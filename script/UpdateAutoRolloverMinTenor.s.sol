// SPDX-License-Identifier: MIT

// usage:
// forge script script/UpdateAutoRolloverMinTenor.s.sol:UpdateAutoRolloverMinTenor --rpc-url sepolia --broadcast --sender [sender] --private-key [private-key]

pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "src/authorization/AutoRollover.sol";
import "./Addresses.s.sol";

contract UpdateAutoRolloverMinTenor is Script, Addresses {
    function run() external {
        // Get the new minimum tenor value from environment variable
        uint256 newMinTenor = vm.envUint("NEW_MIN_TENOR");

        // Get the deployed AutoRollover address from deployment file
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/");
        string memory chainIdStr = vm.toString(block.chainid);
        path = string.concat(path, string.concat(chainIdStr, ".json"));

        string memory deploymentData = vm.readFile(path);
        bytes memory autoRolloverAddressBytes = vm.parseJson(deploymentData, ".deployments.AutoRollover");
        string memory autoRolloverAddressStr = string(autoRolloverAddressBytes);
        address autoRolloverAddress = vm.parseAddress(autoRolloverAddressStr);

        console.log("Updating AutoRollover minimum tenor at:", autoRolloverAddress);
        console.log("New minimum tenor:", newMinTenor, "seconds");

        vm.startBroadcast();

        // Get the AutoRollover contract instance
        AutoRollover autoRollover = AutoRollover(autoRolloverAddress);

        // Get current values
        uint256 currentMinTenor = autoRollover.minTenor();
        uint256 currentMaxTenor = autoRollover.maxTenor();
        console.log("Current minimum tenor:", currentMinTenor, "seconds");
        console.log("Current maximum tenor:", currentMaxTenor, "seconds");

        // Validate that new minTenor < maxTenor
        if (newMinTenor >= currentMaxTenor) {
            revert("New minimum tenor must be less than current maximum tenor");
        }

        // Update the minimum tenor
        autoRollover.setMinTenor(newMinTenor);

        // Verify the update
        uint256 updatedMinTenor = autoRollover.minTenor();
        console.log("Updated minimum tenor:", updatedMinTenor, "seconds");

        vm.stopBroadcast();

        console.log("Minimum tenor updated successfully!");
    }
}
