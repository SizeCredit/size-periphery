// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {ISize} from "@src/market/interfaces/ISize.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ForkTestVirtualsUSDC is Test {
    ISize public size;
    IERC20 public usdc;
    IERC20 public virtuals;
    address public priceFeed;
    address public owner;

    // Hardcoded addresses for the virtuals-USDC market
    address constant SIZE_PROXY = 0x2a7168C467f97A4C56958b0DDE1144E450a60a36;
    address constant VIRTUALS = 0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant PRICE_FEED = 0x19960f5ffa579a0573BF9b9D0D3258C34F9f69a1;

    function setUp() public virtual {
        vm.createSelectFork("base", 31138987);
        size = ISize(SIZE_PROXY);
        usdc = IERC20(USDC);
        virtuals = IERC20(VIRTUALS);
        priceFeed = PRICE_FEED;
        // Owner is not strictly needed for most tests, but can be set if required
        owner = address(0);
    }
}
