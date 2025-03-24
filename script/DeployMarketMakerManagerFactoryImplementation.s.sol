// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {MarketMakerManagerFactory} from "src/market-maker/MarketMakerManagerFactory.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployMarketMakerManagerFactoryImplementation is Script {
    function run() external {
        vm.startBroadcast();

        MarketMakerManagerFactory implementation = new MarketMakerManagerFactory();

        console.log("Deployed MarketMakerManagerFactory at:", address(implementation));
    }
}
