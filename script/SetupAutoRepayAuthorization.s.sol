// SPDX-License-Identifier: MIT

// usage:
// forge script script/SetupAutoRepayAuthorization.s.sol:SetupAutoRepayAuthorization --rpc-url sepolia --broadcast --sender [sender] --private-key [private-key]

pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "src/authorization/AutoRepay.sol";
import "./Addresses.s.sol";
import {ISizeFactory} from "@size/src/factory/interfaces/ISizeFactory.sol";
import {ActionsBitmap} from "@size/src/factory/libraries/Authorization.sol";

contract SetupAutoRepayAuthorization is Script, Addresses {
    function run() external {
        // Get the deployed AutoRepay address from deployment file
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/");
        string memory chainIdStr = vm.toString(block.chainid);
        path = string.concat(path, string.concat(chainIdStr, ".json"));

        string memory deploymentData = vm.readFile(path);
        bytes memory autoRepayAddressBytes = vm.parseJson(deploymentData, ".deployments.AutoRepay");
        string memory autoRepayAddressStr = string(autoRepayAddressBytes);
        address autoRepayAddress = vm.parseAddress(autoRepayAddressStr);

        console.log("Setting up authorization for AutoRepay at:", autoRepayAddress);

        vm.startBroadcast();

        // Get the AutoRepay contract instance
        AutoRepay autoRepay = AutoRepay(autoRepayAddress);

        // Get the actions bitmap that AutoRepay requires
        ActionsBitmap actionsBitmap = autoRepay.getActionsBitmap();

        console.log("AutoRepay requires actions bitmap - DEPOSIT and WITHDRAW permissions");

        // Get the Size Factory address
        address sizeFactoryAddress = addresses[block.chainid][CONTRACT.SIZE_FACTORY];
        ISizeFactory sizeFactory = ISizeFactory(sizeFactoryAddress);

        console.log("Size Factory address:", sizeFactoryAddress);

        // Set authorization for the AutoRepay contract
        // Note: This should be called by the borrower or authorized party
        sizeFactory.setAuthorization(autoRepayAddress, actionsBitmap);

        console.log("Authorization set successfully for AutoRepay");

        vm.stopBroadcast();
    }
}
