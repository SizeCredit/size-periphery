// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Size} from "@size/src/Size.sol";
import {DataView} from "@size/src/SizeViewData.sol";
import {Logger} from "@test/Logger.sol";
import {CreditPosition, DebtPosition} from "@size/src/libraries/LoanLibrary.sol";

import {RESERVED_ID} from "@size/src/libraries/LoanLibrary.sol";
import {BuyCreditMarketParams} from "@size/src/libraries/actions/BuyCreditMarket.sol";
import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

contract BuyCreditMarketScript is Script, Logger {
    function run() external {
        uint256 lenderPrivateKey = vm.envUint("PRIVATE_KEY");
        address sizeContractAddress = vm.envAddress("SIZE_CONTRACT_ADDRESS");
        Size size = Size(payable(sizeContractAddress));

        uint256 tenor = 2 hours;

        address lender = vm.envAddress("LENDER");
        address borrower = vm.envAddress("BORROWER");

        console.log("lender", lender);
        console.log("borrower", borrower);

        uint256 amount = 50e6;

        uint256 apr = size.getBorrowOfferAPR(borrower, tenor);

        BuyCreditMarketParams memory params = BuyCreditMarketParams({
            borrower: borrower,
            creditPositionId: RESERVED_ID,
            tenor: tenor,
            amount: amount,
            deadline: block.timestamp + 1 minutes,
            minAPR: apr,
            exactAmountIn: false
        });

        /* ------------------ Get next debt and credit position ids ----------------- */
        
        DataView memory data = size.data();
        uint256 nextDebtPositionId = data.nextDebtPositionId;
        uint256 nextCreditPositionId = data.nextCreditPositionId;

        console.log("lender USDC", size.getUserView(lender).borrowATokenBalance);
        vm.startBroadcast(lenderPrivateKey);
        size.buyCreditMarket(params);
        vm.stopBroadcast();
        console.log("lender USDC", size.getUserView(lender).borrowATokenBalance);

        /* ---------------------------- Log new positions --------------------------- */
        CreditPosition memory creditPosition = size.getCreditPosition(nextCreditPositionId);
        console.log("");
        console.log("--- Credit Position ID:", nextCreditPositionId);
        console.log("Lender:", creditPosition.lender);
        console.log("For Sale:", creditPosition.forSale);
        console.log("Credit Amount:", creditPosition.credit);
        console.log("Debt Position ID:", creditPosition.debtPositionId);
        
        DebtPosition memory debtPosition = size.getDebtPosition(nextDebtPositionId);
        console.log("");
        console.log("--- Debt Position ID:", nextDebtPositionId);
        console.log("Borrower:", debtPosition.borrower);
        console.log("Future Value:", debtPosition.futureValue);
        console.log("Due Date:", debtPosition.dueDate);
        console.log("Liquidity Index At Repayment:", debtPosition.liquidityIndexAtRepayment);
    }
}
