// OverlayView.swift
// NSView subclass that handles mouse input for freehand drawing and shape creation,
// processes keyboard shortcuts for tool switching and undo/redo, renders committed
// drawing items and in-progress strokes via Core Graphics, and manages a fade timer
// that gradually removes old annotations when fade mode is active.

import Cocoa

// MARK: - OverlayView

@MainActor internal final class OverlayView: NSView {

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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            fadeTimer?.invalidate()
            fadeTimer = nil
        } else if fadeTimer == nil {
            startFadeTimer()
        }
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
        let alpha: CGFloat = drawingState.activeTool == .highlighter ? 0.3 : 1.0
        let width = drawingState.activeTool == .highlighter ? drawingState.activeLineWidth * 4 : drawingState.activeLineWidth
        DrawingRenderer.drawStroke(points: currentPoints, color: drawingState.activeColor, lineWidth: width, alpha: alpha, in: context)
    }

    private func drawCurrentArrow(in context: CGContext) {
        let start = shapeStartPoint
        var end = currentShapeEndPoint

        if isShiftHeld {
            end = DrawingRenderer.constrainToAngles(from: start, to: end)
        }

        DrawingRenderer.drawArrow(from: start, to: end, color: drawingState.activeColor, lineWidth: drawingState.activeLineWidth, in: context)
    }

    private func drawCurrentRect(in context: CGContext) {
        var rect = DrawingRenderer.rectFrom(start: shapeStartPoint, end: currentShapeEndPoint)
        if isShiftHeld {
            let side = max(rect.width, rect.height)
            rect.size = CGSize(width: side, height: side)
        }

        DrawingRenderer.drawRectangle(rect, color: drawingState.activeColor, lineWidth: drawingState.activeLineWidth, in: context)
    }

    private func drawCurrentCircle(in context: CGContext) {
        var rect = DrawingRenderer.rectFrom(start: shapeStartPoint, end: currentShapeEndPoint)
        if isShiftHeld {
            let side = max(rect.width, rect.height)
            rect.size = CGSize(width: side, height: side)
        }

        DrawingRenderer.drawCircle(in: rect, color: drawingState.activeColor, lineWidth: drawingState.activeLineWidth, in: context)
    }

    private func drawCurrentLine(in context: CGContext) {
        let start = shapeStartPoint
        var end = currentShapeEndPoint

        if isShiftHeld {
            end = DrawingRenderer.constrainToAngles(from: start, to: end)
        }

        DrawingRenderer.drawLine(from: start, to: end, color: drawingState.activeColor, lineWidth: drawingState.activeLineWidth, in: context)
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
                    points: DrawingRenderer.smoothPoints(currentPoints),
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
                    points: DrawingRenderer.smoothPoints(currentPoints),
                    color: drawingState.activeColor,
                    lineWidth: drawingState.activeLineWidth * 4,
                    alpha: 0.3
                )
                drawingState.addItem(stroke)
            }
            currentPoints = []

        case .arrow:
            var end = point
            if isShiftHeld { end = DrawingRenderer.constrainToAngles(from: shapeStartPoint, to: end) }
            let arrow = ArrowShape(
                start: shapeStartPoint,
                end: end,
                color: drawingState.activeColor,
                lineWidth: drawingState.activeLineWidth
            )
            drawingState.addItem(arrow)

        case .rectangle:
            var rect = DrawingRenderer.rectFrom(start: shapeStartPoint, end: point)
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
            var rect = DrawingRenderer.rectFrom(start: shapeStartPoint, end: point)
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
            if isShiftHeld { end = DrawingRenderer.constrainToAngles(from: shapeStartPoint, to: end) }
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
        case "b":
            toggleBoard()
        case " ":
            drawingState.fadeMode.toggle()
        case "\u{1B}": // Escape
            onDeactivate?()
        default:
            if let tool = ToolType.allCases.first(where: { $0.keyCharacter == characters }) {
                drawingState.activeTool = tool
            } else if let colorShortcut = ColorShortcut.allCases.first(where: { $0.keyCharacter == characters }) {
                drawingState.activeColor = colorShortcut.color
            } else {
                super.keyDown(with: event)
            }
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
        drawingState.boardMode = drawingState.boardMode.next
        needsDisplay = true
    }

    // MARK: - Fade Timer

    private func startFadeTimer() {
        // Timer scheduled on the main run loop; callback executes on the main thread.
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

    // MARK: - Cleanup

    deinit {
        fadeTimer?.invalidate()
    }
}
