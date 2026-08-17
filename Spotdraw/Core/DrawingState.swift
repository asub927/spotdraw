// DrawingState.swift
// Drawing model layer: defines the DrawingItem protocol, concrete shape types
// (FreehandStroke, ArrowShape, RectangleShape, CircleShape, LineShape),
// tool/board-mode enums, and the DrawingState class that owns the undo/redo
// stack and active tool/color/line-width state shared across overlay views.

import Cocoa

// MARK: - ToolType

internal enum ToolType: CaseIterable, Hashable {
    case pen
    case arrow
    case rectangle
    case circle
    case line
    case highlighter
    case eraser

    /// The keyboard shortcut character that activates this tool.
    var keyCharacter: String {
        switch self {
        case .pen: "p"
        case .arrow: "a"
        case .rectangle: "r"
        case .circle: "o"
        case .line: "l"
        case .highlighter: "h"
        case .eraser: "e"
        }
    }
}

// MARK: - BoardMode

internal enum BoardMode: Equatable {
    case none
    case white
    case black
    case custom(NSColor)

    /// Returns the next mode in the cycling sequence: none → white → black → none.
    /// Custom mode resets to none.
    var next: BoardMode {
        switch self {
        case .none: .white
        case .white: .black
        case .black: .none
        case .custom: .none
        }
    }
}

// MARK: - DrawingItem Protocol

/// A drawable annotation element that can be rendered, hit-tested, and faded over time.
internal protocol DrawingItem: AnyObject {
    /// Unique identifier for this drawing item.
    var id: UUID { get }
    /// The stroke or fill color used when rendering.
    var color: NSColor { get }
    /// The stroke width in points.
    var lineWidth: CGFloat { get }
    /// The timestamp when this item was created, used for fade calculations.
    var createdAt: Date { get }
    /// Current opacity (0–1). Mutated by the fade timer to animate item removal.
    var opacity: CGFloat { get set }
    /// Renders this item into the given Core Graphics context.
    func draw(in context: CGContext)
    /// Returns `true` if `point` lies within `threshold` points of this item's stroke path.
    func hitTest(point: CGPoint, threshold: CGFloat) -> Bool
}

// MARK: - DrawingItem Default Hit-Test

extension DrawingItem {
    /// Default hit-test for line-segment shapes using vector projection.
    func lineSegmentHitTest(point: CGPoint, start: CGPoint, end: CGPoint, threshold: CGFloat) -> Bool {
        return distanceFromPointToLine(point: point, lineStart: start, lineEnd: end) <= threshold + lineWidth / 2
    }
}

// MARK: - FreehandStroke

internal final class FreehandStroke: DrawingItem {
    let id = UUID()
    let points: [CGPoint]
    let color: NSColor
    let lineWidth: CGFloat
    let createdAt = Date()
    var opacity: CGFloat = 1.0
    let alpha: CGFloat

    init(points: [CGPoint], color: NSColor, lineWidth: CGFloat, alpha: CGFloat = 1.0) {
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
        self.alpha = alpha
    }

    // Quadratic Bézier smoothing: uses midpoints between consecutive points as
    // curve endpoints, with the original points as control points. This produces
    // a C1-continuous curve that passes near (but not through) the sampled points.
    func draw(in context: CGContext) {
        guard points.count > 1 else { return }

        let path = CGMutablePath()
        path.move(to: points[0])

        if points.count == 2 {
            path.addLine(to: points[1])
        } else {
            for i in 1..<(points.count - 1) {
                let mid = CGPoint(
                    x: (points[i].x + points[i + 1].x) / 2,
                    y: (points[i].y + points[i + 1].y) / 2
                )
                path.addQuadCurve(to: mid, control: points[i])
            }
            if let lastPoint = points.last {
                path.addLine(to: lastPoint)
            }
        }

        context.saveGState()
        context.setAlpha(opacity * alpha)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    func hitTest(point: CGPoint, threshold: CGFloat) -> Bool {
        let hitDistance = max(threshold, lineWidth / 2 + 5)
        for p in points {
            let dx = p.x - point.x
            let dy = p.y - point.y
            if dx * dx + dy * dy <= hitDistance * hitDistance {
                return true
            }
        }
        return false
    }
}

// MARK: - ArrowShape

internal final class ArrowShape: DrawingItem {
    let id = UUID()
    let start: CGPoint
    let end: CGPoint
    let color: NSColor
    let lineWidth: CGFloat
    let createdAt = Date()
    var opacity: CGFloat = 1.0

    init(start: CGPoint, end: CGPoint, color: NSColor, lineWidth: CGFloat) {
        self.start = start
        self.end = end
        self.color = color
        self.lineWidth = lineWidth
    }

    func draw(in context: CGContext) {
        context.saveGState()
        context.setAlpha(opacity)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)

        // Draw line
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        // Draw arrowhead
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

        context.restoreGState()
    }

    func hitTest(point: CGPoint, threshold: CGFloat) -> Bool {
        lineSegmentHitTest(point: point, start: start, end: end, threshold: threshold)
    }
}

// MARK: - RectangleShape

internal final class RectangleShape: DrawingItem {
    let id = UUID()
    let rect: CGRect
    let color: NSColor
    let lineWidth: CGFloat
    let createdAt = Date()
    var opacity: CGFloat = 1.0

    init(rect: CGRect, color: NSColor, lineWidth: CGFloat) {
        self.rect = rect
        self.color = color
        self.lineWidth = lineWidth
    }

    func draw(in context: CGContext) {
        context.saveGState()
        context.setAlpha(opacity)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.stroke(rect)
        context.restoreGState()
    }

    // Expand/contract approach: checks if the point is within an expanded rect
    // (outside boundary) but NOT within a contracted rect (inside boundary),
    // effectively testing proximity to the rect's border.
    func hitTest(point: CGPoint, threshold: CGFloat) -> Bool {
        let expanded = rect.insetBy(dx: -(threshold + lineWidth), dy: -(threshold + lineWidth))
        let inner = rect.insetBy(dx: threshold + lineWidth, dy: threshold + lineWidth)
        return expanded.contains(point) && !inner.contains(point)
    }
}

// MARK: - CircleShape

internal final class CircleShape: DrawingItem {
    let id = UUID()
    let rect: CGRect
    let color: NSColor
    let lineWidth: CGFloat
    let createdAt = Date()
    var opacity: CGFloat = 1.0

    init(rect: CGRect, color: NSColor, lineWidth: CGFloat) {
        self.rect = rect
        self.color = color
        self.lineWidth = lineWidth
    }

    func draw(in context: CGContext) {
        context.saveGState()
        context.setAlpha(opacity)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.strokeEllipse(in: rect)
        context.restoreGState()
    }

    // Normalized distance check: maps the point into ellipse space where the
    // ellipse boundary is at distance 1.0, then checks if the normalized distance
    // falls within the threshold band around the boundary.
    func hitTest(point: CGPoint, threshold: CGFloat) -> Bool {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let rx = rect.width / 2
        let ry = rect.height / 2
        let dx = point.x - center.x
        let dy = point.y - center.y
        let normalizedDist = (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry)
        let outerThreshold = ((rx + threshold) * (rx + threshold)) / (rx * rx)
        let innerThreshold = ((rx - threshold) * (rx - threshold)) / (rx * rx)
        return normalizedDist <= outerThreshold && normalizedDist >= innerThreshold
    }
}

// MARK: - LineShape

internal final class LineShape: DrawingItem {
    let id = UUID()
    let start: CGPoint
    let end: CGPoint
    let color: NSColor
    let lineWidth: CGFloat
    let createdAt = Date()
    var opacity: CGFloat = 1.0

    init(start: CGPoint, end: CGPoint, color: NSColor, lineWidth: CGFloat) {
        self.start = start
        self.end = end
        self.color = color
        self.lineWidth = lineWidth
    }

    func draw(in context: CGContext) {
        context.saveGState()
        context.setAlpha(opacity)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
        context.restoreGState()
    }

    func hitTest(point: CGPoint, threshold: CGFloat) -> Bool {
        lineSegmentHitTest(point: point, start: start, end: end, threshold: threshold)
    }
}

// MARK: - DrawingState

/// Owns the shared drawing model: active items, undo/redo stack, and tool configuration.
///
/// DrawingState is intentionally a reference type (class) because multiple OverlayView
/// instances across different screens share the same drawing state. Changes to items,
/// undo/redo, and tool state must be visible across all overlay windows without explicit
/// synchronization.
internal final class DrawingState {

    // MARK: - Properties

    var items: [any DrawingItem] = []
    private var undoStack: [any DrawingItem] = []

    var activeTool: ToolType = .pen
    var activeColor: NSColor = .systemRed
    var activeLineWidth: CGFloat = 3.0
    var boardMode: BoardMode = .none
    var fadeMode: Bool = false
    var fadeDuration: TimeInterval = 3.0

    // MARK: - Mutations

    /// Appends a new drawing item and clears the redo stack.
    func addItem(_ item: any DrawingItem) {
        items.append(item)
        undoStack.removeAll()
    }

    /// Moves the most recent item from the canvas to the redo stack.
    func undo() {
        guard let last = items.popLast() else { return }
        undoStack.append(last)
    }

    /// Restores the most recently undone item back to the canvas.
    func redo() {
        guard let last = undoStack.popLast() else { return }
        items.append(last)
    }

    /// Removes all items and clears the undo/redo history.
    func clearAll() {
        items.removeAll()
        undoStack.removeAll()
    }

    /// Removes the item at the given index, if valid.
    func removeItem(at index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
    }

    /// Removes all items whose stroke path intersects the given point within `threshold` points.
    func removeItems(intersecting point: CGPoint, threshold: CGFloat = 10) {
        items.removeAll { $0.hitTest(point: point, threshold: threshold) }
    }
}

// MARK: - Geometry Utilities

// Vector projection: projects the test point onto the infinite line through
// start/end, clamps parameter t to [0,1] to restrict to the segment, then
// returns Euclidean distance to the clamped projection.
func distanceFromPointToLine(point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> CGFloat {
    let dx = lineEnd.x - lineStart.x
    let dy = lineEnd.y - lineStart.y
    let lengthSquared = dx * dx + dy * dy

    if lengthSquared == 0 {
        let ddx = point.x - lineStart.x
        let ddy = point.y - lineStart.y
        return sqrt(ddx * ddx + ddy * ddy)
    }

    var t = ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / lengthSquared
    t = Swift.max(0, Swift.min(1, t))

    let projX = lineStart.x + t * dx
    let projY = lineStart.y + t * dy

    let distX = point.x - projX
    let distY = point.y - projY
    return sqrt(distX * distX + distY * distY)
}
