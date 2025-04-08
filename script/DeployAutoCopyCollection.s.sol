// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {AutoCopyCollection} from "src/authorization/AutoCopyCollection.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ISizeFactory} from "@size/src/factory/interfaces/ISizeFactory.sol";

import {Addresses, CONTRACT} from "./Addresses.s.sol";

contract DeployAutoCopyCollection is Script, Addresses {
    function run() external {
        vm.startBroadcast();

        address admin = Addresses.addresses[block.chainid][CONTRACT.SIZE_GOVERNANCE];
        ISizeFactory factory = ISizeFactory(Addresses.addresses[block.chainid][CONTRACT.SIZE_FACTORY]);

        AutoCopyCollection autoCopyCollection = AutoCopyCollection(
            address(
                new ERC1967Proxy(
                    address(new AutoCopyCollection()), abi.encodeCall(AutoCopyCollection.initialize, (admin, factory))
                )
            )
        );

        console.log("Deployed AutoCopyCollection at:", address(autoCopyCollection));
    }
}
