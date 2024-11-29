// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {CurvesIntersectionLibrary} from "src/market-maker/CurvesIntersectionLibrary.sol";
import {CurvesIntersectionLibrarySimple} from "src/market-maker/CurvesIntersectionLibrarySimple.sol";
import {YieldCurveHelper} from "@size/test/helpers/libraries/YieldCurveHelper.sol";
import {YieldCurve, VariablePoolBorrowRateParams} from "@size/src/libraries/YieldCurveLibrary.sol";
import {Test} from "forge-std/Test.sol";

contract CurvesIntersectionLibraryTest is Test {
    function test_CurvesIntersectionLibrarySimple_curvesIntersect_normal_flat() public {
        YieldCurve memory curve1 = YieldCurveHelper.normalCurve();
        YieldCurve memory curve2 = YieldCurveHelper.flatCurve();
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool intersects = CurvesIntersectionLibrarySimple.curvesIntersect(
            curve1, curve2, variablePoolBorrowRateParams, 0, 0
        );
        assertTrue(intersects);
    }

    function test_CurvesIntersectionLibrarySimple_curvesIntersect_normal_inverted() public {
        YieldCurve memory curve1 = YieldCurveHelper.normalCurve();
        YieldCurve memory curve2 = YieldCurveHelper.invertedCurve();
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool intersects = CurvesIntersectionLibrarySimple.curvesIntersect(
            curve1, curve2, variablePoolBorrowRateParams, 0, 0
        );
        assertTrue(intersects);
    }

     function test_CurvesIntersectionLibrarySimple_curvesIntersect_normal_steep() public {
        YieldCurve memory normal = YieldCurveHelper.normalCurve();
        YieldCurve memory steep = YieldCurveHelper.steepCurve();
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool intersects = CurvesIntersectionLibrarySimple.curvesIntersect(normal, steep, variablePoolBorrowRateParams, 0, 0);
        assertTrue(!intersects);
     }

     function test_CurvesIntersectionLibrarySimple_curvesIntersect_flat_inverted() public {
        YieldCurve memory flat = YieldCurveHelper.flatCurve();
        YieldCurve memory inverted = YieldCurveHelper.invertedCurve();
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool intersects = CurvesIntersectionLibrarySimple.curvesIntersect(flat, inverted, variablePoolBorrowRateParams, 0, 0);
        assertTrue(intersects);
     }

     function test_CurvesIntersectionLibrarySimple_curvesIntersect_humped_negative() public { 
        YieldCurve memory humped = YieldCurveHelper.humpedCurve();
        YieldCurve memory negative = YieldCurveHelper.negativeCurve();
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        bool intersects = CurvesIntersectionLibrarySimple.curvesIntersect(humped, negative, variablePoolBorrowRateParams, 0, 0);
        assertTrue(!intersects);
    }
}
