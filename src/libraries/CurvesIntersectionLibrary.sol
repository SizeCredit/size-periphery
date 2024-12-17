// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {YieldCurve, YieldCurveLibrary, VariablePoolBorrowRateParams} from "@size/src/libraries/YieldCurveLibrary.sol";
import {PiecewiseIntersectionLibrary} from "./PiecewiseIntersectionLibrary.sol";

library CurvesIntersectionLibrary {
    function curvesIntersect(
        YieldCurve memory curve1,
        YieldCurve memory curve2,
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams
    ) public view returns (bool intersects) {
        // null curves don't intersect
        if (curve1.tenors.length == 0 || curve2.tenors.length == 0) {
            return false;
        }
        // Handle point curve cases
        if (curve1.tenors.length == 1 && curve2.tenors.length == 1) {
            // Both are single points, check if they coincide
            return (
                curve1.tenors[0] == curve2.tenors[0]
                    && apr(curve1, variablePoolBorrowRateParams, 0) == apr(curve2, variablePoolBorrowRateParams, 0)
            );
        } else if (curve1.tenors.length == 1) {
            // Curve1 is a single point, check if it lies on any segment of Curve2
            return pointIntersectsCurve(
                curve2, variablePoolBorrowRateParams, curve1.tenors[0], apr(curve1, variablePoolBorrowRateParams, 0)
            );
        } else if (curve2.tenors.length == 1) {
            // Curve2 is a single point, check if it lies on any segment of Curve1
            return pointIntersectsCurve(
                curve1, variablePoolBorrowRateParams, curve2.tenors[0], apr(curve2, variablePoolBorrowRateParams, 0)
            );
        }

        // Initialize pointers
        uint256 i = 0;
        uint256 j = 0;

        // Traverse the segments of both curves
        while (i < curve1.tenors.length - 1 && j < curve2.tenors.length - 1) {
            // Extract the segments from each curve
            uint256 x1 = curve1.tenors[i];
            uint256 y1 = apr(curve1, variablePoolBorrowRateParams, i);
            uint256 x2 = curve1.tenors[i + 1];
            uint256 y2 = apr(curve1, variablePoolBorrowRateParams, i + 1);

            uint256 X1 = curve2.tenors[j];
            uint256 Y1 = apr(curve2, variablePoolBorrowRateParams, j);
            uint256 X2 = curve2.tenors[j + 1];
            uint256 Y2 = apr(curve2, variablePoolBorrowRateParams, j + 1);

            // Check for intersection between the current segments
            if (PiecewiseIntersectionLibrary.pieceWiseLinearIntersection(x1, y1, x2, y2, X1, Y1, X2, Y2)) {
                return true; // Curves intersect
            }

            // Move the pointer for the curve whose segment ends earlier
            if (x2 < X2) {
                i++;
            } else {
                j++;
            }
        }

        // No intersection found
        return false;
    }

    // Helper function to check if a single point lies on a curve
    function pointIntersectsCurve(
        YieldCurve memory curve,
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams,
        uint256 px,
        uint256 py
    ) internal view returns (bool) {
        for (uint256 i = 0; i < curve.tenors.length - 1; i++) {
            uint256 x1 = curve.tenors[i];
            uint256 y1 = apr(curve, variablePoolBorrowRateParams, i);
            uint256 x2 = curve.tenors[i + 1];
            uint256 y2 = apr(curve, variablePoolBorrowRateParams, i + 1);

            // Check if point lies on the segment
            if (PiecewiseIntersectionLibrary.pieceWiseLinearIntersection(x1, y1, x2, y2, px, py, px, py)) {
                return true;
            }
        }
        return false;
    }

    function apr(YieldCurve memory curve, VariablePoolBorrowRateParams memory variablePoolBorrowRateParams, uint256 i)
        internal
        view
        returns (uint256)
    {
        return YieldCurveLibrary.getAdjustedAPR(
            curve.aprs[i], curve.marketRateMultipliers[i], variablePoolBorrowRateParams
        );
    }
}
