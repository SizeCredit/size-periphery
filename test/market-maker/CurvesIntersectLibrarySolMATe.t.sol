// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {console2 as console} from "forge-std/console2.sol";
import {CurvesIntersectionLibrarySolMATe} from "src/market-maker/CurvesIntersectionLibrarySolMATe.sol";
import {PiecewiseIntersectionLibrary} from "src/market-maker/PiecewiseIntersectionLibrary.sol";
import {YieldCurveHelper} from "@size/test/helpers/libraries/YieldCurveHelper.sol";
import {YieldCurve, VariablePoolBorrowRateParams} from "@size/src/libraries/YieldCurveLibrary.sol";
import {PERCENT, YEAR} from "@size/src/libraries/Math.sol";
import {Test} from "forge-std/Test.sol";

contract CurvesIntersectionLibrarySolMATeTest is Test {
    function test_CurvesIntersectionLibrarySolMATe_curvesIntersect_normal_flat() public view {
        YieldCurve memory curve1 = YieldCurveHelper.normalCurve();
        YieldCurve memory curve2 = YieldCurveHelper.flatCurve();
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool intersects = CurvesIntersectionLibrarySolMATe.curvesIntersect(curve1, curve2, variablePoolBorrowRateParams);
        assertTrue(intersects);
    }

    function test_CurvesIntersectionLibrarySolMATe_curvesIntersect_normal_inverted() public view {
        YieldCurve memory curve1 = YieldCurveHelper.normalCurve();
        YieldCurve memory curve2 = YieldCurveHelper.invertedCurve();
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool intersects = CurvesIntersectionLibrarySolMATe.curvesIntersect(curve1, curve2, variablePoolBorrowRateParams);
        assertTrue(intersects);
    }

    function test_CurvesIntersectionLibrarySolMATe_curvesIntersect_normal_steep() public view {
        YieldCurve memory normal = YieldCurveHelper.normalCurve();
        YieldCurve memory steep = YieldCurveHelper.steepCurve();
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool intersects = CurvesIntersectionLibrarySolMATe.curvesIntersect(normal, steep, variablePoolBorrowRateParams);
        assertTrue(!intersects);
    }

    function test_CurvesIntersectionLibrarySolMATe_curvesIntersect_flat_inverted() public view {
        YieldCurve memory flat = YieldCurveHelper.flatCurve();
        YieldCurve memory inverted = YieldCurveHelper.invertedCurve();
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool intersects = CurvesIntersectionLibrarySolMATe.curvesIntersect(flat, inverted, variablePoolBorrowRateParams);
        assertTrue(intersects);
    }

    function test_CurvesIntersectionLibrarySolMATe_curvesIntersect_humped_negative() public view {
        YieldCurve memory humped = YieldCurveHelper.humpedCurve();
        YieldCurve memory negative = YieldCurveHelper.negativeCurve();
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool intersects =
            CurvesIntersectionLibrarySolMATe.curvesIntersect(humped, negative, variablePoolBorrowRateParams);
        assertTrue(!intersects);
    }

    function testFuzz_CurvesIntersectionLibrarySolMATe_curvesIntersect_pointCurve_fails(uint256 x, int256 y)
        public
        view
    {
        x = bound(x, uint256(0), uint256(YEAR * YEAR));
        y = bound(y, int256(0), int256(PERCENT * PERCENT));
        YieldCurve memory curve = YieldCurveHelper.pointCurve(x, y);
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool intersects = CurvesIntersectionLibrarySolMATe.curvesIntersect(curve, curve, variablePoolBorrowRateParams);
        assertTrue(intersects);
    }

    function testFuzz_CurvesIntersectionLibrarySolMATe_curvesIntersect(
        uint256 x1,
        uint256 y1,
        uint256 x2,
        uint256 y2,
        uint256 X1,
        uint256 Y1,
        uint256 X2,
        uint256 Y2,
        bool expected
    ) private view {
        x1 = bound(x1, 0, 10 * YEAR);
        y1 = bound(y1, 0, 100 * PERCENT);
        x2 = bound(x2, x1 + 1, 10 * YEAR + 1);
        y2 = bound(y2, 0, 100 * PERCENT);
        X1 = bound(X1, 0, 10 * YEAR);
        Y1 = bound(Y1, 0, 100 * PERCENT);
        X2 = bound(X2, X1 + 1, 10 * YEAR + 1);
        Y2 = bound(Y2, 0, 100 * PERCENT);

        console.log("(x1, y1)", x1, y1);
        console.log("(x2, y2)", x2, y2);
        console.log("(X1, Y1)", X1, Y1);
        console.log("(X2, Y2)", X2, Y2);

        // revert("This is biased since this function is used inside CurvesIntersectionLibrarySolMATe");
        bool pieceWiseLinearIntersection =
            PiecewiseIntersectionLibrary.pieceWiseLinearIntersection(x1, y1, x2, y2, X1, Y1, X2, Y2);

        YieldCurve memory curve1 = YieldCurveHelper.customCurve(x1, y1, x2, y2);
        YieldCurve memory curve2 = YieldCurveHelper.customCurve(X1, Y1, X2, Y2);

        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool intersects = CurvesIntersectionLibrarySolMATe.curvesIntersect(curve1, curve2, variablePoolBorrowRateParams);
        assertTrue(pieceWiseLinearIntersection == expected ? intersects : !intersects);
    }

    function test_CurvesIntersectionLibrarySolMATe_curvesIntersect_concrete_1() public view {
        uint256 x1 = 1469;
        uint256 y1 = 4662;
        uint256 x2 = 2891;
        uint256 y2 = 90089598632592328463;
        uint256 X1 = 952;
        uint256 Y1 = 5725;
        uint256 X2 = 315359080;
        uint256 Y2 = 1053;
        testFuzz_CurvesIntersectionLibrarySolMATe_curvesIntersect(x1, y1, x2, y2, X1, Y1, X2, Y2, true);
    }

    function test_CurvesIntersectionLibrarySolMATe_curvesIntersect_concrete_2() public view {
        uint256 x1 = 1469;
        uint256 y1 = 4662;
        uint256 x2 = 2891;
        uint256 y2 = 90089598632592328463;
        uint256 X1 = 952;
        uint256 Y1 = 5725;
        uint256 X2 = 315359080;
        uint256 Y2 = 1053;
        testFuzz_CurvesIntersectionLibrarySolMATe_curvesIntersect(x1, y1, x2, y2, X1, Y1, X2, Y2, true);
    }

    function test_CurvesIntersectionLibrarySolMATe_curvesIntersect_concrete_3() public view {
        uint256 x1 = 315359999;
        uint256 y1 = 1178651033205;
        uint256 x2 = 315360000;
        uint256 y2 = 3991797;
        uint256 X1 = 315359997;
        uint256 Y1 = 3;
        uint256 X2 = 315360001;
        uint256 Y2 = 128551179;
        testFuzz_CurvesIntersectionLibrarySolMATe_curvesIntersect(x1, y1, x2, y2, X1, Y1, X2, Y2, true);
    }

    function test_CurvesIntersectionLibrarySolMATe_curvesIntersect_concrete_4() public view {
        uint256 x1 = 315359999;
        uint256 y1 = 1178651033205;
        uint256 x2 = 315360000;
        uint256 y2 = 3991797;
        uint256 X1 = 315359997;
        uint256 Y1 = 3;
        uint256 X2 = 315360001;
        uint256 Y2 = 128551179;
        testFuzz_CurvesIntersectionLibrarySolMATe_curvesIntersect(x1, y1, x2, y2, X1, Y1, X2, Y2, true);
    }

    function test_CurvesIntersectionLibrarySolMATe_curvesIntersect_concrete_5() public view {
        uint256 x1 = 315359999;
        uint256 y1 = 1178651033205;
        uint256 x2 = 315360000;
        uint256 y2 = 3991797;
        uint256 X1 = 315359997;
        uint256 Y1 = 3;
        uint256 X2 = 315360001;
        uint256 Y2 = 128551179;
        testFuzz_CurvesIntersectionLibrarySolMATe_curvesIntersect(x1, y1, x2, y2, X1, Y1, X2, Y2, true);
    }
}
