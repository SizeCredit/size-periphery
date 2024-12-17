// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {MarketMakerManagerFactory} from "src/MarketMakerManagerFactory.sol";

contract MarketMakerManagerFactoryV2 is MarketMakerManagerFactory {
    function version() external pure returns (uint256) {
        return 2;
    }
}
