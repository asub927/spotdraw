import Cocoa

// MARK: - CursorManager

class CursorManager {

    // MARK: - Properties

    private(set) var isHighlightActive = false
    private(set) var isSpotlightActive = false

    private var highlightWindow: CursorHighlightWindow?
    private var spotlightWindow: SpotlightWindow?
    private var mouseMonitor: Any?

    private let settings = SettingsManager.shared

    // MARK: - Init

    init() {
        // Monitors will be set up when features are activated
    }

    // MARK: - Cursor Highlight

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

    // MARK: - Mouse Monitoring

    private func ensureMouseMonitoring() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]
        ) { [weak self] event in
            self?.handleMouseEvent(event)
        }
    }

    private func updateMouseMonitoring() {
        if !isHighlightActive && !isSpotlightActive {
            if let monitor = mouseMonitor {
                NSEvent.removeMonitor(monitor)
                mouseMonitor = nil
            }
        }
    }

    private func handleMouseEvent(_ event: NSEvent) {
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
    }

    // MARK: - Cleanup

    deinit {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
