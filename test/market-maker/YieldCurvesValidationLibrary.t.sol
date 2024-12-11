// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {console} from "forge-std/console.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {YieldCurvesValidationLibrary} from "src/market-maker/YieldCurvesValidationLibrary.sol";
import {PiecewiseIntersectionLibrary} from "src/market-maker/PiecewiseIntersectionLibrary.sol";
import {YieldCurveHelper} from "@size/test/helpers/libraries/YieldCurveHelper.sol";
import {YieldCurve, VariablePoolBorrowRateParams} from "@size/src/libraries/YieldCurveLibrary.sol";
import {CurvesIntersectionLibrary} from "src/market-maker/CurvesIntersectionLibrary.sol";
import {PERCENT, YEAR} from "@size/src/libraries/Math.sol";
import {Test} from "forge-std/Test.sol";

contract YieldCurvesValidationLibraryTest is Test {
    function test_YieldCurvesValidationLibrary_isBelow_normal_flat() public view {
        YieldCurve memory curve1 = YieldCurveHelper.normalCurve();
        YieldCurve memory curve2 = YieldCurveHelper.flatCurve();
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool isBelow = YieldCurvesValidationLibrary.isBelow(curve1, curve2, variablePoolBorrowRateParams);
        assertTrue(!isBelow);
    }

    function test_YieldCurvesValidationLibrary_isBelow_normal_inverted() public view {
        YieldCurve memory curve1 = YieldCurveHelper.normalCurve();
        YieldCurve memory curve2 = YieldCurveHelper.invertedCurve();
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool isBelow = YieldCurvesValidationLibrary.isBelow(curve1, curve2, variablePoolBorrowRateParams);
        assertTrue(!isBelow);
    }

    function test_YieldCurvesValidationLibrary_isBelow_normal_steep() public view {
        YieldCurve memory normal = YieldCurveHelper.normalCurve();
        YieldCurve memory steep = YieldCurveHelper.steepCurve();

        // steep is completely above normal

        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool isBelow = YieldCurvesValidationLibrary.isBelow(normal, steep, variablePoolBorrowRateParams);
        assertTrue(isBelow);

        isBelow = YieldCurvesValidationLibrary.isBelow(steep, normal, variablePoolBorrowRateParams);
        assertTrue(!isBelow);
    }

    function test_YieldCurvesValidationLibrary_isBelow_flat_inverted() public view {
        YieldCurve memory flat = YieldCurveHelper.flatCurve();
        YieldCurve memory inverted = YieldCurveHelper.invertedCurve();
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool isBelow = YieldCurvesValidationLibrary.isBelow(flat, inverted, variablePoolBorrowRateParams);
        assertTrue(!isBelow);
    }

    function test_YieldCurvesValidationLibrary_isBelow_humped_negative() public view {
        YieldCurve memory humped = YieldCurveHelper.humpedCurve();
        YieldCurve memory negative = YieldCurveHelper.negativeCurve();
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;

        // humped is completely below negative

        bool isBelow = YieldCurvesValidationLibrary.isBelow(humped, negative, variablePoolBorrowRateParams);
        assertTrue(isBelow);

        isBelow = YieldCurvesValidationLibrary.isBelow(negative, humped, variablePoolBorrowRateParams);
        assertTrue(!isBelow);
    }

    function testFuzz_YieldCurvesValidationLibrary_isBelow_pointCurve_fails(uint256 x, int256 y) public view {
        x = bound(x, uint256(0), uint256(YEAR * YEAR));
        y = bound(y, int256(0), int256(PERCENT * PERCENT));
        YieldCurve memory curve = YieldCurveHelper.pointCurve(x, y);
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool isBelow = YieldCurvesValidationLibrary.isBelow(curve, curve, variablePoolBorrowRateParams);
        assertTrue(!isBelow);
    }

    function testFuzz_YieldCurvesValidationLibrary_isBelow(
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

        // revert("This is biased since this function is used inside YieldCurvesValidationLibrary");
        bool pieceWiseLinearIntersection =
            PiecewiseIntersectionLibrary.pieceWiseLinearIntersection(x1, y1, x2, y2, X1, Y1, X2, Y2);

        YieldCurve memory curve1 = YieldCurveHelper.customCurve(x1, y1, x2, y2);
        YieldCurve memory curve2 = YieldCurveHelper.customCurve(X1, Y1, X2, Y2);

        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool isBelow = YieldCurvesValidationLibrary.isBelow(curve1, curve2, variablePoolBorrowRateParams);
        console.log("isBelow", isBelow);
        assertTrue(pieceWiseLinearIntersection == expected ? !isBelow : isBelow);
    }

    function test_YieldCurvesValidationLibrary_isBelow_concrete_1() public view {
        uint256 x1 = 1469;
        uint256 y1 = 4662;
        uint256 x2 = 2891;
        uint256 y2 = 90089598632592328463;
        uint256 X1 = 952;
        uint256 Y1 = 5725;
        uint256 X2 = 315359080;
        uint256 Y2 = 1053;
        testFuzz_YieldCurvesValidationLibrary_isBelow(x1, y1, x2, y2, X1, Y1, X2, Y2, true);
    }

    function test_YieldCurvesValidationLibrary_isBelow_concrete_2() public view {
        uint256 x1 = 1469;
        uint256 y1 = 4662;
        uint256 x2 = 2891;
        uint256 y2 = 90089598632592328463;
        uint256 X1 = 952;
        uint256 Y1 = 5725;
        uint256 X2 = 315359080;
        uint256 Y2 = 1053;
        testFuzz_YieldCurvesValidationLibrary_isBelow(x1, y1, x2, y2, X1, Y1, X2, Y2, true);
    }

    function test_YieldCurvesValidationLibrary_isBelow_concrete_3() public view {
        uint256 x1 = 315359999;
        uint256 y1 = 1178651033205;
        uint256 x2 = 315360000;
        uint256 y2 = 3991797;
        uint256 X1 = 315359997;
        uint256 Y1 = 3;
        uint256 X2 = 315360001;
        uint256 Y2 = 128551179;
        testFuzz_YieldCurvesValidationLibrary_isBelow(x1, y1, x2, y2, X1, Y1, X2, Y2, true);
    }

    function test_YieldCurvesValidationLibrary_isBelow_concrete_4() public view {
        uint256 x1 = 315359999;
        uint256 y1 = 1178651033205;
        uint256 x2 = 315360000;
        uint256 y2 = 3991797;
        uint256 X1 = 315359997;
        uint256 Y1 = 3;
        uint256 X2 = 315360001;
        uint256 Y2 = 128551179;
        testFuzz_YieldCurvesValidationLibrary_isBelow(x1, y1, x2, y2, X1, Y1, X2, Y2, true);
    }

    function test_YieldCurvesValidationLibrary_isBelow_concrete_5() public view {
        uint256 x1 = 315359999;
        uint256 y1 = 1178651033205;
        uint256 x2 = 315360000;
        uint256 y2 = 3991797;
        uint256 X1 = 315359997;
        uint256 Y1 = 3;
        uint256 X2 = 315360001;
        uint256 Y2 = 128551179;
        testFuzz_YieldCurvesValidationLibrary_isBelow(x1, y1, x2, y2, X1, Y1, X2, Y2, true);
    }

    function testFuzz_YieldCurvesValidationLibrary_isBelow_inverted(
        uint256 p1x,
        uint256 p1y,
        uint256 p2x,
        uint256 p2y,
        uint256 p3y,
        uint256 p4y
    ) public view {
        /*
      |         P2
      |        / 
      | P1    /           
      |  \   /          
      |   \ /           
      |    /            
      |   / \           
      | P3   \          
      |       \         
      |        \        
      |         P4      
      +-----------------
        */

        p1x = bound(p1x, 1, 1 * YEAR);
        p2x = bound(p2x, p1x + 1, 1 * YEAR + 1);

        p1y = bound(p1y, 1 + 2, 1 * PERCENT + 2);
        p2y = bound(p2y, p1y + 1, 1 * PERCENT + 2 + 1);

        uint256 p3x = p1x;
        p3y = bound(p3y, 0 + 1, p1y - 1);
        uint256 p4x = p2x;
        p4y = bound(p4y, 0, p3y - 1);

        console.log("P1 = (%s,%s)", p1x, p1y);
        console.log("P2 = (%s,%s)", p2x, p2y);
        console.log("P3 = (%s,%s)", p3x, p3y);
        console.log("P4 = (%s,%s)", p4x, p4y);

        YieldCurve memory curve1 = YieldCurveHelper.customCurve(p1x, p1y, p4x, p4y);
        YieldCurve memory curve2 = YieldCurveHelper.customCurve(p3x, p3y, p2x, p2y);
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool isBelow = YieldCurvesValidationLibrary.isBelow(curve1, curve2, variablePoolBorrowRateParams);
        assertTrue(!isBelow);
    }

    function testFuzz_YieldCurvesValidationLibrary_isBelow_not(
        uint256 p1x,
        uint256 p1y,
        uint256 p2x,
        uint256 p2y,
        uint256 p3y,
        uint256 p4y
    ) public view {
        /*
      |     P2
      |    /
      |   /
      | P1
      |
      | P3
      |   \
      |    \
      |     P4
      +-----------------
        */

        p1x = bound(p1x, 1, 1 * YEAR);
        p2x = bound(p2x, p1x + 1, 1 * YEAR + 1);

        p1y = bound(p1y, 0 + 2, 1 * PERCENT + 2);
        p2y = bound(p2y, p1y + 1, 1 * PERCENT + 2 + 1);

        uint256 p3x = p1x;
        p3y = bound(p3y, 0 + 1, p1y - 1);
        uint256 p4x = p2x;
        p4y = bound(p4y, 0, p3y - 1);

        console.log("P1 = (%s,%s)", p1x, p1y);
        console.log("P2 = (%s,%s)", p2x, p2y);
        console.log("P3 = (%s,%s)", p3x, p3y);
        console.log("P4 = (%s,%s)", p4x, p4y);

        YieldCurve memory curve1 = YieldCurveHelper.customCurve(p1x, p1y, p2x, p2y);
        YieldCurve memory curve2 = YieldCurveHelper.customCurve(p3x, p3y, p4x, p4y);
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool isBelow = YieldCurvesValidationLibrary.isBelow(curve1, curve2, variablePoolBorrowRateParams);
        assertTrue(!isBelow);

        isBelow = YieldCurvesValidationLibrary.isBelow(curve2, curve1, variablePoolBorrowRateParams);
        assertTrue(isBelow);
    }

    function testFuzz_YieldCurvesValidationLibrary_isBelow_point_true(uint256 p1x, uint256 p1y, uint256 p4x)
        public
        view
    {
        /*
      |
      | P1 ---- P5 ---- P4        
      |
      +-----------------
        */

        p1x = bound(p1x, 1, 1 * YEAR);
        p4x = bound(p4x, p1x + 3, 1 * YEAR + 3);

        p1y = bound(p1y, 1, 1 * PERCENT);
        uint256 p4y = p1y;

        uint256 p5x = (p1x + p4x) / 2;
        uint256 p5y = p1y;

        console.log("P1 = (%s,%s)", p1x, p1y);
        console.log("P4 = (%s,%s)", p4x, p4y);
        console.log("P5 = (%s,%s)", p5x, p5y);

        YieldCurve memory curve1 = YieldCurveHelper.customCurve(p1x, p1y, p4x, p4y);
        YieldCurve memory curve2 = YieldCurveHelper.pointCurve(p5x, SafeCast.toInt256(p5y));
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool isBelow = YieldCurvesValidationLibrary.isBelow(curve1, curve2, variablePoolBorrowRateParams);
        assertTrue(!isBelow);

        isBelow = YieldCurvesValidationLibrary.isBelow(curve2, curve1, variablePoolBorrowRateParams);
        assertTrue(!isBelow);
    }

    function testFuzz_YieldCurvesValidationLibrary_isBelow_point_false(uint256 p1x, uint256 p1y, uint256 p4x)
        public
        view
    {
        /*
      |
      | P1 ---- P4      P5        
      |
      +-----------------
        */

        p1x = bound(p1x, 1, 1 * YEAR);
        p4x = bound(p4x, p1x + 3, 1 * YEAR + 3);

        p1y = bound(p1y, 1, 1 * PERCENT);
        uint256 p4y = p1y;

        uint256 p5x = (p1x + p4x);
        uint256 p5y = p1y;

        console.log("P1 = (%s,%s)", p1x, p1y);
        console.log("P4 = (%s,%s)", p4x, p4y);
        console.log("P5 = (%s,%s)", p5x, p5y);

        YieldCurve memory curve1 = YieldCurveHelper.customCurve(p1x, p1y, p4x, p4y);
        YieldCurve memory curve2 = YieldCurveHelper.pointCurve(p5x, SafeCast.toInt256(p5y));
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool isBelow = YieldCurvesValidationLibrary.isBelow(curve1, curve2, variablePoolBorrowRateParams);
        assertTrue(isBelow);

        isBelow = YieldCurvesValidationLibrary.isBelow(curve2, curve1, variablePoolBorrowRateParams);
        assertTrue(isBelow);
    }

    function testFuzz_YieldCurvesValidationLibrary_isBelow_same_initial_point(
        uint256 p1x,
        uint256 p1y,
        uint256 p2x,
        uint256 p2y,
        uint256 p4y
    ) public view {
        /*
      |     P2
      |    /
      |   /
      | P1
      |   \
      |    \
      |     P4
      +-----------------
        */

        p1x = bound(p1x, 1, 1 * YEAR);
        p2x = bound(p2x, p1x + 1, 1 * YEAR + 1);

        p1y = bound(p1y, 0 + 2, 1 * PERCENT + 2);
        p2y = bound(p2y, p1y + 1, 1 * PERCENT + 2 + 1);

        uint256 p4x = p2x;
        p4y = bound(p4y, 0, p1y - 1);

        console.log("P1 = (%s,%s)", p1x, p1y);
        console.log("P2 = (%s,%s)", p2x, p2y);
        console.log("P4 = (%s,%s)", p4x, p4y);

        YieldCurve memory curve1 = YieldCurveHelper.customCurve(p1x, p1y, p2x, p2y);
        YieldCurve memory curve2 = YieldCurveHelper.customCurve(p1x, p1y, p4x, p4y);
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool isBelow = YieldCurvesValidationLibrary.isBelow(curve1, curve2, variablePoolBorrowRateParams);
        assertTrue(!isBelow);
    }

    function testFuzz_YieldCurvesValidationLibrary_isBelow_same_final_point(
        uint256 p1x,
        uint256 p1y,
        uint256 p2x,
        uint256 p2y,
        uint256 p3y
    ) public view {
        /*
      | P1
      |   \
      |     P2
      |   /
      | P3
      +-----------------
        */

        p1x = bound(p1x, 1, 1 * YEAR);
        p2x = bound(p2x, p1x + 1, 1 * YEAR + 1);

        p1y = bound(p1y, 0 + 2, 1 * PERCENT + 2);
        p2y = bound(p2y, p1y + 1, 1 * PERCENT + 2 + 1);

        uint256 p3x = p1x;
        p3y = bound(p3y, 0 + 1, p1y - 1);

        console.log("P1 = (%s,%s)", p1x, p1y);
        console.log("P2 = (%s,%s)", p2x, p2y);
        console.log("P3 = (%s,%s)", p3x, p3y);

        YieldCurve memory curve1 = YieldCurveHelper.customCurve(p1x, p1y, p2x, p2y);
        YieldCurve memory curve2 = YieldCurveHelper.customCurve(p3x, p3y, p2x, p2y);
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool isBelow = YieldCurvesValidationLibrary.isBelow(curve1, curve2, variablePoolBorrowRateParams);
        assertTrue(!isBelow);
    }

    function testFuzzFFI_YieldCurvesValidationLibrary_isBelow_ignore_false_negatives(
        uint256 p1x,
        uint256 p2x,
        uint256 p1y,
        uint256 p2y,
        uint256 p3y,
        uint256 p4y
    ) public {
        p1x = bound(p1x, 1 days, 30 days);
        p2x = bound(p2x, p1x + 30 days, 3 * 30 days);
        uint256 p3x = p1x;
        uint256 p4x = p2x;

        p1y = bound(p1y, PERCENT / 100, 5 * PERCENT / 100);
        p2y = bound(p2y, PERCENT / 100, 5 * PERCENT / 100);
        p3y = bound(p3y, PERCENT / 100, 5 * PERCENT / 100);
        p4y = bound(p4y, PERCENT / 100, 5 * PERCENT / 100);

        console.log("P1 = (%s,%s)", p1x, p1y);
        console.log("P2 = (%s,%s)", p2x, p2y);
        console.log("P3 = (%s,%s)", p3x, p3y);
        console.log("P4 = (%s,%s)", p4x, p4y);

        string[] memory inputs = new string[](10);
        inputs[0] = "python3";
        inputs[1] = "./script/curves_intersect.py";
        inputs[2] = vm.toString(p1x);
        inputs[3] = vm.toString(p1y);
        inputs[4] = vm.toString(p2x);
        inputs[5] = vm.toString(p2y);
        inputs[6] = vm.toString(p3x);
        inputs[7] = vm.toString(p3y);
        inputs[8] = vm.toString(p4x);
        inputs[9] = vm.toString(p4y);

        bytes memory result = vm.ffi(inputs);

        bool pythonResult = keccak256(result) == keccak256(bytes("True"));

        YieldCurve memory curve1 = YieldCurveHelper.customCurve(p1x, p1y, p4x, p4y);
        YieldCurve memory curve2 = YieldCurveHelper.customCurve(p3x, p3y, p2x, p2y);
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;

        bool solidityResult = YieldCurvesValidationLibrary.isBelow(curve1, curve2, variablePoolBorrowRateParams);

        if (!solidityResult) {
            assertEq(solidityResult, !pythonResult, "Solidity != Python");
        }
    }

    function testFuzzFFI_YieldCurvesValidationLibrary_isBelow_all(
        uint256 p1x,
        uint256 p2x,
        uint256 p1y,
        uint256 p2y,
        uint256 p3y,
        uint256 p4y
    ) public {
        p1x = bound(p1x, 1 days, 30 days);
        p2x = bound(p2x, p1x + 30 days, 3 * 30 days);
        uint256 p3x = p1x;
        uint256 p4x = p2x;

        p1y = bound(p1y, PERCENT / 100, 5 * PERCENT / 100);
        p2y = bound(p2y, PERCENT / 100, 5 * PERCENT / 100);
        p3y = bound(p3y, PERCENT / 100, 5 * PERCENT / 100);
        p4y = bound(p4y, PERCENT / 100, 5 * PERCENT / 100);

        vm.assume(
            FixedPointMathLib.abs(SafeCast.toInt256(p1y) - SafeCast.toInt256(p3y)) > PERCENT / (10 * 100)
                && FixedPointMathLib.abs(SafeCast.toInt256(p2y) - SafeCast.toInt256(p4y)) > PERCENT / (10 * 100)
        );

        console.log("P1 = (%s,%s)", p1x, p1y);
        console.log("P2 = (%s,%s)", p2x, p2y);
        console.log("P3 = (%s,%s)", p3x, p3y);
        console.log("P4 = (%s,%s)", p4x, p4y);

        string[] memory inputs = new string[](10);
        inputs[0] = "python3";
        inputs[1] = "./script/curves_intersect.py";
        inputs[2] = vm.toString(p1x);
        inputs[3] = vm.toString(p1y);
        inputs[4] = vm.toString(p2x);
        inputs[5] = vm.toString(p2y);
        inputs[6] = vm.toString(p3x);
        inputs[7] = vm.toString(p3y);
        inputs[8] = vm.toString(p4x);
        inputs[9] = vm.toString(p4y);

        bytes memory result = vm.ffi(inputs);

        bool pythonResult = keccak256(result) == keccak256(bytes("True"));

        YieldCurve memory curve1 = YieldCurveHelper.customCurve(p1x, p1y, p4x, p4y);
        YieldCurve memory curve2 = YieldCurveHelper.customCurve(p3x, p3y, p2x, p2y);
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;

        bool solidityResult = YieldCurvesValidationLibrary.isBelow(curve1, curve2, variablePoolBorrowRateParams);

        assertEq(solidityResult, !pythonResult, "Solidity != Python");
    }

    function testFuzz_YieldCurvesValidationLibrary_CurvesIntersectionLibrary_differential(
        uint256 x1,
        uint256 x2,
        uint256 y1,
        uint256 y2,
        uint256 X1,
        uint256 X2,
        uint256 Y1,
        uint256 Y2
    ) public view {
        x1 = bound(x1, 1, 1 * YEAR);
        x2 = bound(x2, x1 + 1, 1 * YEAR + 1);

        X1 = bound(X1, 1, 1 * YEAR);
        X2 = bound(X2, X1 + 1, 1 * YEAR + 1);

        y1 = bound(y1, 1, 1 * PERCENT);
        y2 = bound(y2, 1, 1 * PERCENT);

        Y1 = bound(Y1, 1, 1 * PERCENT);
        Y2 = bound(Y2, 1, 1 * PERCENT);

        console.log("x1x2 = %s,%s", x1, x2);
        console.log("X1X2 = %s,%s", X1, X2);
        console.log("y1y2 = %s,%s", y1, y2);
        console.log("Y1Y2 = %s,%s", Y1, Y2);

        YieldCurve memory curve1 = YieldCurveHelper.customCurve(x1, y1, x2, y2);
        YieldCurve memory curve2 = YieldCurveHelper.customCurve(X1, Y1, X2, Y2);
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool isBelow = YieldCurvesValidationLibrary.isBelow(curve1, curve2, variablePoolBorrowRateParams);
        bool intersects = CurvesIntersectionLibrary.curvesIntersect(curve1, curve2, variablePoolBorrowRateParams);
        assertTrue(intersects ? !isBelow : true);
    }
}
