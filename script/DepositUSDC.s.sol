// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@size/src/Size.sol";

import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console2 as console} from "forge-std/console2.sol";
import {UserView} from "@size/src/SizeViewData.sol";


contract DepositUSDCScript is Script {
    function run() external {
        console.log("Deposit USDC...");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address sizeContractAddress = vm.envAddress("SIZE_CONTRACT_ADDRESS");
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        address lender = vm.envAddress("LENDER");
        address borrower = vm.envAddress("BORROWER");

        console.log("Lender Address:", lender);
        console.log("Borrower Address:", borrower);
        console.log("Size Contract Address:", sizeContractAddress);
        console.log("USDC Address:", usdcAddress);

        Size size = Size(payable(sizeContractAddress));
        IERC20 usdc = IERC20(usdcAddress);
        uint256 amount = 100e6; // USDC has 6 decimals

        vm.startBroadcast(deployerPrivateKey);
        // Approve the Size contract to spend USDC
        usdc.approve(sizeContractAddress, amount);
        console.log("");
        console.log("USDC Balance of Lender after approve:", usdc.balanceOf(lender));
        console.log("USDC Allowance after approve:", usdc.allowance(lender, sizeContractAddress));

        // Deposit USDC
        DepositParams memory params = DepositParams({token: usdcAddress, amount: amount, to: lender});
        size.deposit(params);

        // Fetch and log user information
        UserView memory userView = size.getUserView(lender);
        vm.stopBroadcast();

        console.log("");
        console.log("User:", userView.account);
        console.log("Collateral Token Balance:", userView.collateralTokenBalance);
        console.log("Borrow A Token Balance:", userView.borrowATokenBalance);
        console.log("Debt Balance:", userView.debtBalance);
    }
}
