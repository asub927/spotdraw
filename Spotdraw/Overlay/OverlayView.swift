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

        // Draw all committed items, skipping the one currently being edited
        // to avoid a visual duplicate beneath the live NSTextField.
        let editingID = textEditing.editingItem?.id
        for item in drawingState.items {
            if item.opacity > 0 && item.id != editingID {
                item.render(in: context)
            }
        }

        // Draw current in-progress item
        if isDrawing {
            drawCurrentItem(in: context)
        }

        // Draw marquee and selection outlines on top of items (Requirements 2.11, 2.15, 10.7)
        if selectDragMode == .drawingMarquee {
            SelectionRenderer.drawMarquee(from: selectPressPoint, to: selectCurrentPoint, in: context)
        }
        if !drawingState.selection.isEmpty {
            SelectionRenderer.drawSelectionOutlines(
                selectedIDs: drawingState.selection.selectedIDs,
                items: drawingState.items,
                in: context
            )
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
        case .select:
            break // Select tool rendering handled separately (task 7.2/7.8)
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
        case .select:
            handleSelectMouseDown(at: point, event: event)
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
        case .select:
            handleSelectMouseDragged(at: point)
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

        case .select:
            handleSelectMouseUp(at: point)
        }

        needsDisplay = true
    }

    // MARK: - Contextual Menus (Requirement 6)

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()

        if !drawingState.selection.isEmpty {
            // Context menu for selected annotations
            let copyItem = menu.addItem(withTitle: "Copy", action: #selector(contextCopy), keyEquivalent: "")
            copyItem.target = self
            let cutItem = menu.addItem(withTitle: "Cut", action: #selector(contextCut), keyEquivalent: "")
            cutItem.target = self
            let deleteItem = menu.addItem(withTitle: "Delete", action: #selector(contextDelete), keyEquivalent: "")
            deleteItem.target = self
        } else {
            // Context menu for empty space
            let pasteItem = menu.addItem(withTitle: "Paste", action: #selector(contextPaste), keyEquivalent: "")
            pasteItem.target = self
            pasteItem.isEnabled = NSPasteboard.general.data(forType: .png) != nil
            let selectAllItem = menu.addItem(withTitle: "Select All", action: #selector(contextSelectAll), keyEquivalent: "")
            selectAllItem.target = self
            menu.addItem(NSMenuItem.separator())
            let clearItem = menu.addItem(withTitle: "Clear All", action: #selector(contextClearAll), keyEquivalent: "")
            clearItem.target = self
        }

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func contextCopy() {
        // Copy selected annotations to pasteboard as PNG
        copySelectedToPasteboard()
    }

    @objc private func contextCut() {
        copySelectedToPasteboard()
        drawingState.removeSelected()
        needsDisplay = true
    }

    @objc private func contextDelete() {
        drawingState.removeSelected()
        needsDisplay = true
    }

    @objc private func contextPaste() {
        // Placeholder for paste support
    }

    @objc private func contextSelectAll() {
        drawingState.selectAll()
        needsDisplay = true
    }

    @objc private func contextClearAll() {
        clearAll()
    }

    /// Renders the current selection as PNG and writes to the system pasteboard.
    private func copySelectedToPasteboard() {
        guard !drawingState.selection.isEmpty else { return }

        let selectedItems = drawingState.items.filter { drawingState.selection.contains($0.id) }
        guard !selectedItems.isEmpty else { return }

        // Compute bounding box
        var unionRect = CGRect.null
        for item in selectedItems {
            unionRect = unionRect.union(item.bounds)
        }
        guard !unionRect.isNull, unionRect.width > 0, unionRect.height > 0 else { return }

        let padding: CGFloat = 4
        let renderRect = unionRect.insetBy(dx: -padding, dy: -padding)
        let width = Int(ceil(renderRect.width))
        let height = Int(ceil(renderRect.height))

        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return }

        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmapRep)
        NSGraphicsContext.current = context
        guard let cgContext = context?.cgContext else {
            NSGraphicsContext.restoreGraphicsState()
            return
        }

        cgContext.translateBy(x: -renderRect.origin.x, y: -renderRect.origin.y)
        for item in selectedItems {
            item.render(in: cgContext)
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
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

    // MARK: - Select Tool

    /// State for the select tool's mouse interaction.
    private enum SelectDragMode {
        case none
        case movingSelection
        case drawingMarquee
    }

    private var selectDragMode: SelectDragMode = .none
    private var selectPressPoint: CGPoint = .zero
    private var selectCurrentPoint: CGPoint = .zero
    /// Total delta accumulated during a move drag, applied once on mouseUp.
    private var selectMoveTotalDelta: CGSize = .zero
    /// Last point during a move drag for incremental delta computation.
    private var selectMoveLastPoint: CGPoint = .zero

    private func handleSelectMouseDown(at point: CGPoint, event: NSEvent) {
        let shiftHeld = event.modifierFlags.contains(.shift)
        selectPressPoint = point

        // Check if clicking on a selected item's bounding box (for move drag)
        if let bbox = drawingState.selection.boundingBox(in: drawingState.items),
           bbox.contains(point),
           !drawingState.selection.isEmpty {
            selectDragMode = .movingSelection
            selectMoveLastPoint = point
            selectMoveTotalDelta = .zero
            return
        }

        // Check if clicking on an item
        let threshold: CGFloat = 10
        if let hitItem = SelectionManager.topmostHit(at: point, threshold: threshold, in: drawingState.items) {
            if shiftHeld {
                // Shift-click: toggle membership (Requirements 2.8, 2.9)
                drawingState.selection.toggle(hitItem.id)
            } else {
                // Plain click: select only this item (Requirement 2.4)
                drawingState.selection.set([hitItem.id])
            }
            needsDisplay = true
            return
        }

        // Click on empty space
        if !shiftHeld {
            // No shift: clear the selection (Requirement 2.5)
            drawingState.selection.clear()
        }
        // Start a marquee drag (Requirement 2.6)
        selectDragMode = .drawingMarquee
        selectCurrentPoint = point
        needsDisplay = true
    }

    private func handleSelectMouseDragged(at point: CGPoint) {
        switch selectDragMode {
        case .none:
            break
        case .movingSelection:
            let incrementalDelta = CGSize(
                width: point.x - selectMoveLastPoint.x,
                height: point.y - selectMoveLastPoint.y
            )
            selectMoveLastPoint = point
            selectMoveTotalDelta = CGSize(
                width: selectMoveTotalDelta.width + incrementalDelta.width,
                height: selectMoveTotalDelta.height + incrementalDelta.height
            )
            // Live visual feedback: translate selected items directly
            for item in drawingState.items where drawingState.selection.contains(item.id) {
                item.translate(by: incrementalDelta)
            }
            needsDisplay = true
        case .drawingMarquee:
            selectCurrentPoint = point
            needsDisplay = true
        }
    }

    private func handleSelectMouseUp(at point: CGPoint) {
        defer {
            selectDragMode = .none
            selectPressPoint = .zero
            selectCurrentPoint = .zero
        }

        switch selectDragMode {
        case .none:
            break
        case .movingSelection:
            finishMoveDrag()
        case .drawingMarquee:
            finishMarqueeDrag()
        }
    }

    private func finishMoveDrag() {
        let netDx = abs(selectMoveTotalDelta.width)
        let netDy = abs(selectMoveTotalDelta.height)

        if max(netDx, netDy) < 1.0 {
            // Below threshold: undo the live preview and record nothing (Requirement 3.10)
            let negated = CGSize(width: -selectMoveTotalDelta.width, height: -selectMoveTotalDelta.height)
            for item in drawingState.items where drawingState.selection.contains(item.id) {
                item.translate(by: negated)
            }
        } else {
            // Clamp: ensure at least 20pt of selection bounding box remains visible (Requirement 3.9)
            let clampedDelta = clampMoveDelta(selectMoveTotalDelta)

            // Undo the live preview translation
            let negated = CGSize(width: -selectMoveTotalDelta.width, height: -selectMoveTotalDelta.height)
            for item in drawingState.items where drawingState.selection.contains(item.id) {
                item.translate(by: negated)
            }

            // Apply the clamped delta through DrawingState (records one .move)
            let selectedIDs = Array(drawingState.selection.selectedIDs)
            drawingState.translate(ids: selectedIDs, by: clampedDelta)
        }
        // Selection retained after move (Requirement 3.11)
        selectMoveTotalDelta = .zero
    }

    /// Clamps a move delta so at least 20pt of the selection bounding box stays
    /// within the overlay view bounds (Requirement 3.9).
    private func clampMoveDelta(_ delta: CGSize) -> CGSize {
        guard let bbox = drawingState.selection.boundingBox(in: drawingState.items) else {
            return delta
        }
        let viewBounds = self.bounds
        let minVisible: CGFloat = 20

        // Compute where the bbox would end up with the unclamped delta
        // (note: items already have the live preview applied, so bbox reflects
        // the current visual position; we need to compute from the original position)
        // Since we undo live preview before applying clamped, we compute from
        // the original bbox (before any preview translation was applied).
        // Actually, at this point the live preview IS already applied to the items,
        // so bbox is the "moved" position. We need the original bbox.
        // The original bbox = current bbox offset by -selectMoveTotalDelta
        let originalBbox = bbox.offsetBy(dx: -selectMoveTotalDelta.width, dy: -selectMoveTotalDelta.height)

        // Now compute where originalBbox + delta would land
        var clampedDx = delta.width
        var clampedDy = delta.height

        let movedBbox = originalBbox.offsetBy(dx: clampedDx, dy: clampedDy)

        // Clamp horizontal: ensure at least minVisible overlap with viewBounds
        if movedBbox.maxX < viewBounds.minX + minVisible {
            clampedDx = (viewBounds.minX + minVisible) - originalBbox.maxX
        } else if movedBbox.minX > viewBounds.maxX - minVisible {
            clampedDx = (viewBounds.maxX - minVisible) - originalBbox.minX
        }

        // Clamp vertical: ensure at least minVisible overlap with viewBounds
        let movedBboxV = originalBbox.offsetBy(dx: clampedDx, dy: clampedDy)
        if movedBboxV.maxY < viewBounds.minY + minVisible {
            clampedDy = (viewBounds.minY + minVisible) - originalBbox.maxY
        } else if movedBboxV.minY > viewBounds.maxY - minVisible {
            clampedDy = (viewBounds.maxY - minVisible) - originalBbox.minY
        }

        return CGSize(width: clampedDx, height: clampedDy)
    }

    private func finishMarqueeDrag() {
        let marquee = rectFromPoints(selectPressPoint, selectCurrentPoint)
        if marquee.width > 0 || marquee.height > 0 {
            let ids = SelectionManager.itemsIntersecting(marquee, in: drawingState.items)
            drawingState.selection.set(ids)
        }
        needsDisplay = true
    }

    /// Constructs a normalized rect from two corner points.
    private func rectFromPoints(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        let x = min(a.x, b.x)
        let y = min(a.y, b.y)
        let w = abs(b.x - a.x)
        let h = abs(b.y - a.y)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    // MARK: - Keyboard Events

    override var acceptsFirstResponder: Bool { true }

    /// Routes command-key combinations through ShortcutStore before the system
    /// responder chain can swallow them. macOS dispatches Cmd+key via
    /// performKeyEquivalent, not keyDown, so without this override Cmd+Z,
    /// Cmd+Shift+Z, Cmd+Delete, and Cmd+A would be silently dropped in a
    /// borderless floating window that has no main menu.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Only handle key-down with Command held
        guard event.type == .keyDown, event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }

        // Don't intercept while text editing — let the field handle Cmd+A, etc.
        if textEditing.isEditing {
            return super.performKeyEquivalent(with: event)
        }

        let relevantModifiers: NSEvent.ModifierFlags = [.control, .shift, .option, .command]
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).intersection(relevantModifiers)

        if let action = ShortcutStore.shared.resolve(
            keyCode: event.keyCode,
            modifiers: mods,
            scope: .overlay
        ) {
            performShortcutAction(action)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

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

        // Resolve through ShortcutStore (Requirement 6.10)
        let relevantModifiers: NSEvent.ModifierFlags = [.control, .shift, .option, .command]
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).intersection(relevantModifiers)

        // First try overlay scope
        if let action = ShortcutStore.shared.resolve(
            keyCode: event.keyCode,
            modifiers: mods,
            scope: .overlay
        ) {
            performShortcutAction(action)
            return
        }

        // Fallback: also resolve global shortcuts that originate from within the overlay.
        // When the CGEvent tap is not active (e.g. no Accessibility permission), global
        // shortcuts like toggleAnnotation still need to reach the view via keyDown.
        if let globalAction = ShortcutStore.shared.resolve(
            keyCode: event.keyCode,
            modifiers: mods,
            scope: .global
        ) {
            if globalAction == .toggleAnnotation {
                onDeactivate?()
                return
            }
        }

        super.keyDown(with: event)
    }

    /// Dispatches a resolved overlay ShortcutAction.
    private func performShortcutAction(_ action: ShortcutAction) {
        switch action {
        // Tools
        case .toolPen: drawingState.activeTool = .pen
        case .toolArrow: drawingState.activeTool = .arrow
        case .toolRectangle: drawingState.activeTool = .rectangle
        case .toolCircle: drawingState.activeTool = .circle
        case .toolLine: drawingState.activeTool = .line
        case .toolHighlighter: drawingState.activeTool = .highlighter
        case .toolEraser: drawingState.activeTool = .eraser
        case .toolText: drawingState.activeTool = .text
        case .toolSelect: drawingState.activeTool = .select

        // Colors
        case .colorRed: drawingState.activeColor = .systemRed
        case .colorBlue: drawingState.activeColor = .systemBlue
        case .colorGreen: drawingState.activeColor = .systemGreen
        case .colorYellow: drawingState.activeColor = .systemYellow
        case .colorWhite: drawingState.activeColor = .white

        // Actions
        case .undo:
            drawingState.undo()
            needsDisplay = true
        case .redo:
            drawingState.redo()
            needsDisplay = true
        case .clearAll:
            clearAll()
        case .cycleBoardMode:
            toggleBoard()
        case .toggleFadeMode:
            drawingState.fadeMode.toggle()
        case .deleteSelection:
            drawingState.removeSelected()
            needsDisplay = true
        case .selectAll:
            drawingState.selectAll()
            needsDisplay = true
        case .deactivateOverlay:
            onDeactivate?()

        // Global actions that reach the overlay are no-ops here — they are
        // handled by the CGEvent tap in HotkeyManager.
        default:
            break
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

    /// Called when the overlay is about to deactivate. Clears selection
    /// (Requirement 2.13) and any in-progress editing state.
    func prepareForDeactivation() {
        drawingState.selection.clear()
        if textEditing.isEditing {
            finishTextEditing()
        }
        needsDisplay = true
    }

    // MARK: - Mode Indicator

    private var modeIndicatorView: ModeIndicatorView?

    /// Updates the mode indicator badge visibility and state.
    /// Called by OverlayWindowController when passthrough state changes.
    func updateModeIndicator(showIndicator: Bool, isCapturing: Bool) {
        if showIndicator {
            if modeIndicatorView == nil {
                let indicator = ModeIndicatorView(frame: .zero)
                indicator.translatesAutoresizingMaskIntoConstraints = false
                addSubview(indicator)
                NSLayoutConstraint.activate([
                    indicator.centerXAnchor.constraint(equalTo: centerXAnchor),
                    indicator.topAnchor.constraint(equalTo: topAnchor, constant: 8),
                    indicator.widthAnchor.constraint(equalToConstant: 120),
                    indicator.heightAnchor.constraint(equalToConstant: 32)
                ])
                modeIndicatorView = indicator
            }
            modeIndicatorView?.isCapturing = isCapturing
            modeIndicatorView?.isHidden = false
        } else {
            modeIndicatorView?.isHidden = true
        }
    }

    // MARK: - Passthrough Drain

    /// Commits any in-progress drawing gesture or text edit so the overlay can
    /// safely enter passthrough state. Requirements 8.4, 8.5.
    func drainForPassthrough() {
        // Commit in-progress drawing gesture at current position (Requirement 8.4)
        if isDrawing {
            commitCurrentDrawing()
        }

        // Commit any open text edit (Requirement 8.5)
        if textEditing.isEditing {
            finishTextEditing()
        }

        // Cancel any in-progress select drag
        if selectDragMode != .none {
            selectDragMode = .none
            selectPressPoint = .zero
            selectCurrentPoint = .zero
        }

        needsDisplay = true
    }

    /// Commits the current in-progress drawing stroke/shape using whatever
    /// points have been accumulated so far, without waiting for mouseUp.
    private func commitCurrentDrawing() {
        isDrawing = false

        switch drawingState.activeTool {
        case .pen:
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
            let arrow = ArrowShape(
                start: shapeStartPoint,
                end: currentShapeEndPoint,
                color: drawingState.activeColor,
                lineWidth: drawingState.activeLineWidth
            )
            drawingState.addItem(arrow)

        case .rectangle:
            var rect = DrawingRenderer.rectFrom(start: shapeStartPoint, end: currentShapeEndPoint)
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
            var rect = DrawingRenderer.rectFrom(start: shapeStartPoint, end: currentShapeEndPoint)
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
            let shape = LineShape(
                start: shapeStartPoint,
                end: currentShapeEndPoint,
                color: drawingState.activeColor,
                lineWidth: drawingState.activeLineWidth
            )
            drawingState.addItem(shape)

        case .eraser, .text, .select:
            break
        }
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
