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

    /// Owns the NSTextField subview lifecycle for composing/editing TextAnnotations.
    private let textEditing = TextEditingController()
    /// The TextAnnotation currently being dragged by the text tool, if any.
    private var draggedTextItem: TextAnnotation?
    /// The most recent drag point while dragging a TextAnnotation with the text tool,
    /// used to compute the incremental delta for live visual feedback.
    private var textDragLastPoint: CGPoint = .zero
    /// The total delta accumulated since the text-tool drag began, applied to
    /// DrawingState exactly once on mouseUp so only one `.move` is recorded.
    private var textDragTotalDelta: CGSize = .zero

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
        textEditing.onCommit = { [weak self] result in
            self?.routeTextCommit(result)
        }
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
                item.render(in: context)
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
        case .text:
            break // Text editing is handled by TextEditingController (task 5.4/5.5)
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
        case .text:
            handleTextMouseDown(at: point, clickCount: event.clickCount)
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
        case .text:
            handleTextMouseDragged(at: point)
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

        case .text:
            handleTextMouseUp(at: point)
        }

        needsDisplay = true
    }

    // MARK: - Text Tool

    /// Returns the topmost `TextAnnotation` whose bounding rectangle contains `point`,
    /// searching in reverse so later (visually on-top) items win, matching the
    /// hit-test convention used elsewhere (e.g. `SelectionManager.topmostHit`).
    private func topmostTextAnnotation(at point: CGPoint) -> TextAnnotation? {
        for item in drawingState.items.reversed() {
            if let text = item as? TextAnnotation, text.bounds.contains(point) {
                return text
            }
        }
        return nil
    }

    private func handleTextMouseDown(at point: CGPoint, clickCount: Int) {
        guard let hitItem = topmostTextAnnotation(at: point) else {
            // Empty space: begin composing a new annotation anchored at the press point.
            textEditing.begin(
                at: point,
                existing: nil,
                in: self,
                color: drawingState.activeColor,
                fontSize: SettingsManager.shared.textFontSize
            )
            needsDisplay = true
            return
        }

        if clickCount == 2 {
            // Double-click: begin editing the existing annotation's string at its anchor.
            // `begin` commits any prior in-progress edit first.
            draggedTextItem = nil
            textEditing.begin(
                at: hitItem.anchor,
                existing: hitItem,
                in: self,
                color: drawingState.activeColor,
                fontSize: SettingsManager.shared.textFontSize
            )
            needsDisplay = true
            return
        }

        // Single click inside an existing annotation: prepare for a possible drag.
        // Editing only begins on double-click, per the double-click requirement.
        draggedTextItem = hitItem
        textDragLastPoint = point
        textDragTotalDelta = .zero
    }

    private func handleTextMouseDragged(at point: CGPoint) {
        guard let item = draggedTextItem else { return }

        let incrementalDelta = CGSize(
            width: point.x - textDragLastPoint.x,
            height: point.y - textDragLastPoint.y
        )
        textDragLastPoint = point
        textDragTotalDelta = CGSize(
            width: textDragTotalDelta.width + incrementalDelta.width,
            height: textDragTotalDelta.height + incrementalDelta.height
        )

        // Live visual feedback: mutate the item's offset directly, bypassing
        // DrawingState so the undo stack is not touched on every drag event.
        item.translate(by: incrementalDelta)
    }

    private func handleTextMouseUp(at point: CGPoint) {
        defer {
            draggedTextItem = nil
            textDragLastPoint = .zero
            textDragTotalDelta = .zero
        }

        guard let item = draggedTextItem else { return }

        guard textDragTotalDelta != .zero else {
            // Click without moving: no operation recorded, position unchanged.
            return
        }

        // Undo the directly-applied live preview, then reapply the same total
        // delta through DrawingState so exactly one `.move` is recorded for the
        // whole drag, with the final position equal to start + total delta.
        item.translate(by: CGSize(width: -textDragTotalDelta.width, height: -textDragTotalDelta.height))
        drawingState.translate(ids: [item.id], by: textDragTotalDelta)
    }

    /// Commits the in-progress text edit, if any, routing the result to `DrawingState`
    /// so a new annotation is added and an edited annotation replaces its original
    /// index, recording exactly one undoable operation either way. Called by
    /// `keyDown`'s Editing_State guard (task 5.6) when focus has not transferred;
    /// the NSTextField delegate command path routes through `routeTextCommit`.
    private func finishTextEditing() {
        routeTextCommit(textEditing.commit())
    }

    private func routeTextCommit(_ result: TextCommitResult) {
        switch result {
        case .discarded:
            break
        case .created(let created):
            drawingState.addItem(created)
        case .edited(let original, let updated):
            if let index = drawingState.items.firstIndex(where: { $0.id == original.id }) {
                drawingState.replaceItem(at: index, with: updated)
            }
        }
        needsDisplay = true
    }

    // MARK: - Keyboard Events

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Editing_State must be checked before any character or modifier inspection.
        // While editing, the NSTextField is first responder and receives keys directly;
        // this guard covers the case where focus has not yet transferred to it.
        if textEditing.isEditing {
            // Raw key codes (no Carbon import elsewhere in this project):
            // 53 = Escape, 36 = Return. Both commit; Escape must NOT invoke onDeactivate.
            if event.keyCode == 53 || event.keyCode == 36 {
                finishTextEditing()
                return
            }
            super.keyDown(with: event)
            return
        }

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
