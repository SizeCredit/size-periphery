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

        address addressProvider = 0x012bAC54348C0E635dCAc9D5FB99f06F24136C9A;
        address size = 0x2345988Ec6c0196821177B90F5e919f18F5324F3;
        address aggregator1inch = 0x425141165d3DE9FEC831896C016617a52363b687;
        address unoswapRouter = 0x425141165d3DE9FEC831896C016617a52363b687;
        address uniswapRouter = 0x425141165d3DE9FEC831896C016617a52363b687;
        address collateralToken = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
        address borrowToken = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;

        FlashLoanLiquidator flashLoanLiquidator = new FlashLoanLiquidator(
            addressProvider,
            size,
            aggregator1inch,
            unoswapRouter,
            uniswapRouter,
            collateralToken,
            borrowToken
        );

        console.log("Deployed FlashLoanLiquidator at:", address(flashLoanLiquidator));
        exportDeploymentDetails(flashLoanLiquidator, addressProvider, size, aggregator1inch, unoswapRouter, uniswapRouter, collateralToken, borrowToken);
    }

    function exportDeploymentDetails(
        FlashLoanLiquidator flashLoanLiquidator,
        address addressProvider,
        address size,
        address aggregator1inch,
        address unoswapRouter,
        address uniswapRouter,
        address collateralToken,
        address borrowToken
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
        deploymentsObject = vm.serializeAddress(".deployments", "size", size);
        deploymentsObject = vm.serializeAddress(".deployments", "aggregator1inch", aggregator1inch);
        deploymentsObject = vm.serializeAddress(".deployments", "unoswapRouter", unoswapRouter);
        deploymentsObject = vm.serializeAddress(".deployments", "uniswapRouter", uniswapRouter);
        deploymentsObject = vm.serializeAddress(".deployments", "collateralToken", collateralToken);
        deploymentsObject = vm.serializeAddress(".deployments", "borrowToken", borrowToken);

        // Combine serialized data
        finalObject = vm.serializeString(".", "deployments", deploymentsObject);

        // Write to JSON
        vm.writeJson(finalObject, path);
    }
}