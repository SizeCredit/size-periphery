// SPDX-License-Identifier: MIT

// usage:
// forge script script/DeployFlashLoanContract.s.sol:DeployFlashLoanLiquidator --rpc-url sepolia --broadcast --sender [sender] --private-key [private-key]

pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/FlashLoanLiquidation.sol";
import "@openzeppelin/contracts/utils/Strings.sol";


contract DeployFlashLoanLiquidator is Script {
    function run() external {
        vm.startBroadcast();

        // address addressProvider = vm.envAddress("AAVE_ADDRESS_PROVIDER");
        // address size = vm.envAddress("SIZE_CONTRACT_ADDRESS");
        // address aggregator1inch = vm.envAddress("1INCH_AGGREGATOR");
        // address unoswapRouter = vm.envAddress("UNOSWAP_ROUTER");
        // address uniswapRouter = vm.envAddress("UNISWAP_V2_ROUTER");
        // address collateralToken = vm.envAddress("COLLATERAL_TOKEN");
        // address borrowToken = vm.envAddress("BORROW_TOKEN");

        // https://docs.aave.com/developers/deployed-contracts/v3-mainnet/base
        address addressProvider = 0xe20fCBdBfFC4Dd138cE8b2E6FBb6CB49777ad64D;
        // address size = 0xC2a429681CAd7C1ce36442fbf7A4a68B11eFF940;
        address aggregator1inch = 0x425141165d3DE9FEC831896C016617a52363b687;
        address unoswapRouter = 0x425141165d3DE9FEC831896C016617a52363b687;
        address uniswapRouter = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
        // address collateralToken = 0x4200000000000000000000000000000000000006;
        // address borrowToken = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

        FlashLoanLiquidator flashLoanLiquidator = new FlashLoanLiquidator(
            addressProvider,
            aggregator1inch,
            unoswapRouter,
            uniswapRouter
        );

        console.log("Deployed FlashLoanLiquidator at:", address(flashLoanLiquidator));
        exportDeploymentDetails(flashLoanLiquidator, addressProvider, aggregator1inch, unoswapRouter, uniswapRouter);
    }

    function exportDeploymentDetails(
        FlashLoanLiquidator flashLoanLiquidator,
        address addressProvider,
        address aggregator1inch,
        address unoswapRouter,
        address uniswapRouter
    ) internal {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/");
        string memory chainIdStr = vm.toString(block.chainid);
        path = string.concat(path, string.concat(chainIdStr, ".json"));

        string memory finalObject;
        string memory deploymentsObject;

        // Serialize deployment details
        deploymentsObject = vm.serializeAddress(".deployments", "FlashLoanLiquidator", address(flashLoanLiquidator));
        deploymentsObject = vm.serializeAddress(".deployments", "addressProvider", addressProvider);
        deploymentsObject = vm.serializeAddress(".deployments", "aggregator1inch", aggregator1inch);
        deploymentsObject = vm.serializeAddress(".deployments", "unoswapRouter", unoswapRouter);
        deploymentsObject = vm.serializeAddress(".deployments", "uniswapRouter", uniswapRouter);

        // Combine serialized data
        finalObject = vm.serializeString(".", "deployments", deploymentsObject);

        // Write to JSON
        vm.writeJson(finalObject, path);
    }
}