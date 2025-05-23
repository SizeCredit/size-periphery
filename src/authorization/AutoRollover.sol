// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ISize} from "@size/src/market/interfaces/ISize.sol";
import {DebtPosition, RESERVED_ID} from "@size/src/market/libraries/LoanLibrary.sol";
import {DataView} from "@size/src/market/SizeViewData.sol";
import {PeripheryErrors} from "src/libraries/PeripheryErrors.sol";
import {RepayParams} from "@size/src/market/libraries/actions/Repay.sol";
import {WithdrawParams} from "@size/src/market/libraries/actions/Withdraw.sol";
import {
    SellCreditMarketParams,
    SellCreditMarketOnBehalfOfParams
} from "@size/src/market/libraries/actions/SellCreditMarket.sol";
import {FlashLoanReceiverBase} from "@aave/flashloan/base/FlashLoanReceiverBase.sol";
import {IPoolAddressesProvider} from "@aave/interfaces/IPoolAddressesProvider.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Errors} from "@size/src/market/libraries/Errors.sol";
import {DexSwap, SwapParams} from "src/liquidator/DexSwap.sol";

contract AutoRollover is Ownable2Step, FlashLoanReceiverBase, DexSwap {
    using SafeERC20 for IERC20Metadata;

    enum OperationType {
        Rollover,
        Repay
    }

    uint256 public constant EARLY_REPAYMENT_BUFFER = 1 hours;
    uint256 public constant MIN_TENOR = 1 hours;
    uint256 public constant MAX_TENOR = 7 days;

    struct OperationParams {
        OperationType operationType;
        ISize market;
        uint256 debtPositionId;
        address onBehalfOf;
        address lender;
        uint256 tenor;
        uint256 maxAPR;
        uint256 deadline;
    }

    struct RepayOperationParams {
        OperationType operationType;
        ISize market;
        uint256 debtPositionId;
        address onBehalfOf;
        uint256 collateralWithdrawAmount;
        SwapParams swapParams;
    }

    constructor(
        address _owner,
        IPoolAddressesProvider _addressProvider,
        address _oneInchAggregator,
        address _unoswapRouter,
        address _uniswapV2Router,
        address _uniswapV3Router
    )
        Ownable(_owner)
        FlashLoanReceiverBase(_addressProvider)
        DexSwap(_oneInchAggregator, _unoswapRouter, _uniswapV2Router, _uniswapV3Router)
    {}

    function rollover(
        ISize market,
        uint256 debtPositionId,
        address onBehalfOf,
        address lender,
        uint256 tenor,
        uint256 maxAPR,
        uint256 deadline
    ) external onlyOwner {
        DebtPosition memory debtPosition = market.getDebtPosition(debtPositionId);
        DataView memory data = market.data();

        if (debtPosition.dueDate > block.timestamp + EARLY_REPAYMENT_BUFFER) {
            revert PeripheryErrors.AUTO_REPAY_TOO_EARLY(debtPosition.dueDate, block.timestamp);
        }

        if (tenor < MIN_TENOR || tenor > MAX_TENOR) {
            revert Errors.TENOR_OUT_OF_RANGE(tenor, MIN_TENOR, MAX_TENOR);
        }

        OperationParams memory operationParams = OperationParams({
            operationType: OperationType.Rollover,
            market: market,
            debtPositionId: debtPositionId,
            onBehalfOf: onBehalfOf,
            lender: lender,
            tenor: tenor,
            maxAPR: maxAPR,
            deadline: deadline
        });

        bytes memory params = abi.encode(operationParams);

        address[] memory assets = new address[](1);
        assets[0] = address(data.underlyingBorrowToken);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = debtPosition.futureValue;
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0;

        POOL.flashLoan(address(this), assets, amounts, modes, address(this), params, 0);
    }

    function repay(
        ISize market,
        uint256 debtPositionId,
        address onBehalfOf,
        uint256 collateralWithdrawAmount,
        SwapParams memory swapParams
    ) external onlyOwner {
        DebtPosition memory debtPosition = market.getDebtPosition(debtPositionId);
        DataView memory data = market.data();

        if (debtPosition.dueDate > block.timestamp + EARLY_REPAYMENT_BUFFER) {
            revert PeripheryErrors.AUTO_REPAY_TOO_EARLY(debtPosition.dueDate, block.timestamp);
        }

        RepayOperationParams memory operationParams = RepayOperationParams({
            operationType: OperationType.Repay,
            market: market,
            debtPositionId: debtPositionId,
            onBehalfOf: onBehalfOf,
            collateralWithdrawAmount: collateralWithdrawAmount,
            swapParams: swapParams
        });

        bytes memory params = abi.encode(operationParams);

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

        // Decode the operation type first
        OperationType operationType = abi.decode(params, (OperationType));

        if (operationType == OperationType.Rollover) {
            OperationParams memory rolloverParams = abi.decode(params, (OperationParams));
            uint256 newFutureValue = amounts[0] + premiums[0];

            rolloverParams.market.sellCreditMarketOnBehalfOf(
                SellCreditMarketOnBehalfOfParams({
                    params: SellCreditMarketParams({
                        lender: rolloverParams.lender,
                        creditPositionId: RESERVED_ID,
                        amount: newFutureValue,
                        tenor: rolloverParams.tenor,
                        maxAPR: rolloverParams.maxAPR,
                        deadline: rolloverParams.deadline,
                        exactAmountIn: false
                    }),
                    onBehalfOf: rolloverParams.onBehalfOf,
                    recipient: address(this)
                })
            );

            rolloverParams.market.repay(
                RepayParams({debtPositionId: rolloverParams.debtPositionId, borrower: rolloverParams.onBehalfOf})
            );

            IERC20Metadata(assets[0]).forceApprove(address(POOL), newFutureValue);
        } else {
            RepayOperationParams memory repayParams = abi.decode(params, (RepayOperationParams));
            uint256 totalDebt = amounts[0] + premiums[0];

            // Repay the debt position
            repayParams.market.repay(
                RepayParams({debtPositionId: repayParams.debtPositionId, borrower: repayParams.onBehalfOf})
            );

            // Withdraw collateral
            repayParams.market.withdraw(
                WithdrawParams({
                    token: address(repayParams.market.data().underlyingCollateralToken),
                    amount: repayParams.collateralWithdrawAmount,
                    to: address(this)
                })
            );

            // Swap collateral for borrow token
            _swapCollateral(
                address(repayParams.market.data().underlyingCollateralToken),
                address(repayParams.market.data().underlyingBorrowToken),
                repayParams.swapParams
            );

            // Approve and repay flash loan
            IERC20Metadata(assets[0]).forceApprove(address(POOL), totalDebt);
        }

        return true;
    }
}
