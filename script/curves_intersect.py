import sys
import numpy as np
from datetime import datetime, timedelta
from dataclasses import asdict, dataclass
from math import floor

@dataclass
class OfferCurve:
    curve_relative_time_aprs: list[int]
    curve_relative_time_market_rate_multipliers: list[int]
    curve_relative_time_tenors: list[int]

def _get_point_value(point_index: int, curve: OfferCurve, aave_rate: int) -> tuple[float, float]:
    """Get the (x, y) coordinates of a point on a curve, including AAVE rate adjustment."""
    x = curve.curve_relative_time_tenors[point_index]
    y = curve.curve_relative_time_aprs[point_index] + curve.curve_relative_time_market_rate_multipliers[point_index] * aave_rate
    return x, y

def _check_point_intersection(point1: tuple[float, float], point2: tuple[float, float], threshold: float) -> bool:
    """Check if two points intersect within a given threshold."""
    return np.isclose(point1[0], point2[0], atol=threshold) and np.isclose(point1[1], point2[1], atol=threshold)

def _check_point_on_line_segment(point: tuple[float, float], segment_start: tuple[float, float], 
                               segment_end: tuple[float, float], threshold: float) -> bool:
    """Check if a point lies on a line segment within a given threshold."""
    x, y = point
    x1, y1 = segment_start
    x2, y2 = segment_end
    
    # Check if point is within x-range of segment
    if not (min(x1, x2) <= x <= max(x1, x2)):
        return False
    
    # Handle vertical line
    if x1 == x2:
        return min(y1, y2) <= y <= max(y1, y2)
    
    # Calculate expected y using linear interpolation
    t = (x - x1) / (x2 - x1)
    y_expected = y1 + t * (y2 - y1)
    return np.isclose(y, y_expected, atol=threshold)

def _find_segment_intersection(segment1_start: tuple[float, float], segment1_end: tuple[float, float],
                             segment2_start: tuple[float, float], segment2_end: tuple[float, float],
                             threshold1: float, threshold2: float) -> set[float]:
    """Find intersection points between two line segments."""
    x1, y1 = segment1_start
    x2, y2 = segment1_end
    x3, y3 = segment2_start
    x4, y4 = segment2_end
    
    # Early exit if x-ranges do not overlap
    if max(x1, x2) < min(x3, x4) or max(x3, x4) < min(x1, x2):
        return set()

    # Early exit if one segment is completely above or below the other
    if min(y1, y2) > max(y3, y4) or max(y1, y2) < min(y3, y4):
        return set()

    # Formulate the problem as Ax = b
    A = np.array([
        [x2 - x1, -(x4 - x3)],
        [y2 - y1, -(y4 - y3)]
    ])
    b = np.array([x3 - x1, y3 - y1])

    # Check if the lines are parallel or nearly parallel
    if abs(np.linalg.det(A)) <= threshold1:
        return _handle_parallel_segments(segment1_start, segment1_end, segment2_start, segment2_end, threshold2)

    try:
        # Solve the linear system
        t, s = np.linalg.solve(A, b)
        # Check if the intersection point is within the segment bounds
        if 0 <= t <= 1 and 0 <= s <= 1:
            x_intersect = x1 + t * (x2 - x1)
            return {x_intersect}
    except np.linalg.LinAlgError:
        logger.debug("LinAlgError encountered when solving for intersection")
    
    return set()

def _handle_parallel_segments(segment1_start: tuple[float, float], segment1_end: tuple[float, float],
                            segment2_start: tuple[float, float], segment2_end: tuple[float, float],
                            threshold: float) -> set[float]:
    """Handle the case of parallel or coincident line segments."""
    x1, y1 = segment1_start
    x2, y2 = segment1_end
    x3, y3 = segment2_start
    x4, y4 = segment2_end
    
    # Handle vertical lines
    if x1 == x2 and x3 == x4:
        if x1 == x3 and not (max(y1, y2) < min(y3, y4) or min(y1, y2) > max(y3, y4)):
            return {x1}
        return set()
    
    # Handle non-vertical lines
    if x1 != x2 and x3 != x4:
        slope1 = (y2 - y1) / (x2 - x1)
        slope2 = (y4 - y3) / (x4 - x3)
        intercept1 = y1 - slope1 * x1
        intercept2 = y3 - slope2 * x3
        
        if np.isclose(slope1, slope2, atol=threshold) and np.isclose(intercept1, intercept2, atol=threshold):
            # Lines are coincident, find overlapping region
            overlap_start = max(min(x1, x2), min(x3, x4))
            overlap_end = min(max(x1, x2), max(x3, x4))
            if overlap_start <= overlap_end:
                result = {overlap_start}
                if not np.isclose(overlap_start, overlap_end, atol=threshold):
                    result.add(overlap_end)
                return result
    
    return set()

def find_intersections(curve1: OfferCurve, curve2: OfferCurve, aave_rate: int, threshold1 = 1e-10, threshold2 = 1e-10) -> set[float]:
    """Find intersection points between two offer curves.
    
    Args:
        curve1: First offer curve
        curve2: Second offer curve
        aave_rate: Current AAVE rate
        threshold1: Threshold for determining if lines are parallel
        threshold2: Threshold for numerical precision in intersection point calculation
    
    Returns:
        set: Set of x-coordinates (tenors) where the curves intersect
    """
    # Handle single-point curves
    if len(curve1.curve_relative_time_tenors) == 1 and len(curve2.curve_relative_time_tenors) == 1:
        point1 = _get_point_value(0, curve1, aave_rate)
        point2 = _get_point_value(0, curve2, aave_rate)
        return {point1[0]} if _check_point_intersection(point1, point2, threshold2) else set()

    # Handle case where one curve is a point and the other is a line
    if len(curve1.curve_relative_time_tenors) == 1 or len(curve2.curve_relative_time_tenors) == 1:
        point_curve = curve1 if len(curve1.curve_relative_time_tenors) == 1 else curve2
        line_curve = curve2 if len(curve1.curve_relative_time_tenors) == 1 else curve1
        
        point = _get_point_value(0, point_curve, aave_rate)
        intersections = set()
        
        # Check each segment of the line curve
        for i in range(len(line_curve.curve_relative_time_tenors) - 1):
            segment_start = _get_point_value(i, line_curve, aave_rate)
            segment_end = _get_point_value(i + 1, line_curve, aave_rate)
            
            if _check_point_on_line_segment(point, segment_start, segment_end, threshold2):
                intersections.add(point[0])
        
        return intersections

    # Handle curves with multiple points
    intersections = set()
    for i in range(len(curve1.curve_relative_time_tenors) - 1):
        for j in range(len(curve2.curve_relative_time_tenors) - 1):
            segment1_start = _get_point_value(i, curve1, aave_rate)
            segment1_end = _get_point_value(i + 1, curve1, aave_rate)
            segment2_start = _get_point_value(j, curve2, aave_rate)
            segment2_end = _get_point_value(j + 1, curve2, aave_rate)
            
            intersections.update(_find_segment_intersection(
                segment1_start, segment1_end,
                segment2_start, segment2_end,
                threshold1, threshold2
            ))
    
    return intersections

if __name__ == "__main__":
    # Read input values from command line arguments
    p1x = int(sys.argv[1])
    p1y = int(sys.argv[2])
    p2x = int(sys.argv[3])
    p2y = int(sys.argv[4])
    p3x = int(sys.argv[5])
    p3y = int(sys.argv[6])
    p4x = int(sys.argv[7])
    p4y = int(sys.argv[8])

    # Create curves using input values
    curve1 = OfferCurve(
        curve_relative_time_aprs=[p1y, p4y],
        curve_relative_time_market_rate_multipliers=[0, 0],  # Assuming no market rate multiplier for simplicity
        curve_relative_time_tenors=[p1x, p4x]
    )
    
    curve2 = OfferCurve(
        curve_relative_time_aprs=[p3y, p2y],
        curve_relative_time_market_rate_multipliers=[0, 0],  # Assuming no market rate multiplier for simplicity
        curve_relative_time_tenors=[p3x, p2x]
    )

    # Calculate intersections
    intersections = find_intersections(curve1, curve2, aave_rate=0)  # Assuming aave_rate is 0 for simplicity

    print(bool(intersections))
