// CursorManager.swift
// Coordinates cursor highlight, spotlight, and zoom features with mouse tracking.
// Manages the lifecycle of each feature's window and installs a shared global mouse
// event monitor that dispatches position updates and click effects to active windows.

import Cocoa

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

    /// Toggles the magnification zoom window on or off.
    func toggleZoom() {
        if isZoomActive {
            deactivateZoom()
        } else {
            activateZoom()
        }
    }

    private func activateZoom() {
        if zoomWindow == nil {
            zoomWindow = ZoomWindow()
        }
        zoomWindow?.show()
        isZoomActive = true
        ensureMouseMonitoring()
    }

    private func deactivateZoom() {
        zoomWindow?.hide()
        isZoomActive = false
        updateMouseMonitoring()
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
