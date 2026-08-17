// ZoomWindow.swift
// Floating magnification bubble that captures and displays zoomed screen content.
// Uses a 30 fps timer to grab a CGWindowListCreateImage of the area around the
// cursor, excluding its own window, and renders the zoomed capture inside a
// circular-masked NSImageView with a decorative border ring.

import Cocoa

// MARK: - ZoomWindow

@MainActor internal final class ZoomWindow {

    // MARK: - Properties

    private var window: NSWindow?
    private var imageView: NSImageView?
    private var borderLayer: CAShapeLayer?
    private var captureTimer: Timer?

    var zoomLevel: CGFloat = 2.0 {
        didSet {
            zoomLevel = min(max(zoomLevel, 2.0), 4.0)
        }
    }

    var bubbleSize: CGFloat = 200.0 {
        didSet {
            bubbleSize = min(max(bubbleSize, 100.0), 300.0)
            resizeWindow()
        }
    }

    private let cursorOffset: CGFloat = 30.0

    // MARK: - Init

    init() {
        setupWindow()
    }

    // MARK: - Setup

    private func setupWindow() {
        guard let screen = NSScreen.main else { return }

        let size = bubbleSize
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.level = .screenSaver + 2
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor

        // Image view for magnified content
        let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        imageView.imageScaling = .scaleAxesIndependently
        imageView.wantsLayer = true
        contentView.addSubview(imageView)

        // Circular mask
        let maskLayer = CAShapeLayer()
        let circlePath = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: size, height: size), transform: nil)
        maskLayer.path = circlePath
        imageView.layer?.mask = maskLayer

        // Border ring
        let borderLayer = CAShapeLayer()
        borderLayer.path = circlePath
        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.strokeColor = NSColor.white.withAlphaComponent(0.8).cgColor
        borderLayer.lineWidth = 2.5
        borderLayer.shadowColor = NSColor.black.cgColor
        borderLayer.shadowOffset = CGSize(width: 0, height: -1)
        borderLayer.shadowRadius = 3.0
        borderLayer.shadowOpacity = 0.4
        contentView.layer?.addSublayer(borderLayer)

        window.contentView = contentView
        self.window = window
        self.imageView = imageView
        self.borderLayer = borderLayer
    }

    // MARK: - Private Methods

    private func resizeWindow() {
        guard let window, let imageView, let borderLayer else { return }

        let size = bubbleSize
        window.setContentSize(NSSize(width: size, height: size))

        imageView.frame = NSRect(x: 0, y: 0, width: size, height: size)

        let circlePath = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: size, height: size), transform: nil)
        (imageView.layer?.mask as? CAShapeLayer)?.path = circlePath
        borderLayer.path = circlePath
    }

    // MARK: - Public API

    func show() {
        window?.orderFrontRegardless()
        startCapture()
    }

    func hide() {
        stopCapture()
        window?.orderOut(nil)
    }

    func updatePosition(to point: NSPoint) {
        guard let window else { return }
        let size = window.frame.size
        // Offset to upper-right of cursor so it doesn't overlap
        let origin = NSPoint(
            x: point.x + cursorOffset,
            y: point.y + cursorOffset - size.height / 2
        )
        window.setFrameOrigin(origin)
    }

    // MARK: - Screen Capture

    private func startCapture() {
        stopCapture()
        // Timer scheduled on the main run loop; callback executes on the main thread.
        // MainActor.assumeIsolated is used because Timer's closure is not annotated as
        // @MainActor by the SDK, but we know it runs on the main thread. This satisfies
        // the compiler's isolation check at Swift 6 language mode.
        captureTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.captureScreen()
            }
        }
    }

    private func stopCapture() {
        captureTimer?.invalidate()
        captureTimer = nil
    }

    private func captureScreen() {
        guard let window, window.isVisible else { return }

        let mouseLocation = NSEvent.mouseLocation

        // Coordinate conversion: NSEvent.mouseLocation uses Cocoa coordinates (origin at
        // bottom-left), while CGWindowListCreateImage uses Quartz coordinates (origin at
        // top-left). Convert by: quartzY = screenHeight - cocoaY.
        guard let screen = NSScreen.main else { return }
        let screenHeight = screen.frame.height

        let captureSize = bubbleSize / zoomLevel
        let captureRect = CGRect(
            x: mouseLocation.x - captureSize / 2,
            y: (screenHeight - mouseLocation.y) - captureSize / 2,
            width: captureSize,
            height: captureSize
        )

        // Exclude our own window from the capture
        let windowID = CGWindowID(window.windowNumber)
        guard let cgImage = CGWindowListCreateImage(
            captureRect,
            .optionOnScreenBelowWindow,
            windowID,
            [.bestResolution]
        ) else { return }

        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: bubbleSize, height: bubbleSize))
        imageView?.image = nsImage
    }

    // MARK: - Cleanup

    deinit {
        captureTimer?.invalidate()
        captureTimer = nil
    }
}
