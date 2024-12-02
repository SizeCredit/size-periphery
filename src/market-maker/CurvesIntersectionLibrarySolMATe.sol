// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {console2 as console} from "forge-std/console2.sol";
import {YieldCurve, YieldCurveLibrary, VariablePoolBorrowRateParams} from "@size/src/libraries/YieldCurveLibrary.sol";
import {PERCENT} from "@size/src/libraries/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {VectorUtils} from "@SolMATe/VectorUtils.sol";
import {MatrixUtils} from "@SolMATe/MatrixUtils.sol";

int256 constant IPERCENT = int256(PERCENT);

library CurvesIntersectionLibrarySolMATe {
    struct Vars {
        int256 x1;
        int256 y1;
        int256 x2;
        int256 y2;
        int256 xPoint;
        int256 yPoint;
        int256 xStart;
        int256 yStart;
        int256 xEnd;
        int256 yEnd;
    }

    struct Vars2 {
        int256 x1Start;
        int256 y1Start;
        int256 x1End;
        int256 y1End;
        int256 x2Start;
        int256 y2Start;
        int256 x2End;
        int256 y2End;
    }

    function curvesIntersect(
        YieldCurve memory curve1,
        YieldCurve memory curve2,
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams,
        int256 threshold1,
        int256 threshold2
    ) public view returns (bool intersects) {
        Vars memory vars;

        console.log("1");
        // Handle single-point curves
        if (curve1.tenors.length == 1 && curve2.tenors.length == 1) {
            (vars.x1, vars.y1) = _getPointValue(0, curve1, variablePoolBorrowRateParams);
            (vars.x2, vars.y2) = _getPointValue(0, curve2, variablePoolBorrowRateParams);
            return _checkPointIntersection(vars.x1, vars.y1, vars.x2, vars.y2, threshold2);
        }
        console.log("2");

        // Handle case where one curve is a point and the other is a line
        if (curve1.tenors.length == 1 || curve2.tenors.length == 1) {
            YieldCurve memory pointCurve = curve1.tenors.length == 1 ? curve1 : curve2;
            YieldCurve memory lineCurve = curve1.tenors.length == 1 ? curve2 : curve1;

            (vars.xPoint, vars.yPoint) = _getPointValue(0, pointCurve, variablePoolBorrowRateParams);

            // Check each segment of the line curve
            for (uint256 i = 0; i < lineCurve.tenors.length - 1; i++) {
                (vars.xStart, vars.yStart) = _getPointValue(i, lineCurve, variablePoolBorrowRateParams);
                (vars.xEnd, vars.yEnd) = _getPointValue(i + 1, lineCurve, variablePoolBorrowRateParams);
                if (
                    _checkPointOnLineSegment(
                        vars.xPoint, vars.yPoint, vars.xStart, vars.yStart, vars.xEnd, vars.yEnd, threshold2
                    )
                ) {
                    return true;
                }
            }
            return false;
        }
        console.log("3");

        Vars2 memory vars2;
        // Handle curves with multiple points
        for (uint256 i = 0; i < curve1.tenors.length - 1; i++) {
            for (uint256 j = 0; j < curve2.tenors.length - 1; j++) {
                (vars2.x1Start, vars2.y1Start) = _getPointValue(i, curve1, variablePoolBorrowRateParams);
                (vars2.x1End, vars2.y1End) = _getPointValue(i + 1, curve1, variablePoolBorrowRateParams);
                (vars2.x2Start, vars2.y2Start) = _getPointValue(j, curve2, variablePoolBorrowRateParams);
                (vars2.x2End, vars2.y2End) = _getPointValue(j + 1, curve2, variablePoolBorrowRateParams);
                console.log("4");

                if (
                    _findSegmentIntersection(
                        vars2.x1Start,
                        vars2.y1Start,
                        vars2.x1End,
                        vars2.y1End,
                        vars2.x2Start,
                        vars2.y2Start,
                        vars2.x2End,
                        vars2.y2End,
                        threshold1
                    )
                ) {
                    return true;
                }
            }
        }
        return false;
    }

    function curvesIntersect(
        YieldCurve memory curve1,
        YieldCurve memory curve2,
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams
    ) public view returns (bool intersects) {
        return curvesIntersect(curve1, curve2, variablePoolBorrowRateParams, IPERCENT / 1e10, IPERCENT / 1e10);
    }

    function _getPointValue(
        uint256 pointIndex,
        YieldCurve memory curve,
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams
    ) internal view returns (int256, int256) {
        int256 x = SafeCast.toInt256(curve.tenors[pointIndex]);
        int256 y = SafeCast.toInt256(
            YieldCurveLibrary.getAdjustedAPR(
                curve.aprs[pointIndex], curve.marketRateMultipliers[pointIndex], variablePoolBorrowRateParams
            )
        );
        return (x, y);
    }

    function _checkPointIntersection(int256 x1, int256 y1, int256 x2, int256 y2, int256 threshold)
        internal
        pure
        returns (bool)
    {
        return _isClose(x1, x2, threshold, IPERCENT / 1e8) && _isClose(y1, y2, threshold, IPERCENT / 1e8);
    }

    // https://numpy.org/doc/2.1/reference/generated/numpy.isclose.html#numpy-isclose
    function _isClose(int256 a, int256 b, int256 atol, int256 rtol) internal pure returns (bool) {
        return SafeCast.toInt256(FixedPointMathLib.abs(a - b))
            <= (atol + rtol * SafeCast.toInt256(FixedPointMathLib.abs(b)));
    }

    function _checkPointOnLineSegment(int256 x, int256 y, int256 x1, int256 y1, int256 x2, int256 y2, int256 threshold)
        internal
        pure
        returns (bool)
    {
        // Check if point is within x-range of segment
        if (!(FixedPointMathLib.min(x1, x2) <= x && x <= FixedPointMathLib.max(x1, x2))) {
            return false;
        }

        // Handle vertical line
        if (x1 == x2) {
            return FixedPointMathLib.min(y1, y2) <= y && y <= FixedPointMathLib.max(y1, y2);
        }

        // Calculate expected y using linear interpolation
        int256 t = IPERCENT * (x - x1) / (x2 - x1);
        int256 yExpected = y1 + (t * (y2 - y1)) / IPERCENT;
        return _isClose(y, yExpected, threshold, IPERCENT / 1e8);
    }

    function _determinant(int256[][] memory matrix) private pure returns (int256) {
        return matrix[0][0] * matrix[1][1] - matrix[0][1] * matrix[1][0];
    }

    function _print(int256[] memory vector) private pure {
        for (uint256 i = 0; i < vector.length; i++) {
            console.log("vector[%s]:", i);
            console.log("            %s", vector[i]);
        }
        console.log("");
    }

    function _print(int256[][] memory matrix) private pure {
        for (uint256 i = 0; i < matrix.length; i++) {
            for (uint256 j = 0; j < matrix[i].length; j++) {
                console.log("matrix[%s][%s]:", i, j);
                console.log("                %s", matrix[i][j]);
            }
        }
        console.log("");
    }

    function _solve2x2(int256[][] memory A, int256[] memory b) private pure returns (int256, int256) {
        console.log("x4");
        int256[][] memory q;
        int256[][] memory r;
        int256[][] memory b_mat = VectorUtils.toMatrix(VectorUtils.convertTo59x18(b));
        console.log("x5");
        int256[][] memory converted = MatrixUtils.convertTo59x18(A);
        _print(A);
        _print(b);
        _print(converted);
        (q, r) = MatrixUtils.QRDecomposition(MatrixUtils.convertTo59x18(A));
        console.log("x6");
        int256[][] memory res = MatrixUtils.backSubstitute(r, MatrixUtils.dot(MatrixUtils.T(q), b_mat));
        console.log("x7");
        return (res[0][0], res[1][0]);
    }

    function _findSegmentIntersection(
        int256 x1,
        int256 y1,
        int256 x2,
        int256 y2,
        int256 x3,
        int256 y3,
        int256 x4,
        int256 y4,
        int256 threshold1
    ) internal pure returns (bool) {
        // Early exit if x-ranges do not overlap
        if (
            FixedPointMathLib.max(x1, x2) < FixedPointMathLib.min(x3, x4)
                || FixedPointMathLib.max(x3, x4) < FixedPointMathLib.min(x1, x2)
        ) {
            return false;
        }

        // Early exit if one segment is completely above or below the other
        if (
            FixedPointMathLib.min(y1, y2) > FixedPointMathLib.max(y3, y4)
                || FixedPointMathLib.max(y1, y2) < FixedPointMathLib.min(y3, y4)
        ) {
            return false;
        }

        console.log("x1");
        // Formulate the problem as Ax = b
        int256[][] memory A = new int256[][](2);
        A[0] = new int256[](2);
        A[1] = new int256[](2);
        A[0][0] = x2 - x1;
        A[0][1] = -(x4 - x3);
        A[1][0] = y2 - y1;
        A[1][1] = -(y4 - y3);

        int256[] memory b = new int256[](2);
        b[0] = x3 - x1;
        b[1] = y3 - y1;

        console.log("x2");

        // Check if the lines are parallel or nearly parallel
        if (SafeCast.toInt256(FixedPointMathLib.abs(_determinant(A))) <= threshold1) {
            return false; // Assuming we don't need to handle parallel segments for boolean output
        }

        console.log("x3");

        // Solve the linear system
        (int256 t, int256 s) = _solve2x2(A, b);
        if (t >= 0 && t <= IPERCENT && s >= 0 && s <= IPERCENT) {
            return true;
        }
        return false;
    }
}
