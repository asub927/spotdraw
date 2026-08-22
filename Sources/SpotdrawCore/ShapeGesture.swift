// ShapeGesture.swift
// A pure value type that accumulates one shape/freehand drawing gesture and
// produces both in-progress preview geometry and a committed DrawingItem.
//
// Extracted from OverlayView (see .kiro/specs/overlay-gesture-extraction) so the
// geometry rules — shift-square sizing, 45° angle constraint, freehand smoothing,
// and the highlighter width/alpha multipliers — live in one testable place instead
// of being duplicated between OverlayView.mouseUp and commitCurrentDrawing.
//
// This type is nonisolated (no @MainActor): it holds only value math, so it can be
// exercised in tests without an NSView or a running app.

import Cocoa

// MARK: - ShapePreview

/// Geometry for rendering the in-progress gesture. The renderer switches on this
/// instead of re-deriving the shape from raw points/flags.
public enum ShapePreview: Equatable {
    /// No preview to draw (e.g. a freehand stroke with fewer than 2 points, or a
    /// non-drawing tool).
    case none
    /// A freehand stroke through these raw (unsmoothed) points.
    case stroke(points: [CGPoint])
    /// An arrow from `start` to `end` (end already angle-constrained if applicable).
    case arrow(start: CGPoint, end: CGPoint)
    /// A straight line from `start` to `end` (end already angle-constrained if applicable).
    case line(start: CGPoint, end: CGPoint)
    /// A stroked rectangle (already squared if applicable).
    case rectangle(rect: CGRect)
    /// A stroked ellipse inscribed in `rect` (already squared if applicable).
    case circle(rect: CGRect)
}

// MARK: - ShapeGesture

/// Accumulates a single drawing gesture for one of the shape/freehand tools.
///
/// Lifecycle: `init(tool:startingAt:)` on mouse-down, `extend(to:)` on each
/// drag (and optionally on mouse-up to include the release point), then
/// `previewGeometry(shiftHeld:)` for live rendering or `commit(...)` to produce
/// the finished item.
///
/// The distinction between OverlayView's two old commit paths is captured by
/// whether the caller called `extend(to:)` with the release point: `mouseUp`
/// appended the final point before committing; the passthrough drain committed
/// with the points already accumulated. A single `commit` covers both because
/// the caller controls the point stream.
public struct ShapeGesture {

    /// The tool this gesture was started with.
    public let tool: ToolType

    /// The press point (anchor for shapes; first point for freehand).
    private let start: CGPoint

    /// The most recent point (end for shapes).
    private var current: CGPoint

    /// Accumulated points for freehand tools (pen, highlighter).
    private var freehandPoints: [CGPoint]

    /// True for the freehand tools (pen, highlighter).
    private var isFreehand: Bool {
        tool == .pen || tool == .highlighter
    }

    // MARK: - Init

    public init(tool: ToolType, startingAt point: CGPoint) {
        self.tool = tool
        self.start = point
        self.current = point
        self.freehandPoints = (tool == .pen || tool == .highlighter) ? [point] : []
    }

    // MARK: - Accumulation

    /// Records a new point. Appends for freehand tools; updates the end point for shapes.
    public mutating func extend(to point: CGPoint) {
        if isFreehand {
            freehandPoints.append(point)
        } else {
            current = point
        }
    }

    // MARK: - Preview

    /// The geometry to render for the in-progress gesture, given the current
    /// shift state. Mirrors OverlayView's old drawCurrent* methods exactly.
    public func previewGeometry(shiftHeld: Bool) -> ShapePreview {
        switch tool {
        case .pen, .highlighter:
            guard freehandPoints.count > 1 else { return .none }
            return .stroke(points: freehandPoints)
        case .arrow:
            return .arrow(start: start, end: constrainedEnd(shiftHeld: shiftHeld))
        case .line:
            return .line(start: start, end: constrainedEnd(shiftHeld: shiftHeld))
        case .rectangle:
            return .rectangle(rect: squaredRect(shiftHeld: shiftHeld))
        case .circle:
            return .circle(rect: squaredRect(shiftHeld: shiftHeld))
        case .eraser, .text, .select:
            return .none
        }
    }

    // MARK: - Commit

    /// Produces the finished DrawingItem for this gesture, or `nil` if the gesture
    /// produced nothing (a single-point freehand stroke, or a non-drawing tool).
    ///
    /// Faithfully reproduces OverlayView.mouseUp / commitCurrentDrawing:
    /// - pen: smoothed stroke at the active line width
    /// - highlighter: smoothed stroke at 4× width and 0.3 alpha
    /// - arrow/line: end angle-constrained when shift is held
    /// - rectangle/circle: squared (side = max(w,h)) when shift is held
    public func commit(shiftHeld: Bool,
                       color: NSColor,
                       lineWidth: CGFloat,
                       screenID: CGDirectDisplayID) -> (any DrawingItem)? {
        switch tool {
        case .pen:
            guard freehandPoints.count > 1 else { return nil }
            let stroke = FreehandStroke(
                points: DrawingRenderer.smoothPoints(freehandPoints),
                color: color,
                lineWidth: lineWidth
            )
            stroke.screenID = screenID
            return stroke

        case .highlighter:
            guard freehandPoints.count > 1 else { return nil }
            let stroke = FreehandStroke(
                points: DrawingRenderer.smoothPoints(freehandPoints),
                color: color,
                lineWidth: lineWidth * 4,
                alpha: 0.3
            )
            stroke.screenID = screenID
            return stroke

        case .arrow:
            let arrow = ArrowShape(
                start: start,
                end: constrainedEnd(shiftHeld: shiftHeld),
                color: color,
                lineWidth: lineWidth
            )
            arrow.screenID = screenID
            return arrow

        case .line:
            let line = LineShape(
                start: start,
                end: constrainedEnd(shiftHeld: shiftHeld),
                color: color,
                lineWidth: lineWidth
            )
            line.screenID = screenID
            return line

        case .rectangle:
            let shape = RectangleShape(
                rect: squaredRect(shiftHeld: shiftHeld),
                color: color,
                lineWidth: lineWidth
            )
            shape.screenID = screenID
            return shape

        case .circle:
            let shape = CircleShape(
                rect: squaredRect(shiftHeld: shiftHeld),
                color: color,
                lineWidth: lineWidth
            )
            shape.screenID = screenID
            return shape

        case .eraser, .text, .select:
            return nil
        }
    }

    // MARK: - Geometry helpers

    /// The end point with the 45° angle constraint applied when shift is held.
    private func constrainedEnd(shiftHeld: Bool) -> CGPoint {
        guard shiftHeld else { return current }
        return DrawingRenderer.constrainToAngles(from: start, to: current)
    }

    /// The rectangle from start→current, squared to `max(width, height)` when
    /// shift is held (matching OverlayView's old behavior).
    private func squaredRect(shiftHeld: Bool) -> CGRect {
        var rect = DrawingRenderer.rectFrom(start: start, end: current)
        if shiftHeld {
            let side = max(rect.width, rect.height)
            rect.size = CGSize(width: side, height: side)
        }
        return rect
    }
}
