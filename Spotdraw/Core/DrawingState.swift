import Cocoa

// MARK: - ToolType

enum ToolType {
    case pen
    case arrow
    case rectangle
    case circle
    case line
    case highlighter
    case eraser
}

// MARK: - BoardMode

enum BoardMode: Equatable {
    case none
    case white
    case black
    case custom(NSColor)
}

// MARK: - DrawingItem Protocol

protocol DrawingItem: AnyObject {
    var id: UUID { get }
    var color: NSColor { get }
    var lineWidth: CGFloat { get }
    var createdAt: Date { get }
    var opacity: CGFloat { get set }
    func draw(in context: CGContext)
    func hitTest(point: CGPoint, threshold: CGFloat) -> Bool
}

// MARK: - FreehandStroke

class FreehandStroke: DrawingItem {
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
            path.addLine(to: points.last!)
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

class ArrowShape: DrawingItem {
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
        return distanceFromPointToLine(point: point, lineStart: start, lineEnd: end) <= threshold + lineWidth / 2
    }
}

// MARK: - RectangleShape

class RectangleShape: DrawingItem {
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

    func hitTest(point: CGPoint, threshold: CGFloat) -> Bool {
        let expanded = rect.insetBy(dx: -(threshold + lineWidth), dy: -(threshold + lineWidth))
        let inner = rect.insetBy(dx: threshold + lineWidth, dy: threshold + lineWidth)
        return expanded.contains(point) && !inner.contains(point)
    }
}

// MARK: - CircleShape

class CircleShape: DrawingItem {
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

class LineShape: DrawingItem {
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
        return distanceFromPointToLine(point: point, lineStart: start, lineEnd: end) <= threshold + lineWidth / 2
    }
}

// MARK: - DrawingState

class DrawingState {

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

    func addItem(_ item: any DrawingItem) {
        items.append(item)
        undoStack.removeAll()
    }

    func undo() {
        guard let last = items.popLast() else { return }
        undoStack.append(last)
    }

    func redo() {
        guard let last = undoStack.popLast() else { return }
        items.append(last)
    }

    func clearAll() {
        items.removeAll()
        undoStack.removeAll()
    }

    func removeItem(at index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
    }

    func removeItems(intersecting point: CGPoint, threshold: CGFloat = 10) {
        items.removeAll { $0.hitTest(point: point, threshold: threshold) }
    }
}

// MARK: - Geometry Utilities

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
