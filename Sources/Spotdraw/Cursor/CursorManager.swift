// CursorManager.swift
// Coordinates cursor highlight, spotlight, and zoom features with mouse tracking.
// Manages the lifecycle of each feature's window and installs a shared global mouse
// event monitor that dispatches position updates and click effects to active windows.

import Cocoa
import SpotdrawCore

// MARK: - CursorManager

@MainActor internal final class CursorManager {

    // MARK: - Properties

    private typealias EventMonitorToken = Any

    private(set) var isHighlightActive = false
    private(set) var isSpotlightActive = false
    private(set) var isZoomActive = false

    private var highlightWindow: CursorHighlightWindow?
    private var spotlightWindow: SpotlightWindow?
    private var zoomWindow: ZoomWindow?
    private var mouseMonitor: EventMonitorToken?

    private let settings = SettingsManager.shared

    // MARK: - Init

    init() {
        // Monitors will be set up when features are activated
    }

    // MARK: - Cursor Highlight

    /// Tells the active highlight window to refresh its appearance from current settings.
    func updateHighlightAppearance() {
        highlightWindow?.updateAppearance()
    }

    /// Tells the active spotlight window to refresh its appearance from current settings.
    func updateSpotlightAppearance() {
        spotlightWindow?.updateAppearance()
    }

    /// Toggles the cursor highlight circle on or off.
    func toggleHighlight() {
        if isHighlightActive {
            deactivateHighlight()
        } else {
            activateHighlight()
        }
    }

    private func activateHighlight() {
        if highlightWindow == nil {
            highlightWindow = CursorHighlightWindow()
        }
        highlightWindow?.show()
        isHighlightActive = true
        ensureMouseMonitoring()
    }

    private func deactivateHighlight() {
        highlightWindow?.hide()
        isHighlightActive = false
        updateMouseMonitoring()
    }

    // MARK: - Spotlight

    /// Toggles the spotlight dimming effect on or off.
    func toggleSpotlight() {
        if isSpotlightActive {
            deactivateSpotlight()
        } else {
            activateSpotlight()
        }
    }

    private func activateSpotlight() {
        if spotlightWindow == nil {
            spotlightWindow = SpotlightWindow()
        }
        spotlightWindow?.show()
        isSpotlightActive = true
        ensureMouseMonitoring()
    }

    private func deactivateSpotlight() {
        spotlightWindow?.hide()
        isSpotlightActive = false
        updateMouseMonitoring()
    }

    // MARK: - Zoom

    /// Injectable screen-recording permission probe, defaulting to `CGPreflightScreenCaptureAccess`.
    /// Injectable so the denial path is testable without manipulating system TCC state.
    var screenRecordingProbe: () -> Bool = { CGPreflightScreenCaptureAccess() }

    /// Injectable alert presenter for the denial path. Defaults to showing a modal alert.
    /// Override to a no-op in tests to avoid blocking on `runModal()`.
    var screenRecordingDenialHandler: (() -> Void)?

    /// Toggles the magnification zoom window on or off.
    func toggleZoom() {
        if isZoomActive {
            deactivateZoom()
        } else {
            activateZoom()
        }
    }

    /// Increases the zoom level by 0.5 and persists (Requirement 5.4).
    /// Clamped at 4.0 (Requirement 5.6).
    func zoomIn() {
        guard isZoomActive else { return }
        let newLevel = min(settings.zoomLevel + 0.5, 4.0)
        settings.zoomLevel = newLevel
        updateZoomAppearance()
    }

    /// Decreases the zoom level by 0.5 and persists (Requirement 5.5).
    /// Clamped at 2.0 (Requirement 5.7).
    func zoomOut() {
        guard isZoomActive else { return }
        let newLevel = max(settings.zoomLevel - 0.5, 2.0)
        settings.zoomLevel = newLevel
        updateZoomAppearance()
    }

    /// Applies persisted zoom settings to the ZoomWindow (Requirement 5.9).
    func updateZoomAppearance() {
        zoomWindow?.zoomLevel = settings.zoomLevel
        zoomWindow?.bubbleSize = settings.zoomBubbleSize
    }

    private func activateZoom() {
        // Gate on Screen Recording permission (Requirement 4.7)
        guard screenRecordingProbe() else {
            if let handler = screenRecordingDenialHandler {
                handler()
            } else {
                // Request access first — this triggers the system prompt that adds
                // the app to the Screen Recording list (works for signed apps;
                // unsigned debug builds may need manual addition via the + button).
                CGRequestScreenCaptureAccess()
                presentScreenRecordingAlert()
            }
            return
        }

        if zoomWindow == nil {
            zoomWindow = ZoomWindow()
        }
        // Apply persisted settings before showing (Requirement 5.3)
        zoomWindow?.zoomLevel = settings.zoomLevel
        zoomWindow?.bubbleSize = settings.zoomBubbleSize
        zoomWindow?.show()
        isZoomActive = true
        ensureMouseMonitoring()
    }

    private func deactivateZoom() {
        zoomWindow?.hide()
        isZoomActive = false
        updateMouseMonitoring()
    }

    /// Presents an alert offering to open the System Settings Screen Recording pane
    /// when permission is absent (Requirement 4.7).
    private func presentScreenRecordingAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "SpotDraw needs Screen Recording access to capture the magnified area. Please grant access in System Settings."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Stops the capture timer and releases the zoom window (Requirement 4.11).
    func shutdown() {
        if isZoomActive {
            deactivateZoom()
        }
        if isHighlightActive {
            deactivateHighlight()
        }
        if isSpotlightActive {
            deactivateSpotlight()
        }
    }

    // MARK: - Mouse Monitoring

    private func ensureMouseMonitoring() {
        guard mouseMonitor == nil else { return }
        // NSEvent monitor callbacks are dispatched on the main thread.
        // The @MainActor annotation on CursorManager ensures the compiler
        // verifies this isolation at Swift 6 language mode.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]
        ) { [weak self] event in
            self?.routeMouseEvent(event)
        }
    }

    private func updateMouseMonitoring() {
        if !isHighlightActive && !isSpotlightActive && !isZoomActive {
            if let monitor = mouseMonitor {
                NSEvent.removeMonitor(monitor)
                mouseMonitor = nil
            }
        }
    }

    private func routeMouseEvent(_ event: NSEvent) {
        let mouseLocation = NSEvent.mouseLocation

        if isHighlightActive {
            highlightWindow?.updatePosition(to: mouseLocation)

            // Handle click effects
            switch event.type {
            case .leftMouseDown:
                highlightWindow?.showClickEffect(at: mouseLocation, isRightClick: false)
            case .rightMouseDown:
                highlightWindow?.showClickEffect(at: mouseLocation, isRightClick: true)
            default:
                break
            }
        }

        if isSpotlightActive {
            spotlightWindow?.updatePosition(to: mouseLocation)
        }

        if isZoomActive {
            zoomWindow?.updatePosition(to: mouseLocation)
        }
    }

    // MARK: - Cleanup

    deinit {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
