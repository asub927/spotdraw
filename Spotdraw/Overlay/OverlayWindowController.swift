import Cocoa

// MARK: - OverlayWindowController

class OverlayWindowController {

    // MARK: - Properties

    private var overlayWindows: [NSWindow] = []
    private(set) var isActive = false

    // MARK: - Init

    init() {
        // Windows will be created on first activation
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
            window.orderFrontRegardless()
        }
        isActive = true
    }

    func deactivate() {
        overlayWindows.forEach { window in
            window.ignoresMouseEvents = true
        }
        isActive = false
    }

    func clearAll() {
        overlayWindows.forEach { window in
            if let view = window.contentView as? OverlayView {
                view.clearAll()
            }
        }
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

        let overlayView = OverlayView(frame: screen.frame)
        window.contentView = overlayView

        window.orderFrontRegardless()

        return window
    }
}
