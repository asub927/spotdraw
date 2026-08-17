// DrawingRenderer.swift
// Extracted rendering and geometry helpers for the annotation overlay.
// Provides static methods for drawing strokes, shapes, and arrowheads via Core Graphics,
// plus utility functions for point smoothing and angle-constrained snapping.

import Cocoa

// MARK: - DrawingRenderer

/// Static rendering utilities for drawing in-progress annotation shapes.
internal struct DrawingRenderer {

    // MARK: - Stroke Rendering

    /// Draws a smoothed freehand stroke through the given points.
    ///
    /// Applies weighted-average smoothing to interior points, then renders
    /// the resulting curve using quadratic Bézier segments with round caps.
    static func drawStroke(points: [CGPoint], color: NSColor, lineWidth: CGFloat, alpha: CGFloat, in context: CGContext) {
        guard points.count > 1 else { return }

        let path = CGMutablePath()
        let smoothed = smoothPoints(points)

        guard smoothed.count > 1 else { return }

        path.move(to: smoothed[0])
        for i in 1..<smoothed.count {
            if i < smoothed.count - 1 {
                let mid = CGPoint(
                    x: (smoothed[i].x + smoothed[i + 1].x) / 2,
                    y: (smoothed[i].y + smoothed[i + 1].y) / 2
                )
                path.addQuadCurve(to: mid, control: smoothed[i])
            } else {
                path.addLine(to: smoothed[i])
            }
        }

        context.saveGState()
        context.setAlpha(alpha)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    // MARK: - Shape Rendering

    /// Draws an arrow from `start` to `end` with an arrowhead at the endpoint.
    static func drawArrow(from start: CGPoint, to end: CGPoint, color: NSColor, lineWidth: CGFloat, in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)

        // Draw line
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        // Draw arrowhead
        drawArrowhead(from: start, to: end, color: color, lineWidth: lineWidth, in: context)
        context.restoreGState()
    }

    /// Draws a stroked rectangle outline.
    static func drawRectangle(_ rect: CGRect, color: NSColor, lineWidth: CGFloat, in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.stroke(rect)
        context.restoreGState()
    }

    /// Draws a stroked ellipse inscribed in the given rectangle.
    static func drawCircle(in rect: CGRect, color: NSColor, lineWidth: CGFloat, in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.strokeEllipse(in: rect)
        context.restoreGState()
    }

    /// Draws a straight line between two points.
    static func drawLine(from start: CGPoint, to end: CGPoint, color: NSColor, lineWidth: CGFloat, in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
        context.restoreGState()
    }

    /// Draws a filled triangular arrowhead at the `end` point, pointing away from `start`.
    ///
    /// The arrowhead length is proportional to `lineWidth` (4×) and the half-angle
    /// is π/6 (30°), producing a standard arrow appearance.
    static func drawArrowhead(from start: CGPoint, to end: CGPoint, color: NSColor, lineWidth: CGFloat, in context: CGContext) {
        let headLength: CGFloat = lineWidth * 4
        let headAngle: CGFloat = .pi / 6

        let angle = atan2(end.y - start.y, end.x - start.x)

        let point1 = CGPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)
        )
        let point2 = CGPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)
        )

        context.setFillColor(color.cgColor)
        context.move(to: end)
        context.addLine(to: point1)
        context.addLine(to: point2)
        context.closePath()
        context.fillPath()
    }

    // MARK: - Geometry Helpers

    /// Smooths an array of points using weighted average.
    ///
    /// Each interior point is replaced by `(prev + 2*curr + next) / 4`, producing
    /// a smoother curve without shifting the first or last endpoint.
    static func smoothPoints(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 2 else { return points }

        var smoothed: [CGPoint] = [points[0]]

        for i in 1..<(points.count - 1) {
            let prev = points[i - 1]
            let curr = points[i]
            let next = points[i + 1]

            let smoothX = (prev.x + curr.x * 2 + next.x) / 4.0
            let smoothY = (prev.y + curr.y * 2 + next.y) / 4.0
            smoothed.append(CGPoint(x: smoothX, y: smoothY))
        }

        if let lastPoint = points.last {
            smoothed.append(lastPoint)
        }
        return smoothed
    }

    /// Constrains an endpoint to the nearest 45° angle from the start point.
    ///
    /// Computes the angle from `start` to `end`, snaps it to the nearest
    /// multiple of π/4 (45°), and returns the point at the original distance
    /// along the snapped angle.
    static func constrainToAngles(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let angle = atan2(dy, dx)
        let distance = sqrt(dx * dx + dy * dy)

        // Snap to nearest 45° angle
        let snappedAngle = round(angle / (.pi / 4)) * (.pi / 4)
        return CGPoint(
            x: start.x + distance * cos(snappedAngle),
            y: start.y + distance * sin(snappedAngle)
        )
    }

    /// Computes the bounding rectangle from two corner points.
    ///
    /// Returns the smallest axis-aligned rectangle containing both points,
    /// with origin at the minimum x/y coordinates.
    static func rectFrom(start: CGPoint, end: CGPoint) -> CGRect {
        let x = Swift.min(start.x, end.x)
        let y = Swift.min(start.y, end.y)
        let width = abs(end.x - start.x)
        let height = abs(end.y - start.y)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
