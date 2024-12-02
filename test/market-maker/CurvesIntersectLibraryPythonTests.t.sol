// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {console2 as console} from "forge-std/console2.sol";
import {CurvesIntersectionLibrary} from "src/market-maker/CurvesIntersectionLibrary.sol";
import {PiecewiseIntersectionLibrary} from "src/market-maker/PiecewiseIntersectionLibrary.sol";
import {YieldCurveHelper} from "@size/test/helpers/libraries/YieldCurveHelper.sol";
import {YieldCurve, VariablePoolBorrowRateParams} from "@size/src/libraries/YieldCurveLibrary.sol";
import {AssertsHelper} from "@size/test/helpers/AssertsHelper.sol";
import {PERCENT, YEAR} from "@size/src/libraries/Math.sol";
import {Test} from "forge-std/Test.sol";

contract CurvesIntersectionLibraryPythonTestsTest is Test {
    function test_CurvesIntersectionLibraryPythonTests_curvesIntersect_noIntersection() public view {
        uint256[] memory tenors1 = new uint256[](2);
        tenors1[0] = 0;
        tenors1[1] = 100;

        int256[] memory aprs1 = new int256[](2);
        aprs1[0] = 1000;
        aprs1[1] = 2000;

        uint256[] memory tenors2 = new uint256[](2);
        tenors2[0] = 0;
        tenors2[1] = 100;

        int256[] memory aprs2 = new int256[](2);
        aprs2[0] = 3000;
        aprs2[1] = 4000;

        YieldCurve memory curve1 = YieldCurve({tenors: tenors1, aprs: aprs1, marketRateMultipliers: new uint256[](2)});
        YieldCurve memory curve2 = YieldCurve({tenors: tenors2, aprs: aprs2, marketRateMultipliers: new uint256[](2)});

        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;

        bool intersects = CurvesIntersectionLibrary.curvesIntersect(curve1, curve2, variablePoolBorrowRateParams);
        assertEq(intersects, false);
    }

    function test_CurvesIntersectionLibraryPythonTests_curvesIntersect_singleIntersection() public view {
        uint256[] memory tenors1 = new uint256[](2);
        tenors1[0] = 0;
        tenors1[1] = 100;

        int256[] memory aprs1 = new int256[](2);
        aprs1[0] = 1000;
        aprs1[1] = 3000;

        uint256[] memory tenors2 = new uint256[](2);
        tenors2[0] = 0;
        tenors2[1] = 100;

        int256[] memory aprs2 = new int256[](2);
        aprs2[0] = 3000;
        aprs2[1] = 1000;

        YieldCurve memory curve1 = YieldCurve({tenors: tenors1, aprs: aprs1, marketRateMultipliers: new uint256[](2)});
        YieldCurve memory curve2 = YieldCurve({tenors: tenors2, aprs: aprs2, marketRateMultipliers: new uint256[](2)});

        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;

        bool intersects = CurvesIntersectionLibrary.curvesIntersect(curve1, curve2, variablePoolBorrowRateParams);
        assertEq(intersects, true);
    }

    function test_CurvesIntersectionLibraryPythonTests_curvesIntersect_parallelLines() public view {
        uint256[] memory tenors1 = new uint256[](2);
        tenors1[0] = 0;
        tenors1[1] = 100;

        int256[] memory aprs1 = new int256[](2);
        aprs1[0] = 1000;
        aprs1[1] = 2000;

        uint256[] memory tenors2 = new uint256[](2);
        tenors2[0] = 0;
        tenors2[1] = 100;

        int256[] memory aprs2 = new int256[](2);
        aprs2[0] = 2000;
        aprs2[1] = 3000;

        YieldCurve memory curve1 = YieldCurve({tenors: tenors1, aprs: aprs1, marketRateMultipliers: new uint256[](2)});
        YieldCurve memory curve2 = YieldCurve({tenors: tenors2, aprs: aprs2, marketRateMultipliers: new uint256[](2)});

        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;

        bool intersects = CurvesIntersectionLibrary.curvesIntersect(curve1, curve2, variablePoolBorrowRateParams);
        assertEq(intersects, false);
    }

    function test_CurvesIntersectionLibraryPythonTests_curvesIntersect_singlePoint() public view {
        uint256[] memory tenors1 = new uint256[](1);
        tenors1[0] = 100;

        int256[] memory aprs1 = new int256[](1);
        aprs1[0] = 1000;

        uint256[] memory tenors2 = new uint256[](1);
        tenors2[0] = 100;

        int256[] memory aprs2 = new int256[](1);
        aprs2[0] = 1000;

        YieldCurve memory curve1 = YieldCurve({tenors: tenors1, aprs: aprs1, marketRateMultipliers: new uint256[](1)});
        YieldCurve memory curve2 = YieldCurve({tenors: tenors2, aprs: aprs2, marketRateMultipliers: new uint256[](1)});

        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;

        bool intersects = CurvesIntersectionLibrary.curvesIntersect(curve1, curve2, variablePoolBorrowRateParams);
        assertEq(intersects, true);
    }

    function test_CurvesIntersectionLibraryPythonTests_curvesIntersect_overlappingSegments() public view {
        uint256[] memory tenors1 = new uint256[](3);
        tenors1[0] = 0;
        tenors1[1] = 50;
        tenors1[2] = 100;

        int256[] memory aprs1 = new int256[](3);
        aprs1[0] = 1000;
        aprs1[1] = 2000;
        aprs1[2] = 1000;

        uint256[] memory tenors2 = new uint256[](3);
        tenors2[0] = 0;
        tenors2[1] = 50;
        tenors2[2] = 100;

        int256[] memory aprs2 = new int256[](3);
        aprs2[0] = 500;
        aprs2[1] = 2000;
        aprs2[2] = 2500;

        YieldCurve memory curve1 = YieldCurve({tenors: tenors1, aprs: aprs1, marketRateMultipliers: new uint256[](3)});
        YieldCurve memory curve2 = YieldCurve({tenors: tenors2, aprs: aprs2, marketRateMultipliers: new uint256[](3)});

        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;

        bool intersects = CurvesIntersectionLibrary.curvesIntersect(curve1, curve2, variablePoolBorrowRateParams);
        assertEq(intersects, true);
    }
}
