// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {MarketMakerManagerFactory} from "src/MarketMakerManagerFactory.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployMarketMakerFactory is Script {
    function run() external {
        vm.startBroadcast();

        address governance = vm.envAddress("GOVERNANCE");
        address bot = vm.envAddress("BOT");

        MarketMakerManagerFactory factory = MarketMakerManagerFactory(
            address(
                new ERC1967Proxy(
                    address(new MarketMakerManagerFactory()),
                    abi.encodeCall(MarketMakerManagerFactory.initialize, (governance, bot))
                )
            )
        );

        console.log("Deployed MarketMakerManagerFactory at:", address(factory));
    }
}
