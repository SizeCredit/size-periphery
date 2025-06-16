// SPDX-License-Identifier: MIT

// usage:
// forge script script/DeployAutoRepay.s.sol:DeployAutoRepay --rpc-url sepolia --broadcast --sender [sender] --private-key [private-key]

pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "src/authorization/AutoRepay.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./Addresses.s.sol";

contract DeployAutoRepay is Script, Addresses {
    function run() external {
        vm.startBroadcast();

        address addressProvider = addresses[block.chainid][CONTRACT.ADDRESS_PROVIDER];
        address aggregator1inch = addresses[block.chainid][CONTRACT.AGGREGATOR_1INCH];
        address unoswapRouter = addresses[block.chainid][CONTRACT.UNOSWAP_ROUTER];
        address uniswapV2Router = addresses[block.chainid][CONTRACT.UNISWAP_V2_ROUTER];
        address uniswapV3Router = addresses[block.chainid][CONTRACT.UNISWAP_V3_ROUTER];

        // Deploy implementation contract
        AutoRepay autoRepayImplementation = new AutoRepay(
            aggregator1inch,
            unoswapRouter,
            uniswapV2Router,
            uniswapV3Router
        );

        console.log("Deployed AutoRepay implementation at:", address(autoRepayImplementation));

        // Prepare initialization data
        // Parameters: owner, addressProvider, earlyRepaymentBuffer (48 days = 48 * 24 * 60 * 60 = 4,147,200 seconds)
        bytes memory initData = abi.encodeWithSelector(
            AutoRepay.initialize.selector,
            msg.sender, // owner
            addressProvider,
            24 hours // earlyRepaymentBuffer
        );

        // Deploy proxy contract
        ERC1967Proxy proxy = new ERC1967Proxy(address(autoRepayImplementation), initData);
        AutoRepay autoRepay = AutoRepay(address(proxy));

        console.log("Deployed AutoRepay proxy at:", address(autoRepay));

        exportDeploymentDetails(
            autoRepay,
            address(autoRepayImplementation),
            addressProvider,
            aggregator1inch,
            unoswapRouter,
            uniswapV2Router,
            uniswapV3Router
        );

        vm.stopBroadcast();
    }

    function exportDeploymentDetails(
        AutoRepay autoRepay,
        address implementation,
        address addressProvider,
        address aggregator1inch,
        address unoswapRouter,
        address uniswapV2Router,
        address uniswapV3Router
    ) internal {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/");
        string memory chainIdStr = vm.toString(block.chainid);
        path = string.concat(path, string.concat(chainIdStr, ".json"));

        string memory finalObject;
        string memory deploymentsObject;

        // Serialize deployment details
        deploymentsObject = vm.serializeAddress(".deployments", "AutoRepay", address(autoRepay));
        deploymentsObject = vm.serializeAddress(".deployments", "AutoRepayImplementation", implementation);
        deploymentsObject = vm.serializeAddress(".deployments", "addressProvider", addressProvider);
        deploymentsObject = vm.serializeAddress(".deployments", "aggregator1inch", aggregator1inch);
        deploymentsObject = vm.serializeAddress(".deployments", "unoswapRouter", unoswapRouter);
        deploymentsObject = vm.serializeAddress(".deployments", "uniswapV2Router", uniswapV2Router);
        deploymentsObject = vm.serializeAddress(".deployments", "uniswapV3Router", uniswapV3Router);
        
        // Combine serialized data
        finalObject = vm.serializeString(".", "deployments", deploymentsObject);

        // Write to JSON
        vm.writeJson(finalObject, path);
    }
} 