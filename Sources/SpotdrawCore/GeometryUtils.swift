// GeometryUtils.swift
// Caseless enum namespace for geometry calculations used by drawing item hit-tests.

import Cocoa

// MARK: - GeometryUtils

/// Caseless enum used as a namespace for shared geometry calculations.
public enum GeometryUtils {

    // MARK: - Line Segment Distance

    /// Calculates the shortest distance from a point to a line segment.
    ///
    /// Uses vector projection: projects `point` onto the infinite line through
    /// `segmentStart` and `segmentEnd`, clamps the parameter t to [0, 1] to
    /// restrict to the segment, then returns the Euclidean distance to the
    /// clamped projection.
    public static func distance(from point: CGPoint, toLineSegmentFrom segmentStart: CGPoint, to segmentEnd: CGPoint) -> CGFloat {
        let dx = segmentEnd.x - segmentStart.x
        let dy = segmentEnd.y - segmentStart.y
        let lengthSquared = dx * dx + dy * dy

        if lengthSquared == 0 {
            let ddx = point.x - segmentStart.x
            let ddy = point.y - segmentStart.y
            return sqrt(ddx * ddx + ddy * ddy)
        }

        var t = ((point.x - segmentStart.x) * dx + (point.y - segmentStart.y) * dy) / lengthSquared
        t = Swift.max(0, Swift.min(1, t))

        let projX = segmentStart.x + t * dx
        let projY = segmentStart.y + t * dy

        let distX = point.x - projX
        let distY = point.y - projY
        return sqrt(distX * distX + distY * distY)
    }
}

// MARK: - DrawingItem Line-Segment Hit-Test

extension DrawingItem {
    /// Default hit-test for line-segment shapes using vector projection.
    public func lineSegmentHitTest(point: CGPoint, start: CGPoint, end: CGPoint, threshold: CGFloat) -> Bool {
        return GeometryUtils.distance(from: point, toLineSegmentFrom: start, to: end) <= threshold + lineWidth / 2
    }
}
