// OverlayWindowController.swift
// Manages full-screen transparent overlay windows for annotation across all screens.
// Creates one borderless NSWindow per display, handles screen-change notifications,
// coordinates drawing activation/deactivation, and exposes tool/color/line-width
// setters that propagate to the shared DrawingState.

import Cocoa

// MARK: - OverlayWindowController

internal final class OverlayWindowController {

    // MARK: - Properties

    private var overlayWindows: [NSWindow] = []
    private(set) var isActive = false
    private var drawingState = DrawingState()
    private var screenObserver: Any?

    /// Callback invoked when the user requests deactivation from within the overlay (Ctrl+D or Escape).
    /// Set by AppDelegate to wire view-level deactivation back to the global toggle action.
    var onDeactivate: (() -> Void)? {
        didSet {
            // Propagate to any existing overlay views
            overlayWindows.forEach { window in
                if let view = window.contentView as? OverlayView {
                    view.onDeactivate = onDeactivate
                }
            }
        }
    }

    // MARK: - Init

    init() {
        observeScreenChanges()
    }

    // MARK: - Public API

    /// Toggles the annotation overlay on or off.
    func toggle() {
        if isActive {
            deactivate()
        } else {
            activate()
        }
    }

    /// Creates overlay windows on all screens, makes them key, and enables mouse interaction.
    func activate() {
        guard AccessibilityManager.checkPermission() else {
            showAccessibilityPermissionAlert()
            return
        }

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

    /// Hides overlay windows and restores the default cursor.
    func deactivate() {
        overlayWindows.forEach { window in
            window.ignoresMouseEvents = true
            window.orderBack(nil)
        }
        isActive = false
        NSCursor.arrow.set()
    }

    /// Removes all drawn items and refreshes overlay views.
    func clearAll() {
        drawingState.clearAll()
        overlayWindows.forEach { window in
            if let view = window.contentView as? OverlayView {
                view.needsDisplay = true
            }
        }
    }

    // MARK: - Drawing State Access

    /// Sets the active drawing tool.
    func setTool(_ tool: ToolType) {
        drawingState.activeTool = tool
    }

    /// Sets the active stroke color.
    func setColor(_ color: NSColor) {
        drawingState.activeColor = color
    }

    /// Sets the active stroke width in points.
    func setLineWidth(_ width: CGFloat) {
        drawingState.activeLineWidth = width
    }

    /// Cycles the board background mode: none → white → black → none.
    func toggleBoard() {
        drawingState.boardMode = drawingState.boardMode.next
        refreshAllViews()
    }

    /// Toggles automatic fade-out of drawn annotations.
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

        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true

        let overlayView = OverlayView(frame: screen.frame)
        overlayView.drawingState = drawingState
        overlayView.onDeactivate = onDeactivate
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

    // MARK: - Permission Alert

    private func showAccessibilityPermissionAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "SpotDraw requires Accessibility permission to register global shortcuts. Please grant permission in System Settings > Privacy & Security > Accessibility."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    // MARK: - Cleanup

    deinit {
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        overlayWindows.forEach { $0.close() }
        overlayWindows.removeAll()
    }
}
