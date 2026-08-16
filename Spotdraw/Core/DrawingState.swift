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

protocol DrawingItem {
    var id: UUID { get }
    var color: NSColor { get }
    var lineWidth: CGFloat { get }
    var createdAt: Date { get }
    var opacity: CGFloat { get set }
    func draw(in context: CGContext)
    func hitTest(point: CGPoint, threshold: CGFloat) -> Bool
}

// MARK: - FreehandStroke

struct FreehandStroke: DrawingItem {
    let id = UUID()
    let points: [CGPoint]
    let color: NSColor
    let lineWidth: CGFloat
    let createdAt = Date()
    var opacity: CGFloat = 1.0

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
        context.setAlpha(opacity)
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

// MARK: - DrawingState

class DrawingState {

    // MARK: - Properties

    private(set) var items: [any DrawingItem] = []
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
