// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Script.sol";

import "@size/src/Size.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UserView} from "@size/src/SizeViewData.sol";

interface IWETH {
    function deposit(uint amt) external payable;
}

contract DepositWETHScript is Script {
    function run() external {
        console.log("Deposit WETH...");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address sizeContractAddress = vm.envAddress("SIZE_CONTRACT_ADDRESS");
        address wethAddress = vm.envAddress("WETH_ADDRESS");

        address lender = vm.envAddress("LENDER");
        address borrower = vm.envAddress("BORROWER");

        Size size = Size(payable(sizeContractAddress));
        IERC20 weth = IERC20(wethAddress);
        uint256 amount = 0.02e18;  // 0.02 WETH

        console.log("Lender Address:", lender);
        console.log("Borrower Address:", borrower);
        console.log("Size Contract Address:", sizeContractAddress);
        console.log("WETH Address:", wethAddress);


        // Convert ETH to WETH
        IWETH weth_deposit = IWETH(wethAddress);
        weth_deposit.deposit(amount);

        DepositParams memory params = DepositParams({token: wethAddress, amount: amount, to: borrower});
        vm.startBroadcast(deployerPrivateKey);

        weth.approve(sizeContractAddress, amount);
        console.log("");
        console.log("WETH Balance of Borrower after approve:", weth.balanceOf(borrower));
        console.log("WETH Allowance after approve:", weth.allowance(borrower, sizeContractAddress));

        
        size.deposit(params);
        console.log("");
        console.log("WETH Balance of Borrower after deposit:", weth.balanceOf(borrower));
        console.log("WETH Allowance after deposit:", weth.allowance(borrower, sizeContractAddress));
        // Fetch and log user information
        UserView memory userView = size.getUserView(borrower);

        console.log("");
        console.log("User:", userView.account);
        console.log("Collateral Token Balance:", userView.collateralTokenBalance);
        console.log("Borrow A Token Balance:", userView.borrowATokenBalance);
        console.log("Debt Balance:", userView.debtBalance);

        vm.stopBroadcast();
    }
}
