// SPDX-License-Identifier: MIT

// usage:
// forge script script/UpdateAutoRolloverMaxTenor.s.sol:UpdateAutoRolloverMaxTenor --rpc-url sepolia --broadcast --sender [sender] --private-key [private-key]

pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "src/authorization/AutoRollover.sol";
import "./Addresses.s.sol";

contract UpdateAutoRolloverMaxTenor is Script, Addresses {
    function run() external {
        // Get the new maximum tenor value from environment variable
        uint256 newMaxTenor = vm.envUint("NEW_MAX_TENOR");

        // Get the deployed AutoRollover address from deployment file
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/");
        string memory chainIdStr = vm.toString(block.chainid);
        path = string.concat(path, string.concat(chainIdStr, ".json"));

        string memory deploymentData = vm.readFile(path);
        bytes memory autoRolloverAddressBytes = vm.parseJson(deploymentData, ".deployments.AutoRollover");
        string memory autoRolloverAddressStr = string(autoRolloverAddressBytes);
        address autoRolloverAddress = vm.parseAddress(autoRolloverAddressStr);

        console.log("Updating AutoRollover maximum tenor at:", autoRolloverAddress);
        console.log("New maximum tenor:", newMaxTenor, "seconds");

        vm.startBroadcast();

        // Get the AutoRollover contract instance
        AutoRollover autoRollover = AutoRollover(autoRolloverAddress);

        // Get current values
        uint256 currentMinTenor = autoRollover.minTenor();
        uint256 currentMaxTenor = autoRollover.maxTenor();
        console.log("Current minimum tenor:", currentMinTenor, "seconds");
        console.log("Current maximum tenor:", currentMaxTenor, "seconds");

        // Validate that new maxTenor > minTenor
        if (currentMinTenor >= newMaxTenor) {
            revert("New maximum tenor must be greater than current minimum tenor");
        }

        // Update the maximum tenor
        autoRollover.setMaxTenor(newMaxTenor);

        // Verify the update
        uint256 updatedMaxTenor = autoRollover.maxTenor();
        console.log("Updated maximum tenor:", updatedMaxTenor, "seconds");

        vm.stopBroadcast();

        console.log("Maximum tenor updated successfully!");
    }
}
