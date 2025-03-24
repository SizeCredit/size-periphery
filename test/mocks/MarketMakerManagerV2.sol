// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {MarketMakerManager} from "src/market-maker/MarketMakerManager.sol";

contract MarketMakerManagerV2 is MarketMakerManager {
    function version() external pure returns (uint256) {
        return 2;
    }
}
