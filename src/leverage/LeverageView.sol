// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ISize} from "@size/src/interfaces/ISize.sol";
import {Math, PERCENT} from "@size/src/libraries/Math.sol";
import {InitializeRiskConfigParams} from "@size/src/libraries/actions/Initialize.sol";

contract LeverageView {
    function maxLeveragePercent(ISize size) public view returns (uint256) {
        InitializeRiskConfigParams memory riskConfig = size.riskConfig();
        return Math.mulDivDown(PERCENT, riskConfig.crLiquidation, riskConfig.crLiquidation - PERCENT);
    }
}
