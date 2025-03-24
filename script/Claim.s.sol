// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Size} from "@size/src/market/Size.sol";
import {ClaimParams} from "@size/src/market/libraries/actions/Claim.sol";
import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

contract ClaimScript is Script {
    function run() external {
        console.log("Claim...");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address sizeContractAddress = vm.envAddress("SIZE_CONTRACT_ADDRESS");
        uint256 creditPositionId = vm.envUint("CREDIT_POSITION_ID");

        Size size = Size(payable(sizeContractAddress));

        ClaimParams memory params = ClaimParams({creditPositionId: creditPositionId});

        vm.startBroadcast(deployerPrivateKey);
        size.claim(params);
        vm.stopBroadcast();
    }
}
