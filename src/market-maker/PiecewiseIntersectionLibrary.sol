// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

library PiecewiseIntersectionLibrary {
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
        return (SafeCast.toInt256(bx) - SafeCast.toInt256(ax)) * (SafeCast.toInt256(cy) - SafeCast.toInt256(ay))
            - (SafeCast.toInt256(by) - SafeCast.toInt256(ay)) * (SafeCast.toInt256(cx) - SafeCast.toInt256(ax));
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
}
