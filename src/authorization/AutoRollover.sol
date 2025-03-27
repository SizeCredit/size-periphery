// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ISize} from "@size/src/market/interfaces/ISize.sol";
import {DebtPosition, RESERVED_ID} from "@size/src/market/libraries/LoanLibrary.sol";
import {DataView} from "@size/src/market/SizeViewData.sol";
import {PeripheryErrors} from "src/libraries/PeripheryErrors.sol";
import {RepayParams} from "@size/src/market/libraries/actions/Repay.sol";
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

contract AutoRollover is Ownable2Step, FlashLoanReceiverBase {
    using SafeERC20 for IERC20Metadata;

    uint256 public constant EARLY_REPAYMENT_BUFFER = 1 hours;
    uint256 public constant MIN_TENOR = 1 hours;
    uint256 public constant MAX_TENOR = 7 days;

    struct OperationParams {
        ISize market;
        uint256 debtPositionId;
        address onBehalfOf;
        address lender;
        uint256 tenor;
        uint256 maxAPR;
        uint256 deadline;
    }

    constructor(address _owner, IPoolAddressesProvider _addressProvider)
        Ownable(_owner)
        FlashLoanReceiverBase(_addressProvider)
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

        operationParams.market.repay(
            RepayParams({debtPositionId: operationParams.debtPositionId, borrower: operationParams.onBehalfOf})
        );

        IERC20Metadata(assets[0]).forceApprove(address(POOL), newFutureValue);

        return true;
    }
}
