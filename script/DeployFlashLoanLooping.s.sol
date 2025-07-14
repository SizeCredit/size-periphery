// SPDX-License-Identifier: MIT

// usage:
// forge script script/DeployFlashLoanLooping.s.sol:DeployFlashLoanLooping --rpc-url sepolia --broadcast --sender [sender] --private-key [private-key]

pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "src/zaps/FlashLoanLooping.sol";
import "./Addresses.s.sol";

contract DeployFlashLoanLooping is Script, Addresses {
    function run() external {
        vm.startBroadcast();

        address addressProvider = addresses[block.chainid][CONTRACT.ADDRESS_PROVIDER];
        address aggregator1inch = addresses[block.chainid][CONTRACT.AGGREGATOR_1INCH];
        address unoswapRouter = addresses[block.chainid][CONTRACT.UNOSWAP_ROUTER];
        address uniswapV2Router = addresses[block.chainid][CONTRACT.UNISWAP_V2_ROUTER];
        address uniswapV3Router = addresses[block.chainid][CONTRACT.UNISWAP_V3_ROUTER];

        FlashLoanLooping flashLoanLooping =
            new FlashLoanLooping(addressProvider, aggregator1inch, unoswapRouter, uniswapV2Router, uniswapV3Router);

        console.log("Deployed FlashLoanLooping at:", address(flashLoanLooping));
        exportDeploymentDetails(
            flashLoanLooping, addressProvider, aggregator1inch, unoswapRouter, uniswapV2Router, uniswapV3Router
        );
    }

    function exportDeploymentDetails(
        FlashLoanLooping flashLoanLooping,
        address addressProvider,
        address aggregator1inch,
        address unoswapRouter,
        address uniswapV2Router,
        address uniswapV3Router
    ) internal {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/");
        string memory chainIdStr = vm.toString(block.chainid);
        path = string.concat(path, string.concat(chainIdStr, ".json"));

        string memory finalObject;
        string memory deploymentsObject;

        // Serialize deployment details
        deploymentsObject = vm.serializeAddress(".deployments", "FlashLoanLooping", address(flashLoanLooping));
        deploymentsObject = vm.serializeAddress(".deployments", "addressProvider", addressProvider);
        deploymentsObject = vm.serializeAddress(".deployments", "aggregator1inch", aggregator1inch);
        deploymentsObject = vm.serializeAddress(".deployments", "unoswapRouter", unoswapRouter);
        deploymentsObject = vm.serializeAddress(".deployments", "uniswapV2Router", uniswapV2Router);
        deploymentsObject = vm.serializeAddress(".deployments", "uniswapV3Router", uniswapV3Router);
        // Combine serialized data
        finalObject = vm.serializeString(".", "deployments", deploymentsObject);

        // Write to JSON
        vm.writeJson(finalObject, path);
    }
} 