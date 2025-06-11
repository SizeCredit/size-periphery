// SPDX-License-Identifier: MIT

// usage:
// forge script script/DeployFlashLoanLiquidator.s.sol:DeployFlashLoanLiquidator --rpc-url sepolia --broadcast --sender [sender] --private-key [private-key]

pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "src/liquidator/FlashLoanLiquidator.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./Addresses.s.sol";

contract DeployFlashLoanLiquidator is Script, Addresses {
    function run() external {
        vm.startBroadcast();

        address addressProvider = addresses[block.chainid][CONTRACT.ADDRESS_PROVIDER];

        FlashLoanLiquidator flashLoanLiquidator = new FlashLoanLiquidator(addressProvider);

        console.log("Deployed FlashLoanLiquidator at:", address(flashLoanLiquidator));
        exportDeploymentDetails(flashLoanLiquidator, addressProvider);
    }

    function exportDeploymentDetails(FlashLoanLiquidator flashLoanLiquidator, address addressProvider) internal {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/");
        string memory chainIdStr = vm.toString(block.chainid);
        path = string.concat(path, string.concat(chainIdStr, ".json"));

        string memory finalObject;
        string memory deploymentsObject;

        // Serialize deployment details
        deploymentsObject = vm.serializeAddress(".deployments", "FlashLoanLiquidator", address(flashLoanLiquidator));
        deploymentsObject = vm.serializeAddress(".deployments", "addressProvider", addressProvider);
        // Combine serialized data
        finalObject = vm.serializeString(".", "deployments", deploymentsObject);

        // Write to JSON
        vm.writeJson(finalObject, path);
    }
}
