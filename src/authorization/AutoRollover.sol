// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ISize} from "@size/src/market/interfaces/ISize.sol";
import {DebtPosition, RESERVED_ID} from "@size/src/market/libraries/LoanLibrary.sol";
import {DataView, UserView} from "@size/src/market/SizeViewData.sol";
import {PeripheryErrors} from "src/libraries/PeripheryErrors.sol";
import {RepayParams} from "@size/src/market/libraries/actions/Repay.sol";
import {
    SellCreditMarketParams,
    SellCreditMarketOnBehalfOfParams
} from "@size/src/market/libraries/actions/SellCreditMarket.sol";
import {DepositOnBehalfOfParams, DepositParams} from "@size/src/market/libraries/actions/Deposit.sol";
import {IPoolAddressesProvider} from "@aave/interfaces/IPoolAddressesProvider.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Errors} from "@size/src/market/libraries/Errors.sol";
import {UpgradeableFlashLoanReceiver} from "./UpgradeableFlashLoanReceiver.sol";
import {IRequiresAuthorization} from "./IRequiresAuthorization.sol";
import {ActionsBitmap, Action, Authorization} from "@size/src/factory/libraries/Authorization.sol";
import {WithdrawParams} from "@size/src/market/libraries/actions/Withdraw.sol";

contract AutoRollover is Initializable, Ownable2StepUpgradeable, UpgradeableFlashLoanReceiver {
    using SafeERC20 for IERC20Metadata;

    // State variables for configurable parameters
    uint256 public earlyRepaymentBuffer;
    uint256 public minTenor;
    uint256 public maxTenor;

    // Events for parameter updates
    event EarlyRepaymentBufferUpdated(uint256 oldValue, uint256 newValue);
    event MinTenorUpdated(uint256 oldValue, uint256 newValue);
    event MaxTenorUpdated(uint256 oldValue, uint256 newValue);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        IPoolAddressesProvider _addressProvider,
        uint256 _earlyRepaymentBuffer,
        uint256 _minTenor,
        uint256 _maxTenor
    ) public initializer {
        __Ownable2Step_init();
        __FlashLoanReceiver_init(_addressProvider);
        _transferOwnership(_owner);

        if (_minTenor >= _maxTenor) {
            revert Errors.INVALID_TENOR_RANGE(_minTenor, _maxTenor);
        }
        if (_earlyRepaymentBuffer == 0) {
            revert Errors.NULL_AMOUNT();
        }

        earlyRepaymentBuffer = _earlyRepaymentBuffer;
        minTenor = _minTenor;
        maxTenor = _maxTenor;

        emit EarlyRepaymentBufferUpdated(0, _earlyRepaymentBuffer);
        emit MinTenorUpdated(0, _minTenor);
        emit MaxTenorUpdated(0, _maxTenor);
    }

    function setEarlyRepaymentBuffer(uint256 _newBuffer) external onlyOwner {
        if (_newBuffer == 0) {
            revert Errors.NULL_AMOUNT();
        }
        uint256 oldBuffer = earlyRepaymentBuffer;
        earlyRepaymentBuffer = _newBuffer;
        emit EarlyRepaymentBufferUpdated(oldBuffer, _newBuffer);
    }

    function setMinTenor(uint256 _newMinTenor) external onlyOwner {
        if (_newMinTenor >= maxTenor) {
            revert Errors.INVALID_TENOR_RANGE(_newMinTenor, maxTenor);
        }
        uint256 oldMinTenor = minTenor;
        minTenor = _newMinTenor;
        emit MinTenorUpdated(oldMinTenor, _newMinTenor);
    }

    function setMaxTenor(uint256 _newMaxTenor) external onlyOwner {
        if (minTenor >= _newMaxTenor) {
            revert Errors.INVALID_TENOR_RANGE(minTenor, _newMaxTenor);
        }
        uint256 oldMaxTenor = maxTenor;
        maxTenor = _newMaxTenor;
        emit MaxTenorUpdated(oldMaxTenor, _newMaxTenor);
    }

    struct OperationParams {
        ISize market;
        uint256 debtPositionId;
        address onBehalfOf;
        address lender;
        uint256 tenor;
        uint256 maxAPR;
        uint256 deadline;
    }

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

        if (debtPosition.dueDate > block.timestamp + earlyRepaymentBuffer) {
            revert PeripheryErrors.AUTO_REPAY_TOO_EARLY(debtPosition.dueDate, block.timestamp);
        }

        if (tenor < minTenor || tenor > maxTenor) {
            revert Errors.TENOR_OUT_OF_RANGE(tenor, minTenor, maxTenor);
        }

        OperationParams memory operationParams = OperationParams({
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
        uint256 newFutureValue = amounts[0] + premiums[0];

        // Deposit underlying borrow token to receive borrowAToken
        IERC20Metadata(assets[0]).forceApprove(address(operationParams.market), amounts[0]);
        operationParams.market.deposit(DepositParams({token: assets[0], amount: amounts[0], to: address(this)}));

        // Repay debt position
        operationParams.market.repay(
            RepayParams({debtPositionId: operationParams.debtPositionId, borrower: operationParams.onBehalfOf})
        );

        // Take new loan
        operationParams.market.sellCreditMarketOnBehalfOf(
            SellCreditMarketOnBehalfOfParams({
                params: SellCreditMarketParams({
                    lender: operationParams.lender,
                    creditPositionId: RESERVED_ID,
                    amount: newFutureValue,
                    tenor: operationParams.tenor,
                    maxAPR: operationParams.maxAPR,
                    deadline: operationParams.deadline,
                    exactAmountIn: false
                }),
                onBehalfOf: operationParams.onBehalfOf,
                recipient: address(this)
            })
        );

        // Withdraw underlying borrow token to repay flashloan
        operationParams.market.withdraw(
            WithdrawParams({token: assets[0], amount: amounts[0] + premiums[0], to: address(this)})
        );

        IERC20Metadata(assets[0]).forceApprove(address(POOL), newFutureValue);
        return true;
    }

    function getActionsBitmap() external pure returns (ActionsBitmap) {
        Action[] memory actions = new Action[](1);
        actions[0] = Action.SELL_CREDIT_MARKET;
        return Authorization.getActionsBitmap(actions);
    }
}
