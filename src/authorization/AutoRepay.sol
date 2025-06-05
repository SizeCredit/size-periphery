// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ISize} from "@size/src/market/interfaces/ISize.sol";
import {RepayParams} from "@size/src/market/libraries/actions/Repay.sol";
import {DebtPosition} from "@size/src/market/libraries/LoanLibrary.sol";
import {DataView} from "@size/src/market/SizeViewData.sol";
import {WithdrawOnBehalfOfParams, WithdrawParams} from "@size/src/market/libraries/actions/Withdraw.sol";
import {DepositOnBehalfOfParams, DepositParams} from "@size/src/market/libraries/actions/Deposit.sol";
import {PeripheryErrors} from "src/libraries/PeripheryErrors.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Errors} from "@size/src/market/libraries/Errors.sol";
import {UpgradeableFlashLoanReceiver} from "./UpgradeableFlashLoanReceiver.sol";
import {DexSwap} from "../liquidator/DexSwap.sol";
import {SwapParams} from "../liquidator/DexSwap.sol";
import {IPoolAddressesProvider} from "@aave/interfaces/IPoolAddressesProvider.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AutoRepay is Initializable, Ownable2StepUpgradeable, UpgradeableFlashLoanReceiver, DexSwap {
    using SafeERC20 for IERC20Metadata;

    // State variables for configurable parameters
    uint256 public earlyRepaymentBuffer;

    // Events for parameter updates
    event EarlyRepaymentBufferUpdated(uint256 oldValue, uint256 newValue);

    struct OperationParams {
        ISize market;
        uint256 debtPositionId;
        address onBehalfOf;
        uint256 collateralAmount;
        SwapParams[] swapParams;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        address _oneInchAggregator,
        address _unoswapRouter,
        address _uniswapV2Router,
        address _uniswapV3Router
    ) DexSwap(_oneInchAggregator, _unoswapRouter, _uniswapV2Router, _uniswapV3Router) {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        IPoolAddressesProvider _addressProvider,
        uint256 _earlyRepaymentBuffer
    ) public initializer {
        __Ownable2Step_init();
        __FlashLoanReceiver_init(_addressProvider);
        _transferOwnership(_owner);

        if (_earlyRepaymentBuffer == 0) {
            revert Errors.NULL_AMOUNT();
        }

        earlyRepaymentBuffer = _earlyRepaymentBuffer;
        emit EarlyRepaymentBufferUpdated(0, _earlyRepaymentBuffer);
    }

    function setEarlyRepaymentBuffer(uint256 _newBuffer) external onlyOwner {
        if (_newBuffer == 0) {
            revert Errors.NULL_AMOUNT();
        }
        uint256 oldBuffer = earlyRepaymentBuffer;
        earlyRepaymentBuffer = _newBuffer;
        emit EarlyRepaymentBufferUpdated(oldBuffer, _newBuffer);
    }

    function repayWithCollateral(
        ISize market,
        uint256 debtPositionId,
        address onBehalfOf,
        uint256 collateralAmount,
        SwapParams[] calldata swapParams
    ) external onlyOwner {
        DebtPosition memory debtPosition = market.getDebtPosition(debtPositionId);
        DataView memory data = market.data();

        if (debtPosition.dueDate > block.timestamp + earlyRepaymentBuffer) {
            revert PeripheryErrors.AUTO_REPAY_TOO_EARLY(debtPosition.dueDate, block.timestamp);
        }

        // Verify collateral amount is not zero
        if (collateralAmount == 0) {
            revert Errors.NULL_AMOUNT();
        }

        OperationParams memory operationParams = OperationParams({
            market: market,
            debtPositionId: debtPositionId,
            onBehalfOf: onBehalfOf,
            collateralAmount: collateralAmount,
            swapParams: swapParams
        });

        bytes memory params = abi.encode(operationParams);

        // Request flash loan for the debt amount
        address[] memory assets = new address[](1);
        assets[0] = address(data.underlyingBorrowToken);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = debtPosition.futureValue;
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0;

        POOL.flashLoan(address(this), assets, amounts, modes, address(this), params, 0);
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        if (msg.sender != address(POOL)) {
            revert PeripheryErrors.NOT_AAVE_POOL();
        }
        if (initiator != address(this)) {
            revert PeripheryErrors.NOT_INITIATOR();
        }

        OperationParams memory operationParams = abi.decode(params, (OperationParams));
        ISize market = operationParams.market;
        DataView memory data = market.data();

        // 1. Deposit flash loaned tokens
        market.depositOnBehalfOf(
            DepositOnBehalfOfParams({
                params: DepositParams({
                    token: address(data.underlyingBorrowToken),
                    amount: amounts[0],
                    to: address(this)
                }),
                onBehalfOf: operationParams.onBehalfOf
            })
        );

        // 2. Repay the loan using deposited tokens
        market.repay(RepayParams({
            debtPositionId: operationParams.debtPositionId,
            borrower: operationParams.onBehalfOf
        }));

        // 3. Withdraw collateral tokens
        market.withdrawOnBehalfOf(WithdrawOnBehalfOfParams({
            params: WithdrawParams({
                token: address(data.underlyingCollateralToken),
                amount: operationParams.collateralAmount,
                to: address(this)
            }),
            onBehalfOf: operationParams.onBehalfOf
        }));

        // 4. Execute swap(s) to convert collateral to debt tokens
        _swap(operationParams.swapParams);

        // 5. Approve and repay flash loan
        uint256 amountOwed = amounts[0] + premiums[0];
        IERC20Metadata(assets[0]).forceApprove(address(POOL), amountOwed);

        return true;
    }
}
