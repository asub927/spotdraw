// OverlayView.swift
// NSView subclass that handles mouse input for freehand drawing and shape creation,
// processes keyboard shortcuts for tool switching and undo/redo, renders committed
// drawing items and in-progress strokes via Core Graphics, and manages a fade timer
// that gradually removes old annotations when fade mode is active.

import Cocoa
import SpotdrawCore

// MARK: - OverlayView

@MainActor internal final class OverlayView: NSView {

    // MARK: - Properties

    var drawingState = DrawingState()
    var onDeactivate: (() -> Void)?
    /// The in-progress shape/freehand gesture, if any. Nil when not drawing.
    /// Owns all shape geometry accumulation and commit rules (see ShapeGesture).
    private var shapeGesture: ShapeGesture?
    private var isShiftHeld = false
    private var fadeTimer: Timer?

    /// True while a shape/freehand gesture is in progress.
    private var isDrawing: Bool { shapeGesture != nil }

    /// Owns the NSTextView subview lifecycle for composing/editing TextAnnotations.
    private let textEditing = TextEditingController()
    /// The TextAnnotation currently being dragged by the text tool, if any.
    private var draggedTextItem: TextAnnotation?
    /// The most recent drag point while dragging a TextAnnotation with the text tool,
    /// used to compute the incremental delta for live visual feedback.
    private var textDragLastPoint: CGPoint = .zero
    /// The total delta accumulated since the text-tool drag began, applied to
    /// DrawingState exactly once on mouseUp so only one `.move` is recorded.
    private var textDragTotalDelta: CGSize = .zero

    /// Returns the CGDirectDisplayID for this view's screen.
    /// Falls back to CGMainDisplayID() if the window or screen is unavailable.
    var displayID: CGDirectDisplayID {
        guard let screen = window?.screen,
              let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { return CGMainDisplayID() }
        return screenNumber
    }

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
        // Only render items belonging to this display (Requirements 1.1, 1.2).
        let myDisplay = displayID
        let editingID = textEditing.editingItem?.id
        for item in drawingState.items {
            if item.opacity > 0 && item.id != editingID && item.screenID == myDisplay {
                item.render(in: context)
            }
        }

        // Draw current in-progress item
        if isDrawing {
            drawCurrentItem(in: context)
        }

        // Draw marquee and selection outlines on top of items (Requirements 2.11, 2.15, 10.7)
        if let marquee = selectInteraction.marqueeRect {
            SelectionRenderer.drawMarquee(from: CGPoint(x: marquee.minX, y: marquee.minY),
                                          to: CGPoint(x: marquee.maxX, y: marquee.maxY),
                                          in: context)
        }
        if !drawingState.selection.isEmpty {
            let localItems = drawingState.items.filter { $0.screenID == myDisplay }
            SelectionRenderer.drawSelectionOutlines(
                selectedIDs: drawingState.selection.selectedIDs,
                items: localItems,
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
        guard let gesture = shapeGesture else { return }
        let color = drawingState.activeColor
        let width = drawingState.activeLineWidth
        switch gesture.previewGeometry(shiftHeld: isShiftHeld) {
        case .none:
            break
        case .stroke(let points):
            let alpha: CGFloat = gesture.tool == .highlighter ? 0.3 : 1.0
            let strokeWidth = gesture.tool == .highlighter ? width * 4 : width
            DrawingRenderer.drawStroke(points: points, color: color, lineWidth: strokeWidth, alpha: alpha, in: context)
        case .arrow(let start, let end):
            DrawingRenderer.drawArrow(from: start, to: end, color: color, lineWidth: width, in: context)
        case .line(let start, let end):
            DrawingRenderer.drawLine(from: start, to: end, color: color, lineWidth: width, in: context)
        case .rectangle(let rect):
            DrawingRenderer.drawRectangle(rect, color: color, lineWidth: width, in: context)
        case .circle(let rect):
            DrawingRenderer.drawCircle(in: rect, color: color, lineWidth: width, in: context)
        }
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // Click-outside text field commits the current edit (Requirement 5.5)
        if textEditing.isEditing, let frame = textEditing.scrollViewFrame, !frame.contains(point) {
            textEditing.commitAndNotify()
            // Fall through to process the click at the new location
        }

        isShiftHeld = event.modifierFlags.contains(.shift)

        switch drawingState.activeTool {
        case .pen, .highlighter, .arrow, .rectangle, .circle, .line:
            shapeGesture = ShapeGesture(tool: drawingState.activeTool, startingAt: point)
        case .eraser:
            drawingState.removeItems(intersecting: point, threshold: 15, screenID: displayID)
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
        case .pen, .highlighter, .arrow, .rectangle, .circle, .line:
            shapeGesture?.extend(to: point)
        case .eraser:
            drawingState.removeItems(intersecting: point, threshold: 15, screenID: displayID)
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

        switch drawingState.activeTool {
        case .pen, .highlighter, .arrow, .rectangle, .circle, .line:
            if var gesture = shapeGesture {
                gesture.extend(to: point)
                if let item = gesture.commit(
                    shiftHeld: isShiftHeld,
                    color: drawingState.activeColor,
                    lineWidth: drawingState.activeLineWidth,
                    screenID: displayID
                ) {
                    drawingState.addItem(item)
                }
            }
            shapeGesture = nil

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
    /// Only tests items on this screen (Requirements 1.1, 1.2).
    private func topmostTextAnnotation(at point: CGPoint) -> TextAnnotation? {
        for item in drawingState.items.reversed() {
            if let text = item as? TextAnnotation, text.screenID == displayID, text.bounds.contains(point) {
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
            created.screenID = displayID
            drawingState.addItem(created)
        case .edited(let original, let updated):
            if let index = drawingState.items.firstIndex(where: { $0.id == original.id }) {
                drawingState.replaceItem(at: index, with: updated)
            }
        }
        needsDisplay = true
    }

    // MARK: - Select Tool

    /// Pure state machine for the select tool's press/drag/release lifecycle.
    /// The view interprets the InteractionOutcomes it returns into DrawingState
    /// mutations, live-preview translations, and redraws.
    private var selectInteraction = SelectInteraction()

    private func handleSelectMouseDown(at point: CGPoint, event: NSEvent) {
        let shiftHeld = event.modifierFlags.contains(.shift)
        let hit = hitResult(at: point)
        let bbox = drawingState.selection.boundingBox(in: drawingState.items)
        let outcome = selectInteraction.begin(at: point, shiftHeld: shiftHeld,
                                              hit: hit, currentBBox: bbox)
        apply(outcome)
    }

    private func handleSelectMouseDragged(at point: CGPoint) {
        apply(selectInteraction.drag(to: point))
    }

    private func handleSelectMouseUp(at point: CGPoint) {
        // Capture the accumulated preview delta BEFORE end() resets it, so a
        // committed move can undo the live preview before reapplying the clamped
        // total through DrawingState (records exactly one .move).
        let previewDelta = selectInteraction.accumulatedMoveDelta
        let outcome = selectInteraction.end(viewBounds: bounds)
        apply(outcome, previewDelta: previewDelta)
    }

    /// Classifies the press point the way the old handler did: selection box first
    /// (for move drags), then a topmost item hit, then empty space.
    private func hitResult(at point: CGPoint) -> HitResult {
        if !drawingState.selection.isEmpty,
           let bbox = drawingState.selection.boundingBox(in: drawingState.items),
           bbox.contains(point) {
            return .insideSelectionBox
        }
        let localItems = drawingState.items.filter { $0.screenID == displayID }
        if let hit = SelectionManager.topmostHit(at: point, threshold: 10, in: localItems) {
            return .hitItem(hit.id)
        }
        return .emptySpace
    }

    /// Interprets a select InteractionOutcome. `previewDelta` is the live-preview
    /// delta accumulated before `end()` reset it, needed to undo the preview on commit.
    private func apply(_ outcome: InteractionOutcome, previewDelta: CGSize = .zero) {
        switch outcome {
        case .none:
            break

        case .setSelection(let ids):
            drawingState.selection.set(ids)
            needsDisplay = true

        case .toggleSelection(let id):
            drawingState.selection.toggle(id)
            needsDisplay = true

        case .clearSelection:
            drawingState.selection.clear()
            needsDisplay = true

        case .previewTranslate(let delta):
            // Live visual feedback: translate selected items directly, bypassing
            // the undo stack (a single .move is recorded on commit).
            for item in drawingState.items where drawingState.selection.contains(item.id) {
                item.translate(by: delta)
            }
            needsDisplay = true

        case .marquee:
            // Marquee rect is read from selectInteraction.marqueeRect during draw().
            needsDisplay = true

        case .commitMarquee(let rect):
            if rect.width > 0 || rect.height > 0 {
                let localItems = drawingState.items.filter { $0.screenID == displayID }
                let ids = SelectionManager.itemsIntersecting(rect, in: localItems)
                drawingState.selection.set(ids)
            }
            needsDisplay = true

        case .commitMove(let delta):
            // Undo the live preview (items already carry previewDelta), then apply
            // the clamped total once through DrawingState. When delta == .zero the
            // move was below threshold: undo the preview and record nothing.
            let negated = CGSize(width: -previewDelta.width, height: -previewDelta.height)
            for item in drawingState.items where drawingState.selection.contains(item.id) {
                item.translate(by: negated)
            }
            if delta != .zero {
                let selectedIDs = Array(drawingState.selection.selectedIDs)
                drawingState.translate(ids: selectedIDs, by: delta)
            }
            needsDisplay = true
        }
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
        // Exception: Cmd+Return commits the text edit (Requirement 5.4).
        if textEditing.isEditing {
            if event.keyCode == 36 {
                finishTextEditing()
                return true
            }
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
        // While editing, the NSTextView is first responder and receives keys directly;
        // this guard covers the case where focus has not yet transferred to it.
        if textEditing.isEditing {
            // Raw key codes (no Carbon import elsewhere in this project):
            // 53 = Escape
            if event.keyCode == 53 {
                finishTextEditing()
                return
            }
            // Cmd+Return commits (Requirement 5.4).
            // Plain Return inserts a newline (Requirement 5.2) — handled by NSTextView.
            if event.keyCode == 36 && event.modifierFlags.contains(.command) {
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
        if selectInteraction.mode != .none {
            selectInteraction = SelectInteraction()
        }

        needsDisplay = true
    }

    /// Commits the current in-progress drawing stroke/shape using whatever
    /// points have been accumulated so far, without waiting for mouseUp.
    private func commitCurrentDrawing() {
        guard let gesture = shapeGesture else { return }
        if let item = gesture.commit(
            shiftHeld: isShiftHeld,
            color: drawingState.activeColor,
            lineWidth: drawingState.activeLineWidth,
            screenID: displayID
        ) {
            drawingState.addItem(item)
        }
        shapeGesture = nil
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
