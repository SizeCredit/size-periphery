// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@size/src/Size.sol";
import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

contract UpdateBorrowRateOracleScript is Script {
    function run() external {
        console.log("Update Borrow Rate Oracle...");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address sizeContractAddress = vm.envAddress("SIZE_CONTRACT_ADDRESS");
        uint128 newBorrowRate = 60000000000000000; // borrow rate

        console.log("Size Contract Address:", sizeContractAddress);
        console.log("New Borrow Rate (scaled for 18 decimals):", newBorrowRate);

        Size size = Size(payable(sizeContractAddress));

        vm.startBroadcast(deployerPrivateKey);

        size.setVariablePoolBorrowRate(newBorrowRate);

        vm.stopBroadcast();

        console.log("Borrow rate updated successfully.");
    }
}