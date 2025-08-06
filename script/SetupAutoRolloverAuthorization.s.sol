// SPDX-License-Identifier: MIT

// usage:
// forge script script/SetupAutoRolloverAuthorization.s.sol:SetupAutoRolloverAuthorization --rpc-url sepolia --broadcast --sender [sender] --private-key [private-key]

pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "src/authorization/AutoRollover.sol";
import "./Addresses.s.sol";
import {ISizeFactory} from "@size/src/factory/interfaces/ISizeFactory.sol";
import {ActionsBitmap} from "@size/src/factory/libraries/Authorization.sol";

contract SetupAutoRolloverAuthorization is Script, Addresses {
    function run() external {
        // Get the deployed AutoRollover address from deployment file
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/");
        string memory chainIdStr = vm.toString(block.chainid);
        path = string.concat(path, string.concat(chainIdStr, ".json"));

        string memory deploymentData = vm.readFile(path);
        bytes memory autoRolloverAddressBytes = vm.parseJson(deploymentData, ".deployments.AutoRollover");
        string memory autoRolloverAddressStr = string(autoRolloverAddressBytes);
        address autoRolloverAddress = vm.parseAddress(autoRolloverAddressStr);

        console.log("Setting up authorization for AutoRollover at:", autoRolloverAddress);

        vm.startBroadcast();

        // Get the AutoRollover contract instance
        AutoRollover autoRollover = AutoRollover(autoRolloverAddress);

        // Get the actions bitmap that AutoRollover requires
        ActionsBitmap actionsBitmap = autoRollover.getActionsBitmap();

        console.log("AutoRollover requires actions bitmap - SELL_CREDIT_MARKET permission");

        // Get the Size Factory address
        address sizeFactoryAddress = addresses[block.chainid][CONTRACT.SIZE_FACTORY];
        ISizeFactory sizeFactory = ISizeFactory(sizeFactoryAddress);

        console.log("Size Factory address:", sizeFactoryAddress);

        // Set authorization for the AutoRollover contract
        // Note: This should be called by the borrower or authorized party
        sizeFactory.setAuthorization(autoRolloverAddress, actionsBitmap);

        console.log("Authorization set successfully for AutoRollover");

        vm.stopBroadcast();
    }
}
