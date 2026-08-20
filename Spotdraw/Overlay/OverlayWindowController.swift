// OverlayWindowController.swift
// Manages full-screen transparent overlay windows for annotation across all screens.
// Creates one borderless NSWindow per display, handles screen-change notifications,
// coordinates drawing activation/deactivation, and exposes tool/color/line-width
// setters that propagate to the shared DrawingState.

import Cocoa

// MARK: - KeyableWindow

/// Custom NSWindow subclass that allows borderless windows to become key.
/// Required because borderless windows return false from canBecomeKey by default,
/// which prevents them from receiving keyboard events.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - OverlayWindowController

@MainActor internal final class OverlayWindowController {

    // MARK: - Properties

    private var overlayWindows: [NSWindow] = []
    private(set) var isActive = false
    private(set) var drawingState = DrawingState()
    private var screenObserver: Any?

    // MARK: - Passthrough State Machine

    /// Whether the overlay is currently in passthrough (not capturing mouse input).
    private(set) var isPassthrough: Bool = false

    /// Whether the configured passthrough modifier is currently held.
    private(set) var modifierHeld: Bool = false

    /// Whether Interactive Mode is enabled. When enabled, the overlay defaults
    /// to passthrough and capturing requires the modifier to be held.
    var interactiveModeEnabled: Bool = false {
        didSet {
            guard isActive else { return }
            applyMouseAcceptance()
        }
    }

    /// Updates the held state of the passthrough modifier and recalculates
    /// mouse acceptance. Called by HotkeyManager's flagsChanged monitor.
    func setPassthroughModifierHeld(_ held: Bool) {
        modifierHeld = held
        guard isActive else { return }
        applyMouseAcceptance()
    }

    /// The single writer of `ignoresMouseEvents` and cursor state across all
    /// overlay windows. Derives everything from activation, mode, and modifier.
    private func applyMouseAcceptance() {
        let capturesMouse = isActive && (interactiveModeEnabled ? modifierHeld : !modifierHeld)

        let wasCapturing = !isPassthrough
        isPassthrough = !capturesMouse

        // If transitioning from capturing → passthrough, drain in-flight interaction first
        if wasCapturing && isPassthrough {
            drainInFlightInteraction()
        }

        overlayWindows.forEach { window in
            window.ignoresMouseEvents = !capturesMouse
        }

        if capturesMouse {
            NSCursor.crosshair.set()
        } else {
            NSCursor.arrow.set()
        }

        // Update mode indicator on all views
        overlayWindows.forEach { window in
            if let view = window.contentView as? OverlayView {
                view.updateModeIndicator(
                    showIndicator: shouldShowModeIndicator,
                    isCapturing: capturesMouse
                )
            }
        }
    }

    /// Whether the mode indicator badge should be visible.
    /// Shown when: overlay active AND (Interactive Mode enabled OR not capturing).
    private var shouldShowModeIndicator: Bool {
        guard isActive else { return false }
        return interactiveModeEnabled || isPassthrough
    }

    /// Drains in-flight drawing gestures and text edits on all overlay views
    /// before entering passthrough state.
    private func drainInFlightInteraction() {
        overlayWindows.forEach { window in
            if let view = window.contentView as? OverlayView {
                view.drainForPassthrough()
            }
        }
    }

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

        // Activate the app so overlay windows can become key and receive keyboard events.
        // Without this, menu bar apps remain in the background and windows don't get focus.
        NSApp.activate(ignoringOtherApps: true)

        overlayWindows.forEach { window in
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(window.contentView)
        }
        isActive = true
        applyMouseAcceptance()
    }

    /// Hides overlay windows and restores the default cursor.
    func deactivate() {
        // Requirement 8.10: deactivation while modifier held → ignore mouse events, remove indicator.
        overlayWindows.forEach { window in
            window.ignoresMouseEvents = true
            window.orderBack(nil)
            if let view = window.contentView as? OverlayView {
                view.updateModeIndicator(showIndicator: false, isCapturing: false)
            }
        }
        isActive = false
        isPassthrough = false
        modifierHeld = false
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

    /// Forces a redraw on all overlay views.
    func refreshViews() {
        overlayWindows.forEach { window in
            window.contentView?.needsDisplay = true
        }
    }

    private func createOverlayWindows() {
        for screen in NSScreen.screens {
            let window = makeOverlayWindow(for: screen)
            overlayWindows.append(window)
        }
    }

    private func makeOverlayWindow(for screen: NSScreen) -> NSWindow {
        let window = KeyableWindow(
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
            createOverlayWindows()
            NSApp.activate(ignoringOtherApps: true)
            overlayWindows.forEach { window in
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(window.contentView)
            }
            // Requirement 8.12: re-apply current passthrough state to new windows.
            applyMouseAcceptance()
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
