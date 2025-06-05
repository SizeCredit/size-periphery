// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Script.sol";
import "src/zaps/LeverageUp.sol";
import "./Addresses.s.sol";

contract DeployLeverageUp is Script, Addresses {
    function run() external {
        vm.startBroadcast();

        LeverageUp leverageUp = new LeverageUp(
            address(type(uint160).max),
            address(type(uint160).max),
            addresses[block.chainid][CONTRACT.UNISWAP_V2_ROUTER],
            addresses[block.chainid][CONTRACT.UNISWAP_V3_ROUTER]
        );

        console.log("Deployed LeverageUp at:", address(leverageUp));
    }
}
