// SPDX-License-Identifier: MIT

// usage:
// forge script script/DeployAutoRollover.s.sol:DeployAutoRollover --rpc-url sepolia --broadcast --sender [sender] --private-key [private-key]

pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "src/authorization/AutoRollover.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./Addresses.s.sol";

contract DeployAutoRollover is Script, Addresses {
    function run() external {
        vm.startBroadcast();

        address addressProvider = addresses[block.chainid][CONTRACT.ADDRESS_PROVIDER];

        // Deploy implementation contract
        AutoRollover autoRolloverImplementation = new AutoRollover();

        console.log("Deployed AutoRollover implementation at:", address(autoRolloverImplementation));

        // Prepare initialization data
        // Parameters: owner, addressProvider, earlyRepaymentBuffer, minTenor, maxTenor
        // Using reasonable defaults: 48 days buffer, 1 day min tenor, 365 days max tenor
        bytes memory initData = abi.encodeWithSelector(
            AutoRollover.initialize.selector,
            msg.sender, // owner
            addressProvider,
            24 hours, // earlyRepaymentBuffer
            1 days,  // minTenor
            7 days // maxTenor
        );

        // Deploy proxy contract
        ERC1967Proxy proxy = new ERC1967Proxy(address(autoRolloverImplementation), initData);
        AutoRollover autoRollover = AutoRollover(address(proxy));

        console.log("Deployed AutoRollover proxy at:", address(autoRollover));

        exportDeploymentDetails(
            autoRollover,
            address(autoRolloverImplementation),
            addressProvider
        );

        vm.stopBroadcast();
    }

    function exportDeploymentDetails(
        AutoRollover autoRollover,
        address implementation,
        address addressProvider
    ) internal {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/");
        string memory chainIdStr = vm.toString(block.chainid);
        path = string.concat(path, string.concat(chainIdStr, ".json"));

        string memory finalObject;
        string memory deploymentsObject;

        // Serialize deployment details
        deploymentsObject = vm.serializeAddress(".deployments", "AutoRollover", address(autoRollover));
        deploymentsObject = vm.serializeAddress(".deployments", "AutoRolloverImplementation", implementation);
        deploymentsObject = vm.serializeAddress(".deployments", "addressProvider", addressProvider);
        
        // Combine serialized data
        finalObject = vm.serializeString(".", "deployments", deploymentsObject);

        // Write to JSON
        vm.writeJson(finalObject, path);
    }
} 