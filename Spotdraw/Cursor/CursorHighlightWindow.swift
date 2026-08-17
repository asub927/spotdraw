// CursorHighlightWindow.swift
// Floating borderless window that renders a colored translucent circle centered on
// the cursor. Provides a ripple animation on left/right mouse clicks to give visual
// feedback during presentations. Position is updated externally by CursorManager.

import Cocoa

// MARK: - CursorHighlightWindow

internal final class CursorHighlightWindow {

    // MARK: - Properties

    private var window: NSWindow?
    private var highlightLayer: CAShapeLayer?
    private let settings = SettingsManager.shared

    // MARK: - Init

    init() {
        setupWindow()
    }

    // MARK: - Setup

    private func setupWindow() {
        guard let screen = NSScreen.main else { return }

        let size = settings.highlightSize * 2
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.level = .screenSaver + 1
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false

        let view = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        let layer = CAShapeLayer()
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        layer.path = CGPath(ellipseIn: rect, transform: nil)
        layer.fillColor = settings.highlightColor.withAlphaComponent(settings.highlightOpacity).cgColor
        layer.strokeColor = settings.highlightColor.cgColor
        layer.lineWidth = 2.0
        view.layer?.addSublayer(layer)

        window.contentView = view
        self.window = window
        self.highlightLayer = layer
    }

    // MARK: - Public API

    func show() {
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    func updatePosition(to point: NSPoint) {
        guard let window else { return }
        let size = window.frame.size
        let origin = NSPoint(
            x: point.x - size.width / 2,
            y: point.y - size.height / 2
        )
        window.setFrameOrigin(origin)
    }

    func showClickEffect(at point: NSPoint, isRightClick: Bool) {
        guard let window, let contentView = window.contentView, let layer = contentView.layer else { return }

        let effectSize = settings.highlightSize * 2.5
        let effectLayer = CAShapeLayer()
        let rect = CGRect(
            x: (window.frame.width - effectSize) / 2,
            y: (window.frame.height - effectSize) / 2,
            width: effectSize,
            height: effectSize
        )
        effectLayer.path = CGPath(ellipseIn: rect, transform: nil)
        effectLayer.fillColor = NSColor.clear.cgColor
        effectLayer.strokeColor = (isRightClick ? NSColor.systemRed : NSColor.systemBlue).cgColor
        effectLayer.lineWidth = 3.0
        effectLayer.opacity = 0

        layer.addSublayer(effectLayer)

        // Ripple animation
        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.fromValue = 0.5
        scaleAnimation.toValue = 1.5

        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = 1.0
        opacityAnimation.toValue = 0.0

        let group = CAAnimationGroup()
        group.animations = [scaleAnimation, opacityAnimation]
        group.duration = 0.4
        group.isRemovedOnCompletion = true

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            effectLayer.removeFromSuperlayer()
        }
        effectLayer.add(group, forKey: "ripple")
        CATransaction.commit()
    }
}
