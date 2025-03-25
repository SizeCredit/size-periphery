// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ISize} from "@size/src/market/interfaces/ISize.sol";
import {RepayParams} from "@size/src/market/libraries/actions/Repay.sol";
import {DebtPosition} from "@size/src/market/libraries/LoanLibrary.sol";
import {DataView} from "@size/src/market/SizeViewData.sol";
import {DepositOnBehalfOfParams, DepositParams} from "@size/src/market/libraries/actions/Deposit.sol";
import {PeripheryErrors} from "src/libraries/PeripheryErrors.sol";

contract AutoRepay {
    uint256 public constant EARLY_REPAYMENT_BUFFER = 1 hours;

    constructor() {}

    function depositOnBehalfOfAndRepay(ISize market, uint256 debtPositionId, address onBehalfOf) external {
        DebtPosition memory debtPosition = market.getDebtPosition(debtPositionId);
        DataView memory data = market.data();

        if (debtPosition.dueDate > block.timestamp + EARLY_REPAYMENT_BUFFER) {
            revert PeripheryErrors.AUTO_REPAY_TOO_EARLY(debtPosition.dueDate, block.timestamp);
        }

        market.depositOnBehalfOf(
            DepositOnBehalfOfParams({
                params: DepositParams({
                    token: address(data.underlyingBorrowToken),
                    amount: debtPosition.futureValue,
                    to: address(this)
                }),
                onBehalfOf: onBehalfOf
            })
        );

        market.repay(RepayParams({debtPositionId: debtPositionId, borrower: onBehalfOf}));
    }
}
