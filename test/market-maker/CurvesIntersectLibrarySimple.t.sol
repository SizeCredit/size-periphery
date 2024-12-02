// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {console2 as console} from "forge-std/console2.sol";
import {CurvesIntersectionLibrarySimple} from "src/market-maker/CurvesIntersectionLibrarySimple.sol";
import {PiecewiseIntersectionLibrary} from "src/market-maker/PiecewiseIntersectionLibrary.sol";
import {YieldCurveHelper} from "@size/test/helpers/libraries/YieldCurveHelper.sol";
import {YieldCurve, VariablePoolBorrowRateParams} from "@size/src/libraries/YieldCurveLibrary.sol";
import {AssertsHelper} from "@size/test/helpers/AssertsHelper.sol";
import {PERCENT, YEAR} from "@size/src/libraries/Math.sol";
import {Test} from "forge-std/Test.sol";

contract CurvesIntersectionLibrarySimpleTest is Test {
    function test_CurvesIntersectionLibrarySimple_normal_flat() public view {
        YieldCurve memory curve1 = YieldCurveHelper.normalCurve();
        YieldCurve memory curve2 = YieldCurveHelper.flatCurve();
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool intersects =
            CurvesIntersectionLibrarySimple.curvesIntersect(curve1, curve2, variablePoolBorrowRateParams, 0, 0);
        assertTrue(intersects);
    }

    function test_CurvesIntersectionLibrarySimple_curvesIntersect_normal_inverted() public view {
        YieldCurve memory curve1 = YieldCurveHelper.normalCurve();
        YieldCurve memory curve2 = YieldCurveHelper.invertedCurve();
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool intersects =
            CurvesIntersectionLibrarySimple.curvesIntersect(curve1, curve2, variablePoolBorrowRateParams, 0, 0);
        assertTrue(intersects);
    }

    function test_CurvesIntersectionLibrarySimple_curvesIntersect_normal_steep() public view {
        YieldCurve memory normal = YieldCurveHelper.normalCurve();
        YieldCurve memory steep = YieldCurveHelper.steepCurve();
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool intersects =
            CurvesIntersectionLibrarySimple.curvesIntersect(normal, steep, variablePoolBorrowRateParams, 0, 0);
        assertTrue(!intersects);
    }

    function test_CurvesIntersectionLibrarySimple_curvesIntersect_flat_inverted() public view {
        YieldCurve memory flat = YieldCurveHelper.flatCurve();
        YieldCurve memory inverted = YieldCurveHelper.invertedCurve();
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool intersects =
            CurvesIntersectionLibrarySimple.curvesIntersect(flat, inverted, variablePoolBorrowRateParams, 0, 0);
        assertTrue(intersects);
    }

    function test_CurvesIntersectionLibrarySimple_curvesIntersect_humped_negative() public view {
        YieldCurve memory humped = YieldCurveHelper.humpedCurve();
        YieldCurve memory negative = YieldCurveHelper.negativeCurve();
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool intersects =
            CurvesIntersectionLibrarySimple.curvesIntersect(humped, negative, variablePoolBorrowRateParams, 0, 0);
        assertTrue(!intersects);
    }

    function testFailFuzz_CurvesIntersectionLibrarySimple_curvesIntersect_pointCurve_fails(uint256 x, int256 y)
        public
    {
        YieldCurve memory curve = YieldCurveHelper.pointCurve(x, y);
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool intersects =
            CurvesIntersectionLibrarySimple.curvesIntersect(curve, curve, variablePoolBorrowRateParams, 0, 0);
        assertTrue(intersects);
    }

    function _testFuzz_CurvesIntersectionLibrarySimple_curvesIntersect(
        uint256 x1,
        uint256 y1,
        uint256 x2,
        uint256 y2,
        uint256 X1,
        uint256 Y1,
        uint256 X2,
        uint256 Y2,
        uint256 tolerance
    ) public view {
        x1 = bound(x1, 0, 10 * YEAR);
        y1 = bound(y1, 0, 100 * PERCENT);
        x2 = bound(x2, x1 + 1, 10 * YEAR + 1);
        y2 = bound(y2, 0, 100 * PERCENT);
        X1 = bound(X1, 0, 10 * YEAR);
        Y1 = bound(Y1, 0, 100 * PERCENT);
        X2 = bound(X2, X1 + 1, 10 * YEAR + 1);
        Y2 = bound(Y2, 0, 100 * PERCENT);
        tolerance = bound(tolerance, 0, PERCENT / 100);

        console.log("(x1, y1)", x1, y1);
        console.log("(x2, y2)", x2, y2);
        console.log("(X1, Y1)", X1, Y1);
        console.log("(X2, Y2)", X2, Y2);
        console.log("tolerance", tolerance);

        vm.assume(PiecewiseIntersectionLibrary.pieceWiseLinearIntersection(x1, y1, x2, y2, X1, Y1, X2, Y2));

        YieldCurve memory curve1 = YieldCurveHelper.customCurve(x1, y1, x2, y2);
        YieldCurve memory curve2 = YieldCurveHelper.customCurve(X1, Y1, X2, Y2);

        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool intersects = CurvesIntersectionLibrarySimple.curvesIntersect(
            curve1, curve2, variablePoolBorrowRateParams, tolerance, tolerance
        );
        assertTrue(intersects);
    }

    function testFail_CurvesIntersectionLibrarySimple_curvesIntersect_concrete_fails() public view {
        uint256 x1 = 1469;
        uint256 y1 = 4662;
        uint256 x2 = 2891;
        uint256 y2 = 90089598632592328463;
        uint256 X1 = 952;
        uint256 Y1 = 5725;
        uint256 X2 = 315359080;
        uint256 Y2 = 1053;
        _testFuzz_CurvesIntersectionLibrarySimple_curvesIntersect(x1, y1, x2, y2, X1, Y1, X2, Y2, 0);
    }

    function test_CurvesIntersectionLibrarySimple_curvesIntersect_concrete_succeeds_1_pct_tolerance() public view {
        uint256 x1 = 1469;
        uint256 y1 = 4662;
        uint256 x2 = 2891;
        uint256 y2 = 90089598632592328463;
        uint256 X1 = 952;
        uint256 Y1 = 5725;
        uint256 X2 = 315359080;
        uint256 Y2 = 1053;
        _testFuzz_CurvesIntersectionLibrarySimple_curvesIntersect(x1, y1, x2, y2, X1, Y1, X2, Y2, PERCENT / 100);
    }

    function testFail_CurvesIntersectionLibrarySimple_curvesIntersect_concrete_fails_001_pct_tolerance() public view {
        uint256 x1 = 315359999;
        uint256 y1 = 1178651033205;
        uint256 x2 = 315360000;
        uint256 y2 = 3991797;
        uint256 X1 = 315359997;
        uint256 Y1 = 3;
        uint256 X2 = 315360001;
        uint256 Y2 = 128551179;
        _testFuzz_CurvesIntersectionLibrarySimple_curvesIntersect(x1, y1, x2, y2, X1, Y1, X2, Y2, PERCENT / 1e4);
    }

    function testFail_CurvesIntersectionLibrarySimple_curvesIntersect_concrete_fails_1_pct_tolerance() public view {
        uint256 x1 = 315359999;
        uint256 y1 = 1178651033205;
        uint256 x2 = 315360000;
        uint256 y2 = 3991797;
        uint256 X1 = 315359997;
        uint256 Y1 = 3;
        uint256 X2 = 315360001;
        uint256 Y2 = 128551179;
        _testFuzz_CurvesIntersectionLibrarySimple_curvesIntersect(x1, y1, x2, y2, X1, Y1, X2, Y2, PERCENT / 100);
    }

    function testFail_CurvesIntersectionLibrarySimple_curvesIntersect_concrete_fails_005_pct_tolerance() public view {
        uint256 x1 = 315359999;
        uint256 y1 = 1178651033205;
        uint256 x2 = 315360000;
        uint256 y2 = 3991797;
        uint256 X1 = 315359997;
        uint256 Y1 = 3;
        uint256 X2 = 315360001;
        uint256 Y2 = 128551179;
        uint256 tolerance = 55295820855837;
        _testFuzz_CurvesIntersectionLibrarySimple_curvesIntersect(x1, y1, x2, y2, X1, Y1, X2, Y2, tolerance);
    }
}
