import Cocoa

// MARK: - OverlayView

class OverlayView: NSView {

    // MARK: - Properties

    private var drawingState = DrawingState()
    private var currentPoints: [CGPoint] = []
    private var isDrawing = false

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Draw whiteboard background if enabled
        if drawingState.boardMode != .none {
            drawBoard(in: context)
        }

        // Draw all committed items
        for item in drawingState.items {
            item.draw(in: context)
        }

        // Draw current in-progress stroke
        if isDrawing, currentPoints.count > 1 {
            drawCurrentStroke(in: context)
        }
    }

    private func drawBoard(in context: CGContext) {
        let color: NSColor
        switch drawingState.boardMode {
        case .white:
            color = .white
        case .black:
            color = .black
        case .custom(let c):
            color = c
        case .none:
            return
        }
        context.setFillColor(color.cgColor)
        context.fill(bounds)
    }

    private func drawCurrentStroke(in context: CGContext) {
        let path = CGMutablePath()
        let smoothed = smoothPoints(currentPoints)

        guard smoothed.count > 1 else { return }

        path.move(to: smoothed[0])
        for i in 1..<smoothed.count {
            path.addLine(to: smoothed[i])
        }

        context.setStrokeColor(drawingState.activeColor.cgColor)
        context.setLineWidth(drawingState.activeLineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(path)
        context.strokePath()
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        currentPoints = [point]
        isDrawing = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        currentPoints.append(point)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        currentPoints.append(point)
        isDrawing = false

        // Commit stroke
        if currentPoints.count > 1 {
            let stroke = FreehandStroke(
                points: smoothPoints(currentPoints),
                color: drawingState.activeColor,
                lineWidth: drawingState.activeLineWidth
            )
            drawingState.addItem(stroke)
        }

        currentPoints = []
        needsDisplay = true
    }

    // MARK: - Keyboard Events

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard let characters = event.charactersIgnoringModifiers else {
            super.keyDown(with: event)
            return
        }

        switch characters {
        case "z" where event.modifierFlags.contains(.command):
            if event.modifierFlags.contains(.shift) {
                drawingState.redo()
            } else {
                drawingState.undo()
            }
            needsDisplay = true
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Public API

    func clearAll() {
        drawingState.clearAll()
        needsDisplay = true
    }

    // MARK: - Smoothing

    private func smoothPoints(_ points: [CGPoint]) -> [CGPoint] {
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

        smoothed.append(points.last!)
        return smoothed
    }
}
