// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {MarketMakerManagerFactory} from "src/MarketMakerManagerFactory.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployMarketMakerManagerFactory is Script {
    function run() external {
        vm.startBroadcast();

        // address governance = vm.envAddress("GOVERNANCE");
        // address bot = vm.envAddress("BOT");
        address governance = 0x462B545e8BBb6f9E5860928748Bfe9eCC712c3a7;
        address bot = 0xDe5C38699a7057a33524F96e62Bb1987C2568816;

        MarketMakerManagerFactory factory = MarketMakerManagerFactory(
            address(
                new ERC1967Proxy(
                    address(new MarketMakerManagerFactory()),
                    abi.encodeCall(MarketMakerManagerFactory.initialize, (governance, bot))
                )
            )
        );

        console.log("Deployed MarketMakerManagerFactory at:", address(factory));
        exportDeploymentDetails(factory, governance, bot);
    }

    function exportDeploymentDetails(MarketMakerManagerFactory factory, address governance, address bot) internal {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/market_maker/");
        string memory chainIdStr = vm.toString(block.chainid);
        path = string.concat(path, string.concat(chainIdStr, ".json"));

        string memory finalObject;
        string memory deploymentsObject;

        deploymentsObject = vm.serializeAddress(".deployments", "MarketMakerManagerFactory", address(factory));
        deploymentsObject = vm.serializeAddress(".deployments", "governance", governance);
        deploymentsObject = vm.serializeAddress(".deployments", "bot", bot);

        finalObject = vm.serializeString(".deployments", "deployments", deploymentsObject);
        vm.writeJson(finalObject, path);
    }
}
