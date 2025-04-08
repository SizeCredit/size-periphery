// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {CopyLimitOrdersForCollection} from "src/authorization/CopyLimitOrdersForCollection.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ISizeFactory} from "@size/src/factory/interfaces/ISizeFactory.sol";

import {Addresses, CONTRACT} from "./Addresses.s.sol";

contract DeployCopyLimitOrdersForCollection is Script, Addresses {
    function run() external {
        vm.startBroadcast();

        address admin = Addresses.addresses[block.chainid][CONTRACT.SIZE_GOVERNANCE];
        ISizeFactory factory = ISizeFactory(Addresses.addresses[block.chainid][CONTRACT.SIZE_FACTORY]);

        CopyLimitOrdersForCollection copyLimitOrdersForCollection = CopyLimitOrdersForCollection(
            address(
                new ERC1967Proxy(
                    address(new CopyLimitOrdersForCollection()),
                    abi.encodeCall(CopyLimitOrdersForCollection.initialize, (admin, factory))
                )
            )
        );

        console.log("Deployed CopyLimitOrdersForCollection at:", address(copyLimitOrdersForCollection));
    }
}
