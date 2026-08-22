// ToolbarPanelController.swift
// Unified dynamic floating toolbar panel that shows sections only for currently
// active features: annotation, cursor highlight, spotlight, and zoom.
// The panel grows/shrinks horizontally as sections are added or removed.
//
// The reusable button/swatch/handle views, the TooltipWindow, and FeatureState
// live in their own files (see Overlay/ToolbarViews/ and Overlay/FeatureState.swift).

import Cocoa
import SpotdrawCore

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

    /// Toggles the panel visibility. If dismissed, shows it again; if visible, dismisses it.
    func toggleVisibility() {
        if panelDismissed || panel == nil || !panel!.isVisible {
            panelDismissed = false
            if panel != nil {
                panel?.orderFrontRegardless()
                startRefreshTimer()
            }
        } else {
            dismiss()
        }
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
        panelWindow.acceptsMouseMovedEvents = true
        panelWindow.isFloatingPanel = true
        panelWindow.sharingType = .none  // Invisible to screen capture/recording
        panelWindow.contentView = content

        self.panel = panelWindow
    }

    private func initialFrame(width: CGFloat) -> NSRect {
        let settings = SettingsManager.shared
        if settings.hasToolbarPanelPosition {
            let x = settings.toolbarPanelX
            let y = settings.toolbarPanelY
            return NSRect(x: x, y: y, width: width, height: Layout.panelHeight)
        }
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

        // Persist position (Requirement 5)
        let settings = SettingsManager.shared
        settings.toolbarPanelX = newOrigin.x
        settings.toolbarPanelY = newOrigin.y
    }

    /// Saves the current panel position to settings. Called by AppDelegate on terminate.
    func savePosition() {
        guard let panel = panel else { return }
        let settings = SettingsManager.shared
        settings.toolbarPanelX = panel.frame.origin.x
        settings.toolbarPanelY = panel.frame.origin.y
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
        ToolbarLayout(features: features).totalWidth
    }

    // MARK: - Init

    init(features: FeatureState, drawingState: DrawingState?, cursorManager: CursorManager?) {
        self.features = features
        self.drawingState = drawingState
        self.cursorManager = cursorManager
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: panelHeight))
        wantsLayer = true
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("Annotation toolbar")
        setupSubviews()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
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
        dragHandle.toolTip = "Drag to reposition"
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
        dismissButton.toolTip = "Hide toolbar"
        addSubview(dismissButton)
    }

    // MARK: - Annotation Section Builder

    private func buildAnnotationSection(at startX: CGFloat) -> CGFloat {
        var x = startX

        // 5 color swatches
        let colors: [(ColorShortcut, NSColor, String)] = [
            (.red, .systemRed, "Red (1)"),
            (.blue, .systemBlue, "Blue (2)"),
            (.green, .systemGreen, "Green (3)"),
            (.yellow, .systemYellow, "Yellow (4)"),
            (.white, .white, "White (5)")
        ]
        for (shortcut, color, tip) in colors {
            let btn = AnnotationColorSwatchButton(
                frame: NSRect(x: x, y: (panelHeight - 30) / 2, width: 30, height: 30),
                swatchColor: color,
                shortcut: shortcut,
                tooltip: tip
            )
            btn.onTap = { [weak self] sc in self?.annotationColorTapped(sc) }
            addSubview(btn)
            annotationColorButtons.append(btn)
            x += 30 + itemSpacing
        }
        x -= itemSpacing
        x += itemSpacing

        // Separator between colors and tools
        let sep = SeparatorView(frame: NSRect(x: x, y: (panelHeight - 36) / 2, width: 1, height: 36))
        addSubview(sep)
        x += 1 + itemSpacing

        // 6 tool icons
        let tools: [(ToolType, String, String)] = [
            (.pen, "pencil.tip", "Pen (P)"),
            (.arrow, "arrow.up.right", "Arrow (A)"),
            (.rectangle, "rectangle", "Rectangle (R)"),
            (.circle, "circle", "Circle (O)"),
            (.text, "textformat", "Text (T)"),
            (.eraser, "eraser", "Eraser (E)")
        ]
        for (tool, symbolName, tip) in tools {
            let btn = AnnotationToolIconButton(
                frame: NSRect(x: x, y: (panelHeight - 36) / 2, width: 36, height: 36),
                tool: tool,
                symbolName: symbolName,
                tooltip: tip
            )
            btn.onTap = { [weak self] t in self?.annotationToolTapped(t) }
            addSubview(btn)
            annotationToolButtons.append(btn)
            x += 36 + itemSpacing
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
        let colors: [(String, NSColor, String)] = [
            ("yellow", .systemYellow, "Yellow"),
            ("red", .systemRed, "Red"),
            ("blue", .systemBlue, "Blue"),
            ("green", .systemGreen, "Green"),
            ("white", .white, "White")
        ]
        for (name, color, tip) in colors {
            let btn = SmallColorSwatchButton(
                frame: NSRect(x: x, y: (panelHeight - 24) / 2, width: 24, height: 24),
                swatchColor: color,
                colorName: name,
                tooltip: tip
            )
            btn.onTap = { [weak self] c in self?.highlightColorTapped(c) }
            addSubview(btn)
            highlightColorButtons.append(btn)
            x += 24 + 6
        }
        x -= 6
        x += itemSpacing

        // Size buttons S/M/L/XL (30/50/100/150)
        let sizes: [(String, CGFloat, String)] = [("S", 30, "Small (30pt)"), ("M", 50, "Medium (50pt)"), ("L", 100, "Large (100pt)"), ("XL", 150, "Extra Large (150pt)")]
        for (label, size, tip) in sizes {
            let btn = LabelButton(
                frame: NSRect(x: x, y: (panelHeight - 30) / 2, width: 30, height: 30),
                label: label,
                tag: Int(size),
                tooltip: tip
            )
            btn.onTap = { [weak self] tag in self?.highlightSizeTapped(CGFloat(tag)) }
            addSubview(btn)
            highlightSizeButtons.append(btn)
            x += 20 + 4
        }
        x -= 4
        x += itemSpacing

        // Shape buttons
        let shapes: [(HighlightShape, String, String)] = [
            (.circle, "circle.fill", "Circle"),
            (.ring, "circle", "Ring"),
            (.square, "square", "Square"),
            (.crosshair, "plus", "Crosshair")
        ]
        for (shape, symbolName, tip) in shapes {
            let btn = ShapeIconButton(
                frame: NSRect(x: x, y: (panelHeight - 30) / 2, width: 30, height: 30),
                shape: shape,
                symbolName: symbolName,
                tooltip: tip
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
            tag: 0,
            tooltip: "Toggle glow effect"
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
            tag: -1,
            tooltip: "Zoom out (⌃-)"
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
            tag: 1,
            tooltip: "Zoom in (⌃=)"
        )
        plusBtn.onTap = { [weak self] _ in self?.zoomInTapped() }
        addSubview(plusBtn)
        zoomPlusButton = plusBtn
        x += 30 + itemSpacing

        // Bubble size buttons S/M/L (100/200/300)
        let sizes: [(String, CGFloat, String)] = [("S", 100, "Small bubble (100pt)"), ("M", 200, "Medium bubble (200pt)"), ("L", 300, "Large bubble (300pt)")]
        for (labelStr, size, tip) in sizes {
            let btn = LabelButton(
                frame: NSRect(x: x, y: (panelHeight - 30) / 2, width: 30, height: 30),
                label: labelStr,
                tag: Int(size),
                tooltip: tip
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
