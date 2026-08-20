// ToolbarPanelController.swift
// Unified dynamic floating toolbar panel that shows sections only for currently
// active features: annotation, cursor highlight, spotlight, and zoom.
// The panel grows/shrinks horizontally as sections are added or removed.

import Cocoa

// MARK: - FeatureState

/// Describes which SpotDraw features are currently active so the toolbar can
/// show only the relevant sections.
internal struct FeatureState: Equatable {
    var annotationActive: Bool
    var highlightActive: Bool
    var spotlightActive: Bool
    var zoomActive: Bool

    /// True if any feature is active and the panel should be visible.
    var anyActive: Bool {
        annotationActive || highlightActive || spotlightActive || zoomActive
    }
}

// MARK: - ToolbarPanelController

/// Manages a floating non-activating panel containing sections for each active
/// feature. Rebuilds its layout dynamically when the active feature set changes.
@MainActor internal final class ToolbarPanelController {

    // MARK: - Constants

    private enum Layout {
        static let panelHeight: CGFloat = 60
        static let cornerRadius: CGFloat = 10
        static let topOffset: CGFloat = 50
        static let itemSpacing: CGFloat = 10
        static let swatchDiameter: CGFloat = 28
        static let smallSwatchDiameter: CGFloat = 22
        static let iconSize: CGFloat = 24
        static let smallButtonSize: CGFloat = 20
        static let horizontalPadding: CGFloat = 12
        static let separatorWidth: CGFloat = 1
        static let separatorHeight: CGFloat = 24
        static let labelFontSize: CGFloat = 9
    }

    // MARK: - Properties

    private var panel: NSPanel?
    private var contentView: UnifiedToolbarContentView?
    private weak var drawingState: DrawingState?
    private weak var cursorManager: CursorManager?
    private var currentFeatures = FeatureState(annotationActive: false, highlightActive: false, spotlightActive: false, zoomActive: false)
    private var refreshTimer: Timer?
    private var panelDismissed = false

    // MARK: - Public API

    /// Updates the panel to reflect the current feature state. Rebuilds the panel
    /// content if active features changed.
    func update(features: FeatureState, drawingState: DrawingState?, cursorManager: CursorManager?) {
        self.drawingState = drawingState
        self.cursorManager = cursorManager

        if panelDismissed && features.anyActive {
            // User dismissed panel, keep it hidden until all features deactivate
        }

        if !features.anyActive {
            hide()
            panelDismissed = false
            currentFeatures = features
            return
        }

        if panelDismissed {
            currentFeatures = features
            return
        }

        let featuresChanged = (currentFeatures != features)
        currentFeatures = features

        if featuresChanged || panel == nil {
            rebuildPanel()
        }

        updateIndicators()
        panel?.orderFrontRegardless()
        startRefreshTimer()
    }

    /// Hides the toolbar panel.
    func hide() {
        stopRefreshTimer()
        panel?.orderOut(nil)
    }

    /// Dismisses the panel for the current session (user clicked dismiss button).
    private func dismiss() {
        stopRefreshTimer()
        panel?.orderOut(nil)
        panelDismissed = true
    }

    // MARK: - Panel Rebuild

    private func rebuildPanel() {
        // Preserve position if panel already exists
        let previousOrigin = panel?.frame.origin

        panel?.orderOut(nil)
        panel = nil
        contentView = nil

        let content = UnifiedToolbarContentView(
            features: currentFeatures,
            drawingState: drawingState,
            cursorManager: cursorManager
        )
        content.onDismiss = { [weak self] in self?.dismiss() }
        content.onDragMoved = { [weak self] delta in self?.movePanel(by: delta) }
        self.contentView = content

        let panelWidth = content.computedWidth
        let panelFrame: NSRect

        if let origin = previousOrigin {
            panelFrame = NSRect(x: origin.x, y: origin.y, width: panelWidth, height: Layout.panelHeight)
        } else {
            panelFrame = initialFrame(width: panelWidth)
        }

        let panelWindow = NSPanel(
            contentRect: panelFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panelWindow.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 2)
        panelWindow.backgroundColor = .clear
        panelWindow.isOpaque = false
        panelWindow.hasShadow = true
        panelWindow.hidesOnDeactivate = false
        panelWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panelWindow.isReleasedWhenClosed = false
        panelWindow.isMovableByWindowBackground = false
        panelWindow.contentView = content

        self.panel = panelWindow
    }

    private func initialFrame(width: CGFloat) -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 100, y: 100, width: width, height: Layout.panelHeight)
        }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - width / 2
        let y = screenFrame.maxY - Layout.topOffset - Layout.panelHeight
        return NSRect(x: x, y: y, width: width, height: Layout.panelHeight)
    }

    // MARK: - Dragging

    private func movePanel(by delta: CGPoint) {
        guard let panel = panel, let screen = NSScreen.main else { return }
        var newOrigin = panel.frame.origin
        newOrigin.x += delta.x
        newOrigin.y += delta.y

        let screenFrame = screen.visibleFrame
        newOrigin.x = max(screenFrame.minX, min(newOrigin.x, screenFrame.maxX - panel.frame.width))
        newOrigin.y = max(screenFrame.minY, min(newOrigin.y, screenFrame.maxY - panel.frame.height))

        panel.setFrameOrigin(newOrigin)
    }

    // MARK: - Refresh Timer

    private func startRefreshTimer() {
        stopRefreshTimer()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateIndicators()
            }
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func updateIndicators() {
        guard let contentView else { return }
        contentView.updateActiveState(
            drawingState: drawingState,
            cursorManager: cursorManager
        )
    }
}

// MARK: - UnifiedToolbarContentView

/// Root view for the unified toolbar panel. Builds sections dynamically based on
/// which features are active.
@MainActor private final class UnifiedToolbarContentView: NSView {

    // MARK: - Callbacks

    var onDismiss: (() -> Void)?
    var onDragMoved: ((CGPoint) -> Void)?

    // MARK: - State

    private weak var drawingState: DrawingState?
    private weak var cursorManager: CursorManager?
    private let features: FeatureState
    private let settings = SettingsManager.shared

    // Annotation section tracking
    private var annotationColorButtons: [AnnotationColorSwatchButton] = []
    private var annotationToolButtons: [AnnotationToolIconButton] = []

    // Highlight section tracking
    private var highlightColorButtons: [SmallColorSwatchButton] = []
    private var highlightSizeButtons: [LabelButton] = []
    private var highlightShapeButtons: [ShapeIconButton] = []
    private var glowButton: LabelButton?

    // Spotlight section tracking
    private var spotlightSizeButtons: [IconButton] = []
    private var spotlightDimButtons: [IconButton] = []

    // Zoom section tracking
    private var zoomMinusButton: LabelButton?
    private var zoomPlusButton: LabelButton?
    private var zoomLevelLabel: NSTextField?
    private var zoomBubbleSizeButtons: [LabelButton] = []

    // MARK: - Layout Constants

    private let hPadding: CGFloat = 16
    private let itemSpacing: CGFloat = 10
    private let panelHeight: CGFloat = 60

    var computedWidth: CGFloat {
        var width: CGFloat = hPadding // leading padding
        width += 24 // drag handle
        width += itemSpacing * 2 // spacing after drag handle

        var sectionCount = 0

        if features.annotationActive {
            // 5 swatches + separator + 6 tools
            let swatchesW = CGFloat(5) * 30 + CGFloat(4) * itemSpacing
            let separatorW: CGFloat = 1 + itemSpacing * 2
            let toolsW = CGFloat(6) * 36 + CGFloat(5) * itemSpacing
            width += swatchesW + separatorW + toolsW
            sectionCount += 1
        }

        if features.highlightActive {
            if sectionCount > 0 { width += itemSpacing + 1 + itemSpacing } // separator
            // Label "Highlight" ~40pt + spacing
            width += 50 + itemSpacing
            // 5 small color swatches
            width += CGFloat(5) * 24 + CGFloat(4) * 6
            width += itemSpacing
            // 4 size buttons (S/M/L/XL)
            width += CGFloat(4) * 30 + CGFloat(3) * 6
            width += itemSpacing
            // 4 shape buttons
            width += CGFloat(4) * 30 + CGFloat(3) * 6
            width += itemSpacing
            // Glow button
            width += 20
            sectionCount += 1
        }

        if features.spotlightActive {
            if sectionCount > 0 { width += itemSpacing + 1 + itemSpacing } // separator
            // Label "Spotlight" ~42pt + spacing
            width += 52 + itemSpacing
            // 3 size buttons (S/M/L)
            width += CGFloat(3) * 30 + CGFloat(2) * 6
            width += itemSpacing
            // 3 dim buttons (L/M/D)
            width += CGFloat(3) * 30 + CGFloat(2) * 6
            sectionCount += 1
        }

        if features.zoomActive {
            if sectionCount > 0 { width += itemSpacing + 1 + itemSpacing } // separator
            // Label "Zoom" ~26pt + spacing
            width += 34 + itemSpacing
            // − button + level label + + button
            width += 30 + 6 + 40 + 6 + 30
            width += itemSpacing
            // 3 bubble size buttons (S/M/L)
            width += CGFloat(3) * 30 + CGFloat(2) * 6
            sectionCount += 1
        }

        width += itemSpacing // before dismiss
        width += 26 // dismiss button
        width += hPadding // trailing padding

        return width
    }

    // MARK: - Init

    init(features: FeatureState, drawingState: DrawingState?, cursorManager: CursorManager?) {
        self.features = features
        self.drawingState = drawingState
        self.cursorManager = cursorManager
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: panelHeight))
        wantsLayer = true
        setupSubviews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: - Setup

    private func setupSubviews() {
        let width = computedWidth
        frame = NSRect(x: 0, y: 0, width: width, height: panelHeight)

        var x = hPadding

        // Drag handle (always present at leading edge)
        let dragHandle = DragHandleView(frame: NSRect(x: x, y: (panelHeight - 22) / 2, width: 27, height: 22))
        dragHandle.onDrag = { [weak self] delta in self?.onDragMoved?(delta) }
        addSubview(dragHandle)
        x += 27 + itemSpacing * 2

        var sectionCount = 0

        // --- Section 1: Annotation ---
        if features.annotationActive {
            x = buildAnnotationSection(at: x)
            sectionCount += 1
        }

        // --- Section 2: Cursor Highlight ---
        if features.highlightActive {
            if sectionCount > 0 {
                let sep = SeparatorView(frame: NSRect(x: x + itemSpacing, y: (panelHeight - 36) / 2, width: 1, height: 36))
                addSubview(sep)
                x += itemSpacing + 1 + itemSpacing
            }
            x = buildHighlightSection(at: x)
            sectionCount += 1
        }

        // --- Section 3: Spotlight ---
        if features.spotlightActive {
            if sectionCount > 0 {
                let sep = SeparatorView(frame: NSRect(x: x + itemSpacing, y: (panelHeight - 36) / 2, width: 1, height: 36))
                addSubview(sep)
                x += itemSpacing + 1 + itemSpacing
            }
            x = buildSpotlightSection(at: x)
            sectionCount += 1
        }

        // --- Section 4: Zoom ---
        if features.zoomActive {
            if sectionCount > 0 {
                let sep = SeparatorView(frame: NSRect(x: x + itemSpacing, y: (panelHeight - 36) / 2, width: 1, height: 36))
                addSubview(sep)
                x += itemSpacing + 1 + itemSpacing
            }
            x = buildZoomSection(at: x)
            sectionCount += 1
        }

        // Dismiss button (always at trailing edge)
        x += itemSpacing
        let dismissButton = DismissButtonView(frame: NSRect(x: x, y: (panelHeight - 30) / 2, width: 30, height: 30))
        dismissButton.onTap = { [weak self] in self?.onDismiss?() }
        addSubview(dismissButton)
    }

    // MARK: - Annotation Section Builder

    private func buildAnnotationSection(at startX: CGFloat) -> CGFloat {
        var x = startX

        // 5 color swatches
        let colors: [(ColorShortcut, NSColor)] = [
            (.red, .systemRed),
            (.blue, .systemBlue),
            (.green, .systemGreen),
            (.yellow, .systemYellow),
            (.white, .white)
        ]
        for (shortcut, color) in colors {
            let btn = AnnotationColorSwatchButton(
                frame: NSRect(x: x, y: (panelHeight - 30) / 2, width: 30, height: 30),
                swatchColor: color,
                shortcut: shortcut
            )
            btn.onTap = { [weak self] sc in self?.annotationColorTapped(sc) }
            addSubview(btn)
            annotationColorButtons.append(btn)
            x += 20 + itemSpacing
        }
        x -= itemSpacing
        x += itemSpacing

        // Separator between colors and tools
        let sep = SeparatorView(frame: NSRect(x: x, y: (panelHeight - 36) / 2, width: 1, height: 36))
        addSubview(sep)
        x += 1 + itemSpacing

        // 6 tool icons
        let tools: [(ToolType, String)] = [
            (.pen, "pencil.tip"),
            (.arrow, "arrow.up.right"),
            (.rectangle, "rectangle"),
            (.circle, "circle"),
            (.text, "textformat"),
            (.eraser, "eraser")
        ]
        for (tool, symbolName) in tools {
            let btn = AnnotationToolIconButton(
                frame: NSRect(x: x, y: (panelHeight - 36) / 2, width: 36, height: 36),
                tool: tool,
                symbolName: symbolName
            )
            btn.onTap = { [weak self] t in self?.annotationToolTapped(t) }
            addSubview(btn)
            annotationToolButtons.append(btn)
            x += 24 + itemSpacing
        }
        x -= itemSpacing

        return x
    }

    // MARK: - Highlight Section Builder

    private func buildHighlightSection(at startX: CGFloat) -> CGFloat {
        var x = startX

        // Label
        let label = makeSectionLabel("Highlight", at: x)
        addSubview(label)
        x += label.frame.width + itemSpacing

        // Color swatches (smaller 16pt)
        let colors: [(String, NSColor)] = [
            ("yellow", .systemYellow),
            ("red", .systemRed),
            ("blue", .systemBlue),
            ("green", .systemGreen),
            ("white", .white)
        ]
        for (name, color) in colors {
            let btn = SmallColorSwatchButton(
                frame: NSRect(x: x, y: (panelHeight - 24) / 2, width: 24, height: 24),
                swatchColor: color,
                colorName: name
            )
            btn.onTap = { [weak self] c in self?.highlightColorTapped(c) }
            addSubview(btn)
            highlightColorButtons.append(btn)
            x += 24 + 6
        }
        x -= 6
        x += itemSpacing

        // Size buttons S/M/L/XL (30/50/100/150)
        let sizes: [(String, CGFloat)] = [("S", 30), ("M", 50), ("L", 100), ("XL", 150)]
        for (label, size) in sizes {
            let btn = LabelButton(
                frame: NSRect(x: x, y: (panelHeight - 30) / 2, width: 30, height: 30),
                label: label,
                tag: Int(size)
            )
            btn.onTap = { [weak self] tag in self?.highlightSizeTapped(CGFloat(tag)) }
            addSubview(btn)
            highlightSizeButtons.append(btn)
            x += 20 + 4
        }
        x -= 4
        x += itemSpacing

        // Shape buttons
        let shapes: [(HighlightShape, String)] = [
            (.circle, "circle.fill"),
            (.ring, "circle"),
            (.square, "square"),
            (.crosshair, "plus")
        ]
        for (shape, symbolName) in shapes {
            let btn = ShapeIconButton(
                frame: NSRect(x: x, y: (panelHeight - 30) / 2, width: 30, height: 30),
                shape: shape,
                symbolName: symbolName
            )
            btn.onTap = { [weak self] s in self?.highlightShapeTapped(s) }
            addSubview(btn)
            highlightShapeButtons.append(btn)
            x += 30 + 6
        }
        x -= 6
        x += itemSpacing

        // Glow toggle button
        let gBtn = LabelButton(
            frame: NSRect(x: x, y: (panelHeight - 30) / 2, width: 30, height: 30),
            label: "G",
            tag: 0
        )
        gBtn.onTap = { [weak self] _ in self?.glowToggleTapped() }
        addSubview(gBtn)
        glowButton = gBtn
        x += 30

        return x
    }

    // MARK: - Spotlight Section Builder

    private func buildSpotlightSection(at startX: CGFloat) -> CGFloat {
        var x = startX

        // Label
        let label = makeSectionLabel("Spotlight", at: x)
        addSubview(label)
        x += label.frame.width + itemSpacing

        // Size buttons: small/medium/large circle icons (75/150/225)
        // Uses progressively larger circle SF Symbols to visually convey size.
        let sizes: [(String, CGFloat, String)] = [
            ("smallcircle.filled.circle", 75, "Small spotlight"),
            ("circle.inset.filled", 150, "Medium spotlight"),
            ("circle.fill", 225, "Large spotlight")
        ]
        for (symbolName, size, tooltip) in sizes {
            let btn = IconButton(
                frame: NSRect(x: x, y: (panelHeight - 30) / 2, width: 30, height: 30),
                symbolName: symbolName,
                pointSize: 14,
                tag: Int(size),
                tooltip: tooltip
            )
            btn.onTap = { [weak self] tag in self?.spotlightSizeTapped(CGFloat(tag)) }
            addSubview(btn)
            spotlightSizeButtons.append(btn)
            x += 30 + 6
        }
        x -= 6
        x += itemSpacing

        // Dim intensity buttons: sun → half → moon to convey brightness of surroundings.
        // Light = less dimming (bright surroundings), Dark = heavy dimming.
        let dims: [(String, Double, String)] = [
            ("sun.max", 0.4, "Light dimming"),
            ("sun.haze", 0.6, "Medium dimming"),
            ("moon.fill", 0.8, "Heavy dimming")
        ]
        for (symbolName, intensity, tooltip) in dims {
            let btn = IconButton(
                frame: NSRect(x: x, y: (panelHeight - 30) / 2, width: 30, height: 30),
                symbolName: symbolName,
                pointSize: 14,
                tag: Int(intensity * 100),
                tooltip: tooltip
            )
            btn.onTap = { [weak self] tag in self?.spotlightDimTapped(CGFloat(tag) / 100.0) }
            addSubview(btn)
            spotlightDimButtons.append(btn)
            x += 30 + 6
        }
        x -= 6

        return x
    }

    // MARK: - Zoom Section Builder

    private func buildZoomSection(at startX: CGFloat) -> CGFloat {
        var x = startX

        // Label
        let label = makeSectionLabel("Zoom", at: x)
        addSubview(label)
        x += label.frame.width + itemSpacing

        // − button
        let minusBtn = LabelButton(
            frame: NSRect(x: x, y: (panelHeight - 30) / 2, width: 30, height: 30),
            label: "−",
            tag: -1
        )
        minusBtn.onTap = { [weak self] _ in self?.zoomOutTapped() }
        addSubview(minusBtn)
        zoomMinusButton = minusBtn
        x += 30 + 6

        // Zoom level label
        let levelLabel = NSTextField(frame: NSRect(x: x, y: (panelHeight - 22) / 2, width: 40, height: 22))
        levelLabel.isEditable = false
        levelLabel.isBordered = false
        levelLabel.isSelectable = false
        levelLabel.backgroundColor = .clear
        levelLabel.textColor = .white
        levelLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        levelLabel.alignment = .center
        levelLabel.stringValue = String(format: "%.1fx", settings.zoomLevel)
        addSubview(levelLabel)
        zoomLevelLabel = levelLabel
        x += 40 + 6

        // + button
        let plusBtn = LabelButton(
            frame: NSRect(x: x, y: (panelHeight - 30) / 2, width: 30, height: 30),
            label: "+",
            tag: 1
        )
        plusBtn.onTap = { [weak self] _ in self?.zoomInTapped() }
        addSubview(plusBtn)
        zoomPlusButton = plusBtn
        x += 30 + itemSpacing

        // Bubble size buttons S/M/L (100/200/300)
        let sizes: [(String, CGFloat)] = [("S", 100), ("M", 200), ("L", 300)]
        for (labelStr, size) in sizes {
            let btn = LabelButton(
                frame: NSRect(x: x, y: (panelHeight - 30) / 2, width: 30, height: 30),
                label: labelStr,
                tag: Int(size)
            )
            btn.onTap = { [weak self] tag in self?.zoomBubbleSizeTapped(CGFloat(tag)) }
            addSubview(btn)
            zoomBubbleSizeButtons.append(btn)
            x += 30 + 6
        }
        x -= 6

        return x
    }

    // MARK: - Helpers

    private func makeSectionLabel(_ text: String, at x: CGFloat) -> NSTextField {
        let label = NSTextField(frame: .zero)
        label.isEditable = false
        label.isBordered = false
        label.isSelectable = false
        label.backgroundColor = .clear
        label.textColor = NSColor.white.withAlphaComponent(0.8)
        label.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        label.stringValue = text
        label.sizeToFit()
        let h = label.frame.height
        label.frame = NSRect(x: x, y: (panelHeight - h) / 2, width: label.frame.width, height: h)
        return label
    }

    // MARK: - Annotation Actions

    private func annotationColorTapped(_ shortcut: ColorShortcut) {
        drawingState?.activeColor = shortcut.color
    }

    private func annotationToolTapped(_ tool: ToolType) {
        drawingState?.activeTool = tool
    }

    // MARK: - Highlight Actions

    private func highlightColorTapped(_ color: NSColor) {
        settings.highlightColor = color
        cursorManager?.updateHighlightAppearance()
    }

    private func highlightSizeTapped(_ size: CGFloat) {
        settings.highlightSize = size
        cursorManager?.updateHighlightAppearance()
    }

    private func highlightShapeTapped(_ shape: HighlightShape) {
        settings.highlightShape = shape
        cursorManager?.updateHighlightAppearance()
    }

    private func glowToggleTapped() {
        settings.glowEnabled.toggle()
        cursorManager?.updateHighlightAppearance()
    }

    // MARK: - Spotlight Actions

    private func spotlightSizeTapped(_ size: CGFloat) {
        settings.spotlightSize = size
        cursorManager?.updateSpotlightAppearance()
    }

    private func spotlightDimTapped(_ intensity: CGFloat) {
        settings.spotlightDimIntensity = intensity
        cursorManager?.updateSpotlightAppearance()
    }

    // MARK: - Zoom Actions

    private func zoomInTapped() {
        cursorManager?.zoomIn()
        zoomLevelLabel?.stringValue = String(format: "%.1fx", settings.zoomLevel)
    }

    private func zoomOutTapped() {
        cursorManager?.zoomOut()
        zoomLevelLabel?.stringValue = String(format: "%.1fx", settings.zoomLevel)
    }

    private func zoomBubbleSizeTapped(_ size: CGFloat) {
        settings.zoomBubbleSize = size
        cursorManager?.updateZoomAppearance()
    }

    // MARK: - Update Active Indicators

    func updateActiveState(drawingState: DrawingState?, cursorManager: CursorManager?) {
        // Annotation indicators
        if let ds = drawingState {
            for btn in annotationColorButtons {
                btn.isActive = btn.swatchColor.isEquivalent(to: ds.activeColor)
            }
            for btn in annotationToolButtons {
                btn.isActive = (btn.tool == ds.activeTool)
            }
        }

        // Highlight indicators
        let currentHighlightColor = settings.highlightColor
        for btn in highlightColorButtons {
            btn.isActive = btn.swatchColor.isEquivalent(to: currentHighlightColor)
        }

        let currentSize = settings.highlightSize
        for btn in highlightSizeButtons {
            btn.isActive = (CGFloat(btn.buttonTag) == currentSize)
        }

        let currentShape = settings.highlightShape
        for btn in highlightShapeButtons {
            btn.isActive = (btn.shape == currentShape)
        }

        glowButton?.isActive = settings.glowEnabled

        // Spotlight indicators
        let spotSize = settings.spotlightSize
        for btn in spotlightSizeButtons {
            btn.isActive = (CGFloat(btn.buttonTag) == spotSize)
        }

        let spotDim = settings.spotlightDimIntensity
        for btn in spotlightDimButtons {
            btn.isActive = (CGFloat(btn.buttonTag) == spotDim * 100)
        }

        // Zoom indicators
        zoomLevelLabel?.stringValue = String(format: "%.1fx", settings.zoomLevel)
        let bubbleSize = settings.zoomBubbleSize
        for btn in zoomBubbleSizeButtons {
            btn.isActive = (CGFloat(btn.buttonTag) == bubbleSize)
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let bgRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 10, cornerHeight: 10, transform: nil)
        context.addPath(bgPath)
        context.setFillColor(NSColor(white: 0.12, alpha: 0.92).cgColor)
        context.fillPath()

        context.addPath(bgPath)
        context.setStrokeColor(NSColor(white: 0.3, alpha: 0.5).cgColor)
        context.setLineWidth(0.5)
        context.strokePath()
    }

    // MARK: - Mouse Handling (prevent pass-through)

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
}

// MARK: - DragHandleView

@MainActor private final class DragHandleView: NSView {

    var onDrag: ((CGPoint) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let dotSize: CGFloat = 3
        let hSpacing: CGFloat = 5
        let vSpacing: CGFloat = 5
        let cols = 2
        let rows = 3

        let totalW = CGFloat(cols) * dotSize + CGFloat(cols - 1) * (hSpacing - dotSize)
        let totalH = CGFloat(rows) * dotSize + CGFloat(rows - 1) * (vSpacing - dotSize)
        let startX = (bounds.width - totalW) / 2
        let startY = (bounds.height - totalH) / 2

        context.setFillColor(NSColor(white: 0.6, alpha: 0.8).cgColor)

        for row in 0..<rows {
            for col in 0..<cols {
                let x = startX + CGFloat(col) * hSpacing
                let y = startY + CGFloat(row) * vSpacing
                let dotRect = CGRect(x: x, y: y, width: dotSize, height: dotSize)
                context.fillEllipse(in: dotRect)
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        onDrag?(CGPoint(x: event.deltaX, y: -event.deltaY))
    }

    override func mouseDown(with event: NSEvent) {}

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}

// MARK: - AnnotationColorSwatchButton

@MainActor private final class AnnotationColorSwatchButton: NSView {

    let swatchColor: NSColor
    let shortcut: ColorShortcut
    var isActive: Bool = false { didSet { needsDisplay = true } }
    var onTap: ((ColorShortcut) -> Void)?

    init(frame frameRect: NSRect, swatchColor: NSColor, shortcut: ColorShortcut) {
        self.swatchColor = swatchColor
        self.shortcut = shortcut
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let inset: CGFloat = isActive ? 2 : 1
        let circleRect = bounds.insetBy(dx: inset, dy: inset)
        context.setFillColor(swatchColor.cgColor)
        context.fillEllipse(in: circleRect)

        if isActive {
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(2)
            context.strokeEllipse(in: bounds.insetBy(dx: 1, dy: 1))
        }
    }

    override func mouseDown(with event: NSEvent) {
        onTap?(shortcut)
    }
}

// MARK: - AnnotationToolIconButton

@MainActor private final class AnnotationToolIconButton: NSView {

    let tool: ToolType
    private let symbolName: String
    var isActive: Bool = false { didSet { needsDisplay = true } }
    var onTap: ((ToolType) -> Void)?

    init(frame frameRect: NSRect, tool: ToolType, symbolName: String) {
        self.tool = tool
        self.symbolName = symbolName
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        if isActive {
            let highlightRect = bounds.insetBy(dx: 1, dy: 1)
            let highlightPath = CGPath(roundedRect: highlightRect, cornerWidth: 5, cornerHeight: 5, transform: nil)
            context.addPath(highlightPath)
            context.setFillColor(NSColor(white: 0.35, alpha: 0.8).cgColor)
            context.fillPath()
        }

        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        if let baseImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            let tintColor = NSColor.white.withAlphaComponent(isActive ? 1.0 : 0.7)
            let tintedImage = NSImage(size: baseImage.size, flipped: false) { rect in
                baseImage.draw(in: rect)
                tintColor.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            let imageSize = tintedImage.size
            let imageRect = CGRect(
                x: (bounds.width - imageSize.width) / 2,
                y: (bounds.height - imageSize.height) / 2,
                width: imageSize.width,
                height: imageSize.height
            )
            tintedImage.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
    }

    override func mouseDown(with event: NSEvent) {
        onTap?(tool)
    }
}

// MARK: - SmallColorSwatchButton

@MainActor private final class SmallColorSwatchButton: NSView {

    let swatchColor: NSColor
    let colorName: String
    var isActive: Bool = false { didSet { needsDisplay = true } }
    var onTap: ((NSColor) -> Void)?

    init(frame frameRect: NSRect, swatchColor: NSColor, colorName: String) {
        self.swatchColor = swatchColor
        self.colorName = colorName
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let inset: CGFloat = isActive ? 2 : 1
        let circleRect = bounds.insetBy(dx: inset, dy: inset)
        context.setFillColor(swatchColor.cgColor)
        context.fillEllipse(in: circleRect)

        if isActive {
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(1.5)
            context.strokeEllipse(in: bounds.insetBy(dx: 0.5, dy: 0.5))
        }
    }

    override func mouseDown(with event: NSEvent) {
        onTap?(swatchColor)
    }
}

// MARK: - LabelButton

@MainActor private final class LabelButton: NSView {

    let label: String
    let buttonTag: Int
    var isActive: Bool = false { didSet { needsDisplay = true } }
    var onTap: ((Int) -> Void)?

    init(frame frameRect: NSRect, label: String, tag: Int) {
        self.label = label
        self.buttonTag = tag
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Background
        if isActive {
            let bgRect = bounds.insetBy(dx: 1, dy: 1)
            let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
            context.addPath(bgPath)
            context.setFillColor(NSColor(white: 0.4, alpha: 0.9).cgColor)
            context.fillPath()
        }

        // Text
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(isActive ? 1.0 : 0.7)
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        let strSize = str.size()
        let strRect = CGRect(
            x: (bounds.width - strSize.width) / 2,
            y: (bounds.height - strSize.height) / 2,
            width: strSize.width,
            height: strSize.height
        )
        str.draw(in: strRect)
    }

    override func mouseDown(with event: NSEvent) {
        onTap?(buttonTag)
    }
}

// MARK: - ShapeIconButton

@MainActor private final class ShapeIconButton: NSView {

    let shape: HighlightShape
    private let symbolName: String
    var isActive: Bool = false { didSet { needsDisplay = true } }
    var onTap: ((HighlightShape) -> Void)?

    init(frame frameRect: NSRect, shape: HighlightShape, symbolName: String) {
        self.shape = shape
        self.symbolName = symbolName
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        if isActive {
            let bgRect = bounds.insetBy(dx: 1, dy: 1)
            let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
            context.addPath(bgPath)
            context.setFillColor(NSColor(white: 0.4, alpha: 0.9).cgColor)
            context.fillPath()
        }

        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        if let baseImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            let tintColor = NSColor.white.withAlphaComponent(isActive ? 1.0 : 0.7)
            let tintedImage = NSImage(size: baseImage.size, flipped: false) { rect in
                baseImage.draw(in: rect)
                tintColor.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            let imageSize = tintedImage.size
            let imageRect = CGRect(
                x: (bounds.width - imageSize.width) / 2,
                y: (bounds.height - imageSize.height) / 2,
                width: imageSize.width,
                height: imageSize.height
            )
            tintedImage.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
    }

    override func mouseDown(with event: NSEvent) {
        onTap?(shape)
    }
}


// MARK: - IconButton

/// A button that renders an SF Symbol icon with an active highlight.
/// Used for spotlight size/dim controls with tooltips.
@MainActor private final class IconButton: NSView {

    let buttonTag: Int
    private let symbolName: String
    private let pointSize: CGFloat
    var isActive: Bool = false { didSet { needsDisplay = true } }
    var onTap: ((Int) -> Void)?

    init(frame frameRect: NSRect, symbolName: String, pointSize: CGFloat, tag: Int, tooltip: String) {
        self.symbolName = symbolName
        self.pointSize = pointSize
        self.buttonTag = tag
        super.init(frame: frameRect)
        wantsLayer = true
        self.toolTip = tooltip
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        if isActive {
            let bgRect = bounds.insetBy(dx: 1, dy: 1)
            let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
            context.addPath(bgPath)
            context.setFillColor(NSColor(white: 0.4, alpha: 0.9).cgColor)
            context.fillPath()
        }

        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        if let baseImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            let tintColor = NSColor.white.withAlphaComponent(isActive ? 1.0 : 0.7)
            let tintedImage = NSImage(size: baseImage.size, flipped: false) { rect in
                baseImage.draw(in: rect)
                tintColor.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            let imageSize = tintedImage.size
            let imageRect = CGRect(
                x: (bounds.width - imageSize.width) / 2,
                y: (bounds.height - imageSize.height) / 2,
                width: imageSize.width,
                height: imageSize.height
            )
            tintedImage.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
    }

    override func mouseDown(with event: NSEvent) {
        onTap?(buttonTag)
    }
}

// MARK: - SeparatorView

@MainActor private final class SeparatorView: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(NSColor(white: 0.5, alpha: 0.5).cgColor)
        context.fill(bounds)
    }
}

// MARK: - DismissButtonView

@MainActor private final class DismissButtonView: NSView {

    var onTap: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard NSGraphicsContext.current?.cgContext != nil else { return }

        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        if let baseImage = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Dismiss toolbar")?.withSymbolConfiguration(config) {
            let tintColor = NSColor.white.withAlphaComponent(0.7)
            let tintedImage = NSImage(size: baseImage.size, flipped: false) { rect in
                baseImage.draw(in: rect)
                tintColor.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            let imageSize = tintedImage.size
            let imageRect = CGRect(
                x: (bounds.width - imageSize.width) / 2,
                y: (bounds.height - imageSize.height) / 2,
                width: imageSize.width,
                height: imageSize.height
            )
            tintedImage.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
    }

    override func mouseDown(with event: NSEvent) {
        onTap?()
    }
}

// MARK: - NSColor Equivalence Helper

private extension NSColor {
    func isEquivalent(to other: NSColor) -> Bool {
        guard let c1 = self.usingColorSpace(.deviceRGB),
              let c2 = other.usingColorSpace(.deviceRGB) else {
            return false
        }
        let tolerance: CGFloat = 0.01
        return abs(c1.redComponent - c2.redComponent) < tolerance
            && abs(c1.greenComponent - c2.greenComponent) < tolerance
            && abs(c1.blueComponent - c2.blueComponent) < tolerance
            && abs(c1.alphaComponent - c2.alphaComponent) < tolerance
    }
}
