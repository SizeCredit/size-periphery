// SPDX-License-Identifier: MIT

// usage:
// forge script script/UpdateAutoRolloverEarlyRepaymentBuffer.s.sol:UpdateAutoRolloverEarlyRepaymentBuffer --rpc-url sepolia --broadcast --sender [sender] --private-key [private-key]

pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "src/authorization/AutoRollover.sol";
import "./Addresses.s.sol";

contract UpdateAutoRolloverEarlyRepaymentBuffer is Script, Addresses {
    function run() external {
        // Get the new early repayment buffer value from environment variable
        // uint256 newBuffer = vm.envUint("NEW_EARLY_REPAYMENT_BUFFER");
        // set new buffer to 7 days in seconds
        uint256 newBuffer = 7 * 24 * 60 * 60;

        
        // Get the deployed AutoRollover address from deployment file
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/");
        string memory chainIdStr = vm.toString(block.chainid);
        path = string.concat(path, string.concat(chainIdStr, ".json"));
        
        // string memory deploymentData = vm.readFile(path);
        // bytes memory autoRolloverAddressBytes = vm.parseJson(deploymentData, ".deployments.AutoRollover");
        // string memory autoRolloverAddressStr = string(autoRolloverAddressBytes);
        // address autoRolloverAddress = vm.parseAddress(autoRolloverAddressStr);
        
        address autoRolloverAddress = 0xA7EF0584ed1eEC3b42D50085A07E47251093ac58;

        console.log("Updating AutoRollover early repayment buffer at:", autoRolloverAddress);
        console.log("New early repayment buffer:", newBuffer, "seconds");
        
        vm.startBroadcast();
        
        // Get the AutoRollover contract instance
        AutoRollover autoRollover = AutoRollover(autoRolloverAddress);
        
        // Get current value
        uint256 currentBuffer = autoRollover.earlyRepaymentBuffer();
        console.log("Current early repayment buffer:", currentBuffer, "seconds");
        
        // Update the early repayment buffer
        autoRollover.setEarlyRepaymentBuffer(newBuffer);
        
        // Verify the update
        uint256 updatedBuffer = autoRollover.earlyRepaymentBuffer();
        console.log("Updated early repayment buffer:", updatedBuffer, "seconds");
        
        vm.stopBroadcast();
        
        console.log("Early repayment buffer updated successfully!");
    }
} 