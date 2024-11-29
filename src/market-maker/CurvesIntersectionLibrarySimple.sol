// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {console2 as console} from "forge-std/console2.sol";
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

    struct IntersectionVars {
        int256 o1;
        int256 o2;
        int256 o3;
        int256 o4;
    }

    // Internal helper function for orientation
    function orientation(uint256 ax, uint256 ay, uint256 bx, uint256 by, uint256 cx, uint256 cy)
        internal
        pure
        returns (int256)
    {
        // Cross product to determine orientation
        // Positive -> Counterclockwise
        // Negative -> Clockwise
        // Zero -> Collinear
        return (int256(bx) - int256(ax)) * (int256(cy) - int256(ay))
            - (int256(by) - int256(ay)) * (int256(cx) - int256(ax));
    }

    // Internal helper function to check if a point is on a segment
    function onSegment(uint256 px, uint256 py, uint256 qx, uint256 qy, uint256 rx, uint256 ry)
        internal
        pure
        returns (bool)
    {
        return rx >= (px < qx ? px : qx) && rx <= (px > qx ? px : qx) && ry >= (py < qy ? py : qy)
            && ry <= (py > qy ? py : qy);
    }

    function pieceWiseLinearIntersection(
        uint256 x1,
        uint256 y1,
        uint256 x2,
        uint256 y2,
        uint256 X1,
        uint256 Y1,
        uint256 X2,
        uint256 Y2
    ) public pure returns (bool intersects) {
        IntersectionVars memory vars;

        // Compute orientations
        vars.o1 = orientation(x1, y1, x2, y2, X1, Y1);
        vars.o2 = orientation(x1, y1, x2, y2, X2, Y2);
        vars.o3 = orientation(X1, Y1, X2, Y2, x1, y1);
        vars.o4 = orientation(X1, Y1, X2, Y2, x2, y2);

        // General case: segments intersect if orientations are different
        if (vars.o1 * vars.o2 < 0 && vars.o3 * vars.o4 < 0) {
            return true;
        }

        // Special case: check if collinear points lie on the segment
        if (vars.o1 == 0 && onSegment(x1, y1, x2, y2, X1, Y1)) return true;
        if (vars.o2 == 0 && onSegment(x1, y1, x2, y2, X2, Y2)) return true;
        if (vars.o3 == 0 && onSegment(X1, Y1, X2, Y2, x1, y1)) return true;
        if (vars.o4 == 0 && onSegment(X1, Y1, X2, Y2, x2, y2)) return true;

        return false;
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
                vars.y1 = SafeCast.toInt256(
                    YieldCurveLibrary.getAdjustedAPR(
                        curve1.aprs[i], curve1.marketRateMultipliers[i], variablePoolBorrowRateParams
                    )
                );
                vars.x2 = SafeCast.toInt256(curve1.tenors[i + 1]);
                vars.y2 = SafeCast.toInt256(
                    YieldCurveLibrary.getAdjustedAPR(
                        curve1.aprs[i + 1], curve1.marketRateMultipliers[i + 1], variablePoolBorrowRateParams
                    )
                );
                vars.x3 = SafeCast.toInt256(curve2.tenors[j]);
                vars.y3 = SafeCast.toInt256(
                    YieldCurveLibrary.getAdjustedAPR(
                        curve2.aprs[j], curve2.marketRateMultipliers[j], variablePoolBorrowRateParams
                    )
                );
                vars.x4 = SafeCast.toInt256(curve2.tenors[j + 1]);
                vars.y4 = SafeCast.toInt256(
                    YieldCurveLibrary.getAdjustedAPR(
                        curve2.aprs[j + 1], curve2.marketRateMultipliers[j + 1], variablePoolBorrowRateParams
                    )
                );

                console.log("(x1, y1)", SafeCast.toUint256(vars.x1), SafeCast.toUint256(vars.y1));
                console.log("(x2, y2)", SafeCast.toUint256(vars.x2), SafeCast.toUint256(vars.y2));
                console.log("(X1, Y1)", SafeCast.toUint256(vars.x3), SafeCast.toUint256(vars.y3));
                console.log("(X2, Y2)", SafeCast.toUint256(vars.x4), SafeCast.toUint256(vars.y4));

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
                    int256 t = ((b1 * deltaY2 - b2 * deltaX2) * int256(PERCENT)) / detA;
                    int256 s = ((b1 * deltaY1 - b2 * deltaX1) * int256(PERCENT)) / detA;

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
