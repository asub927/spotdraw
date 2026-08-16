import Cocoa

// MARK: - OverlayWindowController

class OverlayWindowController {

    // MARK: - Properties

    private var overlayWindows: [NSWindow] = []
    private(set) var isActive = false
    private var drawingState = DrawingState()
    private var screenObserver: Any?

    // MARK: - Init

    init() {
        observeScreenChanges()
    }

    // MARK: - Public API

    func toggle() {
        if isActive {
            deactivate()
        } else {
            activate()
        }
    }

    func activate() {
        if overlayWindows.isEmpty {
            createOverlayWindows()
        }
        overlayWindows.forEach { window in
            window.ignoresMouseEvents = false
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(window.contentView)
        }
        isActive = true
        NSCursor.crosshair.set()
    }

    func deactivate() {
        overlayWindows.forEach { window in
            window.ignoresMouseEvents = true
            window.orderBack(nil)
        }
        isActive = false
        NSCursor.arrow.set()
    }

    func clearAll() {
        drawingState.clearAll()
        overlayWindows.forEach { window in
            if let view = window.contentView as? OverlayView {
                view.needsDisplay = true
            }
        }
    }

    // MARK: - Drawing State Access

    func setTool(_ tool: ToolType) {
        drawingState.activeTool = tool
    }

    func setColor(_ color: NSColor) {
        drawingState.activeColor = color
    }

    func setLineWidth(_ width: CGFloat) {
        drawingState.activeLineWidth = width
    }

    func toggleBoard() {
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
        refreshAllViews()
    }

    func toggleFadeMode() {
        drawingState.fadeMode.toggle()
    }

    // MARK: - Window Creation

    private func createOverlayWindows() {
        for screen in NSScreen.screens {
            let window = createOverlayWindow(for: screen)
            overlayWindows.append(window)
        }
    }

    private func createOverlayWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true

        let overlayView = OverlayView(frame: screen.frame)
        overlayView.drawingState = drawingState
        window.contentView = overlayView

        window.orderFrontRegardless()

        return window
    }

    // MARK: - Screen Changes

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildWindows()
        }
    }

    private func rebuildWindows() {
        let wasActive = isActive
        overlayWindows.forEach { $0.close() }
        overlayWindows.removeAll()
        if wasActive {
            activate()
        }
    }

    private func refreshAllViews() {
        overlayWindows.forEach { window in
            window.contentView?.needsDisplay = true
        }
    }

    // MARK: - Cleanup

    deinit {
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
