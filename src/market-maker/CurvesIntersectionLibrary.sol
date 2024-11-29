// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {YieldCurve, YieldCurveLibrary, VariablePoolBorrowRateParams} from "@size/src/libraries/YieldCurveLibrary.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {PERCENT} from "@size/src/libraries/Math.sol";

library CurvesIntersectionLibrary {
    struct Vars {
        int256 x1;
        int256 y1;
        int256 x2;
        int256 y2;
        int256 x3;
        int256 y3;
        int256 x4;
        int256 y4;
    }

    function curvesIntersect(
        YieldCurve memory curve1,
        YieldCurve memory curve2,
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams,
        uint256 threshold1,
        uint256 threshold2
    ) public pure returns (bool intersects) {
        return false;
    }
}
