// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../src/FlashLoanLiquidation.sol";
import {Vm} from "forge-std/Vm.sol";



contract DeployFlashLoanLiquidator is Script {
    address deployer;
    address owner;
    string chainName;

    function setUp() public {
        // deployer = vm.addr(vm.envOr("DEPLOYER_PRIVATE_KEY", address(0))); 
        deployer = vm.envOr("DEPLOYER_PRIVATE_KEY", address(0)); 
        owner = vm.envOr("OWNER", address(0));
        chainName = "sepolia";
        chainName = vm.envOr("CHAIN_NAME", chainName); 
    }

    modifier broadcast() {
        vm.startBroadcast();
        _;
        vm.stopBroadcast();
    }

    function run() public broadcast {
        console.log("Deploying FlashLoanLiquidator on chain:", chainName);

        address addressProvider = vm.envOr("ADDRESS_PROVIDER", address(0));
        address size = vm.envOr("SIZE_CONTRACT_ADDRESS", address(0));
        address aggregator1inch = vm.envOr("1INCH_AGGREGATOR", address(0));
        address unoswapRouter = vm.envOr("UNOSWAP_ROUTER", address(0));
        address uniswapRouter = vm.envOr("UNISWAP_ROUTER", address(0));
        address collateralToken = vm.envOr("COLLATERAL_TOKEN", address(0));
        address borrowToken = vm.envOr("BORROW_TOKEN", address(0));

        FlashLoanLiquidator flashLoanLiquidator = new FlashLoanLiquidator(
            addressProvider,
            size,
            aggregator1inch,
            unoswapRouter,
            uniswapRouter,
            collateralToken,
            borrowToken
        );

        console.log("Deployed FlashLoanLiquidator at:", address(flashLoanLiquidator));
        exportDeploymentDetails(flashLoanLiquidator, addressProvider, size, aggregator1inch, unoswapRouter, uniswapRouter, collateralToken, borrowToken);
    }

    function exportDeploymentDetails(
        FlashLoanLiquidator flashLoanLiquidator,
        address addressProvider,
        address size,
        address aggregator1inch,
        address unoswapRouter,
        address uniswapRouter,
        address collateralToken,
        address borrowToken
    ) internal {
        string memory path = string(abi.encodePacked(vm.projectRoot(), "/deployments/", chainName, ".json"));
        string memory data = string(abi.encodePacked(
            '{"FlashLoanLiquidator": "',
            Strings.toHexString(address(flashLoanLiquidator)),
            '", "addressProvider": "',
            Strings.toHexString(addressProvider),
            '", "size": "',
            Strings.toHexString(size),
            '", "aggregator1inch": "',
            Strings.toHexString(aggregator1inch),
            '", "unoswapRouter": "',
            Strings.toHexString(unoswapRouter),
            '", "uniswapRouter": "',
            Strings.toHexString(uniswapRouter),
            '", "collateralToken": "',
            Strings.toHexString(collateralToken),
            '", "borrowToken": "',
            Strings.toHexString(borrowToken),
            '"}'
        ));
        vm.writeFile(path, data);
    }
}