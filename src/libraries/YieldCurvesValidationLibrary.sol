// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {
    YieldCurve,
    YieldCurveLibrary,
    VariablePoolBorrowRateParams
} from "@size/src/market/libraries/YieldCurveLibrary.sol";
import {Math} from "@size/src/market/libraries/Math.sol";

library YieldCurvesValidationLibrary {
    /// @dev Returns true if curve1 < curve2 for all overlapping segments
    function isBelow(
        YieldCurve memory curve1,
        YieldCurve memory curve2,
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams
    ) public view returns (bool) {
        uint256 i = 0; // Index for curve1
        uint256 j = 0; // Index for curve2

        while (i < curve1.tenors.length && j < curve2.tenors.length) {
            // Find the next tenor contained on both curves to evaluate
            uint256 currentTenor = Math.min(curve1.tenors[i], curve2.tenors[j]);

            // Skip tenors that are outside the range of either curve
            if (currentTenor < curve1.tenors[0] || currentTenor > curve1.tenors[curve1.tenors.length - 1]) {
                j++;
                continue;
            }
            if (currentTenor < curve2.tenors[0] || currentTenor > curve2.tenors[curve2.tenors.length - 1]) {
                i++;
                continue;
            }

            // Calculate APRs at the current tenor
            uint256 aprCurve1 = YieldCurveLibrary.getAPR(curve1, variablePoolBorrowRateParams, currentTenor);
            uint256 aprCurve2 = YieldCurveLibrary.getAPR(curve2, variablePoolBorrowRateParams, currentTenor);

            // If curve1 APR is not strictly less than curve2 APR, the validation fails
            if (aprCurve1 >= aprCurve2) {
                return false;
            }

            // Advance the indices for the next tenor
            if (currentTenor == curve1.tenors[i]) {
                i++;
            }
            if (currentTenor == curve2.tenors[j]) {
                j++;
            }
        }

        // If we exhaust one curve without finding a conflict, validation passes
        return true;
    }
}
