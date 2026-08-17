import Cocoa

// MARK: - OverlayView

class OverlayView: NSView {

    // MARK: - Properties

    var drawingState = DrawingState()
    var onDeactivate: (() -> Void)?
    private var currentPoints: [CGPoint] = []
    private var shapeStartPoint: CGPoint = .zero
    private var currentShapeEndPoint: CGPoint = .zero
    private var isDrawing = false
    private var isShiftHeld = false
    private var fadeTimer: Timer?

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
        startFadeTimer()
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
            if item.opacity > 0 {
                item.draw(in: context)
            }
        }

        // Draw current in-progress item
        if isDrawing {
            drawCurrentItem(in: context)
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

    private func drawCurrentItem(in context: CGContext) {
        switch drawingState.activeTool {
        case .pen, .highlighter:
            drawCurrentStroke(in: context)
        case .arrow:
            drawCurrentArrow(in: context)
        case .rectangle:
            drawCurrentRect(in: context)
        case .circle:
            drawCurrentCircle(in: context)
        case .line:
            drawCurrentLine(in: context)
        case .eraser:
            break // Eraser erases on drag, no preview needed
        }
    }

    private func drawCurrentStroke(in context: CGContext) {
        guard currentPoints.count > 1 else { return }

        let path = CGMutablePath()
        let smoothed = smoothPoints(currentPoints)

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
        let alpha: CGFloat = drawingState.activeTool == .highlighter ? 0.3 : 1.0
        let width = drawingState.activeTool == .highlighter ? drawingState.activeLineWidth * 4 : drawingState.activeLineWidth
        context.setAlpha(alpha)
        context.setStrokeColor(drawingState.activeColor.cgColor)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    private func drawCurrentArrow(in context: CGContext) {
        let start = shapeStartPoint
        var end = currentShapeEndPoint

        if isShiftHeld {
            end = constrainToAngles(from: start, to: end)
        }

        context.saveGState()
        context.setStrokeColor(drawingState.activeColor.cgColor)
        context.setLineWidth(drawingState.activeLineWidth)
        context.setLineCap(.round)

        // Draw line
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        // Draw arrowhead
        drawArrowhead(in: context, from: start, to: end)
        context.restoreGState()
    }

    private func drawCurrentRect(in context: CGContext) {
        var rect = rectFrom(start: shapeStartPoint, end: currentShapeEndPoint)
        if isShiftHeld {
            let side = max(rect.width, rect.height)
            rect.size = CGSize(width: side, height: side)
        }

        context.saveGState()
        context.setStrokeColor(drawingState.activeColor.cgColor)
        context.setLineWidth(drawingState.activeLineWidth)
        context.stroke(rect)
        context.restoreGState()
    }

    private func drawCurrentCircle(in context: CGContext) {
        var rect = rectFrom(start: shapeStartPoint, end: currentShapeEndPoint)
        if isShiftHeld {
            let side = max(rect.width, rect.height)
            rect.size = CGSize(width: side, height: side)
        }

        context.saveGState()
        context.setStrokeColor(drawingState.activeColor.cgColor)
        context.setLineWidth(drawingState.activeLineWidth)
        context.strokeEllipse(in: rect)
        context.restoreGState()
    }

    private func drawCurrentLine(in context: CGContext) {
        let start = shapeStartPoint
        var end = currentShapeEndPoint

        if isShiftHeld {
            end = constrainToAngles(from: start, to: end)
        }

        context.saveGState()
        context.setStrokeColor(drawingState.activeColor.cgColor)
        context.setLineWidth(drawingState.activeLineWidth)
        context.setLineCap(.round)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
        context.restoreGState()
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        isShiftHeld = event.modifierFlags.contains(.shift)

        switch drawingState.activeTool {
        case .pen, .highlighter:
            currentPoints = [point]
            isDrawing = true
        case .arrow, .rectangle, .circle, .line:
            shapeStartPoint = point
            currentShapeEndPoint = point
            isDrawing = true
        case .eraser:
            drawingState.removeItems(intersecting: point, threshold: 15)
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        isShiftHeld = event.modifierFlags.contains(.shift)

        switch drawingState.activeTool {
        case .pen, .highlighter:
            currentPoints.append(point)
        case .arrow, .rectangle, .circle, .line:
            currentShapeEndPoint = point
        case .eraser:
            drawingState.removeItems(intersecting: point, threshold: 15)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        isShiftHeld = event.modifierFlags.contains(.shift)
        isDrawing = false

        switch drawingState.activeTool {
        case .pen:
            currentPoints.append(point)
            if currentPoints.count > 1 {
                let stroke = FreehandStroke(
                    points: smoothPoints(currentPoints),
                    color: drawingState.activeColor,
                    lineWidth: drawingState.activeLineWidth
                )
                drawingState.addItem(stroke)
            }
            currentPoints = []

        case .highlighter:
            currentPoints.append(point)
            if currentPoints.count > 1 {
                let stroke = FreehandStroke(
                    points: smoothPoints(currentPoints),
                    color: drawingState.activeColor,
                    lineWidth: drawingState.activeLineWidth * 4,
                    alpha: 0.3
                )
                drawingState.addItem(stroke)
            }
            currentPoints = []

        case .arrow:
            var end = point
            if isShiftHeld { end = constrainToAngles(from: shapeStartPoint, to: end) }
            let arrow = ArrowShape(
                start: shapeStartPoint,
                end: end,
                color: drawingState.activeColor,
                lineWidth: drawingState.activeLineWidth
            )
            drawingState.addItem(arrow)

        case .rectangle:
            var rect = rectFrom(start: shapeStartPoint, end: point)
            if isShiftHeld {
                let side = max(rect.width, rect.height)
                rect.size = CGSize(width: side, height: side)
            }
            let shape = RectangleShape(
                rect: rect,
                color: drawingState.activeColor,
                lineWidth: drawingState.activeLineWidth
            )
            drawingState.addItem(shape)

        case .circle:
            var rect = rectFrom(start: shapeStartPoint, end: point)
            if isShiftHeld {
                let side = max(rect.width, rect.height)
                rect.size = CGSize(width: side, height: side)
            }
            let shape = CircleShape(
                rect: rect,
                color: drawingState.activeColor,
                lineWidth: drawingState.activeLineWidth
            )
            drawingState.addItem(shape)

        case .line:
            var end = point
            if isShiftHeld { end = constrainToAngles(from: shapeStartPoint, to: end) }
            let shape = LineShape(
                start: shapeStartPoint,
                end: end,
                color: drawingState.activeColor,
                lineWidth: drawingState.activeLineWidth
            )
            drawingState.addItem(shape)

        case .eraser:
            break
        }

        needsDisplay = true
    }

    // MARK: - Keyboard Events

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard let characters = event.charactersIgnoringModifiers else {
            super.keyDown(with: event)
            return
        }

        let hasCommand = event.modifierFlags.contains(.command)
        let hasShift = event.modifierFlags.contains(.shift)
        let hasControl = event.modifierFlags.contains(.control)

        // Ctrl+D deactivates the overlay — check before the switch to prevent the event from being swallowed
        if hasControl && characters == "d" {
            onDeactivate?()
            return
        }

        switch characters {
        case "z" where hasCommand && hasShift:
            drawingState.redo()
            needsDisplay = true
        case "z" where hasCommand:
            drawingState.undo()
            needsDisplay = true
        case "p":
            drawingState.activeTool = .pen
        case "a":
            drawingState.activeTool = .arrow
        case "r":
            drawingState.activeTool = .rectangle
        case "o":
            drawingState.activeTool = .circle
        case "l":
            drawingState.activeTool = .line
        case "h":
            drawingState.activeTool = .highlighter
        case "e":
            drawingState.activeTool = .eraser
        case "b":
            toggleBoard()
        case " ":
            drawingState.fadeMode.toggle()
        case "\u{1B}": // Escape
            onDeactivate?()
        default:
            super.keyDown(with: event)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        isShiftHeld = event.modifierFlags.contains(.shift)
        if isDrawing {
            needsDisplay = true
        }
    }

    // MARK: - Public API

    func clearAll() {
        drawingState.clearAll()
        needsDisplay = true
    }

    // MARK: - Board Toggle

    private func toggleBoard() {
        switch drawingState.boardMode {
        case .none:
            drawingState.boardMode = .white
        case .white:
            drawingState.boardMode = .black
        case .black:
            drawingState.boardMode = .none
        case .custom:
            drawingState.boardMode = .none
        }
        needsDisplay = true
    }

    // MARK: - Fade Timer

    private func startFadeTimer() {
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.processFade()
        }
    }

    private func processFade() {
        guard drawingState.fadeMode else { return }

        let now = Date()
        var needsRedraw = false

        for i in (0..<drawingState.items.count).reversed() {
            let age = now.timeIntervalSince(drawingState.items[i].createdAt)
            if age > drawingState.fadeDuration {
                let fadeProgress = (age - drawingState.fadeDuration) / 1.0 // 1 second fade
                let newOpacity = CGFloat(1.0 - fadeProgress)
                if newOpacity <= 0 {
                    drawingState.removeItem(at: i)
                    needsRedraw = true
                } else {
                    drawingState.items[i].opacity = newOpacity
                    needsRedraw = true
                }
            }
        }

        if needsRedraw {
            needsDisplay = true
        }
    }

    // MARK: - Geometry Helpers

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

    private func constrainToAngles(from start: CGPoint, to end: CGPoint) -> CGPoint {
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

    private func rectFrom(start: CGPoint, end: CGPoint) -> CGRect {
        let x = Swift.min(start.x, end.x)
        let y = Swift.min(start.y, end.y)
        let width = abs(end.x - start.x)
        let height = abs(end.y - start.y)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func drawArrowhead(in context: CGContext, from start: CGPoint, to end: CGPoint) {
        let headLength: CGFloat = drawingState.activeLineWidth * 4
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

        context.setFillColor(drawingState.activeColor.cgColor)
        context.move(to: end)
        context.addLine(to: point1)
        context.addLine(to: point2)
        context.closePath()
        context.fillPath()
    }

    // MARK: - Cleanup

    deinit {
        fadeTimer?.invalidate()
    }
}
