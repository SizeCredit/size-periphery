// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {YieldCurve, YieldCurveLibrary, VariablePoolBorrowRateParams} from "@size/src/libraries/YieldCurveLibrary.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {PERCENT, Math} from "@size/src/libraries/Math.sol";

library CurvesIntersectionLibrarySimple {
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
    ) public view returns (bool intersects) {
        Vars memory vars;
        for (uint256 i = 0; i < curve1.tenors.length - 1; i++) {
            for (uint256 j = 0; j < curve2.tenors.length - 1; j++) {
                vars.x1 = SafeCast.toInt256(curve1.tenors[i]);
                vars.y1 = SafeCast.toInt256(YieldCurveLibrary.getAdjustedAPR(
                    curve1.aprs[i], curve1.marketRateMultipliers[i], variablePoolBorrowRateParams
                ));
                vars.x2 = SafeCast.toInt256(curve1.tenors[i + 1]);
                vars.y2 = SafeCast.toInt256(YieldCurveLibrary.getAdjustedAPR(
                    curve1.aprs[i + 1], curve1.marketRateMultipliers[i + 1], variablePoolBorrowRateParams
                ));
                vars.x3 = SafeCast.toInt256(curve2.tenors[j]);
                vars.y3 = SafeCast.toInt256(YieldCurveLibrary.getAdjustedAPR(
                    curve2.aprs[j], curve2.marketRateMultipliers[j], variablePoolBorrowRateParams
                ));
                vars.x4 = SafeCast.toInt256(curve2.tenors[j + 1]);
                vars.y4 = SafeCast.toInt256(YieldCurveLibrary.getAdjustedAPR(
                    curve2.aprs[j + 1], curve2.marketRateMultipliers[j + 1], variablePoolBorrowRateParams
                ));

                // Early exit if x-ranges do not overlap
                if (
                    FixedPointMathLib.max(vars.x1, vars.x2) < FixedPointMathLib.min(vars.x3, vars.x4)
                        || FixedPointMathLib.max(vars.x3, vars.x4) < FixedPointMathLib.min(vars.x1, vars.x2)
                ) {
                    continue;
                }

                // Early exit if one segment is completely above or below the other
                if (
                    FixedPointMathLib.min(vars.y1, vars.y2) > FixedPointMathLib.max(vars.y3, vars.y4)
                        || FixedPointMathLib.max(vars.y1, vars.y2) < FixedPointMathLib.min(vars.y3, vars.y4)
                ) {
                    continue;
                }

                // Formulate the problem as Ax = b
                int256 deltaX1 = vars.x2 - vars.x1;
                int256 deltaY1 = vars.y2 - vars.y1;
                int256 deltaX2 = vars.x4 - vars.x3;
                int256 deltaY2 = vars.y4 - vars.y3;

                int256 detA = deltaX1 * deltaY2 - deltaY1 * deltaX2;

                // Check if the lines are parallel taking into account numerical precision
                if (FixedPointMathLib.abs(detA) > threshold1) {
                    // Solve the linear system
                    int256 b1 = vars.x3 - vars.x1;
                    int256 b2 = vars.y3 - vars.y1;
                    int256 t = (b1 * deltaY2 - b2 * deltaX2) * int256(PERCENT) / detA;
                    int256 s = (b1 * deltaY1 - b2 * deltaX1) * int256(PERCENT) / detA;

                    // Check if the intersection point is within the segment bounds
                    if (t >= 0 && t <= int256(PERCENT) && s >= 0 && s <= int256(PERCENT)) {
                        // Numerical Precision Checks
                        int256 xIntersectT = vars.x1 + (t * deltaX1) / int256(PERCENT);
                        int256 xIntersectS = vars.x3 + (s * deltaX2) / int256(PERCENT);
                        if (FixedPointMathLib.abs(xIntersectT - xIntersectS) <= threshold2) {
                            return true;
                        }
                    }
                }
            }
        }

        return false;
    }
}
