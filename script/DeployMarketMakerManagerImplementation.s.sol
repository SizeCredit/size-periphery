// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {MarketMakerManager} from "src/market-maker/MarketMakerManager.sol";

contract DeployMarketMakerManagerImplementation is Script {
    function run() external {
        vm.startBroadcast();

        MarketMakerManager implementation = new MarketMakerManager();

        console.log("Deployed MarketMakerManager at:", address(implementation));

        vm.stopBroadcast();
    }
}
