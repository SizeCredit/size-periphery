// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ISize} from "@size/src/market/interfaces/ISize.sol";
import {DebtPosition, RESERVED_ID} from "@size/src/market/libraries/LoanLibrary.sol";
import {DataView} from "@size/src/market/SizeViewData.sol";
import {PeripheryErrors} from "src/libraries/PeripheryErrors.sol";
import {DepositParams} from "@size/src/market/libraries/actions/Deposit.sol";
import {RepayParams} from "@size/src/market/libraries/actions/Repay.sol";
import {
    SellCreditMarketParams,
    SellCreditMarketOnBehalfOfParams
} from "@size/src/market/libraries/actions/SellCreditMarket.sol";

contract AutoRollover {
    uint256 public constant EARLY_REPAYMENT_BUFFER = 1 hours;

    constructor() {}

    function rollover(
        ISize market,
        uint256 debtPositionId,
        address onBehalfOf,
        address lender,
        uint256 tenor,
        uint256 maxAPR,
        uint256 deadline
    ) external {
        DebtPosition memory debtPosition = market.getDebtPosition(debtPositionId);

        if (debtPosition.dueDate > block.timestamp + EARLY_REPAYMENT_BUFFER) {
            revert PeripheryErrors.AUTO_REPAY_TOO_EARLY(debtPosition.dueDate, block.timestamp);
        }

        market.sellCreditMarketOnBehalfOf(
            SellCreditMarketOnBehalfOfParams({
                params: SellCreditMarketParams({
                    lender: lender,
                    creditPositionId: RESERVED_ID,
                    amount: debtPosition.futureValue,
                    tenor: tenor,
                    maxAPR: maxAPR,
                    deadline: deadline,
                    exactAmountIn: false
                }),
                onBehalfOf: onBehalfOf,
                recipient: address(this)
            })
        );

        market.repay(RepayParams({debtPositionId: debtPositionId, borrower: onBehalfOf}));
    }
}
