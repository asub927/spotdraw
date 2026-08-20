// SpotlightWindow.swift
// Full-screen dimming overlay with a clear circular cutout (spotlight) that follows
// the cursor. The SpotlightView fills the screen with a semi-transparent black layer
// and uses CGContext clear blend mode to punch through a spotlight ellipse at the
// current mouse position. Managed by CursorManager.

import Cocoa

// MARK: - SpotlightWindow

@MainActor internal final class SpotlightWindow {

    // MARK: - Properties

    private var window: NSWindow?
    private var spotlightView: SpotlightView?
    private let settings = SettingsManager.shared

    // MARK: - Init

    init() {
        setupWindow()
    }

    // MARK: - Setup

    private func setupWindow() {
        guard let screen = NSScreen.main else { return }

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

        let view = SpotlightView(frame: screen.frame)
        view.spotlightSize = settings.spotlightSize
        view.dimIntensity = settings.spotlightDimIntensity
        window.contentView = view

        self.window = window
        self.spotlightView = view
    }

    // MARK: - Public API

    func show() {
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    /// Refreshes the spotlight view's size and dim intensity from current settings.
    func updateAppearance() {
        spotlightView?.spotlightSize = settings.spotlightSize
        spotlightView?.dimIntensity = settings.spotlightDimIntensity
        spotlightView?.needsDisplay = true
    }

    func updatePosition(to point: NSPoint) {
        guard let spotlightView, let window else { return }
        // Convert screen coordinates to view coordinates
        let viewPoint = NSPoint(
            x: point.x - window.frame.origin.x,
            y: point.y - window.frame.origin.y
        )
        spotlightView.cursorPosition = viewPoint
        spotlightView.needsDisplay = true
    }
}

// MARK: - SpotlightView

@MainActor internal final class SpotlightView: NSView {

    // MARK: - Properties

    var cursorPosition: NSPoint = .zero
    var spotlightSize: CGFloat = 150.0
    var dimIntensity: CGFloat = 0.7

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Fill entire view with dim color
        context.setFillColor(NSColor.black.withAlphaComponent(dimIntensity).cgColor)
        context.fill(bounds)

        // Cut out the spotlight area using clear blend mode
        context.setBlendMode(.clear)
        let spotlightRect = CGRect(
            x: cursorPosition.x - spotlightSize / 2,
            y: cursorPosition.y - spotlightSize / 2,
            width: spotlightSize,
            height: spotlightSize
        )
        let spotlightPath = CGPath(ellipseIn: spotlightRect, transform: nil)
        context.addPath(spotlightPath)
        context.fillPath()

        // Reset blend mode
        context.setBlendMode(.normal)
    }
}
