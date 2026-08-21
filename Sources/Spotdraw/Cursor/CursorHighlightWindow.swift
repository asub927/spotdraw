// CursorHighlightWindow.swift
// Floating borderless window that renders a colored translucent circle centered on
// the cursor. Provides a ripple animation on left/right mouse clicks to give visual
// feedback during presentations. Position is updated externally by CursorManager.

import Cocoa
import SpotdrawCore

// MARK: - CursorHighlightWindow

@MainActor internal final class CursorHighlightWindow {

    // MARK: - Properties

    private var window: NSWindow?
    private var highlightLayer: CAShapeLayer?
    private let settings = SettingsManager.shared

    // MARK: - Init

    init() {
        setupWindow()
    }

    // MARK: - Setup

    /// Returns the padding needed to prevent stroke clipping when glow is disabled.
    /// For ring shape, the stroke extends outward by half the lineWidth.
    /// For other stroked shapes, accounts for the 2pt border stroke.
    private func strokePaddingForCurrentShape() -> CGFloat {
        switch settings.highlightShape {
        case .ring:
            // lineWidth = max(highlightSize * 0.15, 4), stroke extends half outward
            let lineWidth = max(settings.highlightSize * 0.15, 4)
            return ceil(lineWidth / 2) + 1
        case .crosshair:
            return 2 // no stroke, minimal padding
        default:
            return 3 // 2pt stroke border + 1pt safety
        }
    }

    private func makeHighlightPath(in rect: CGRect) -> CGPath {
        switch settings.highlightShape {
        case .circle:
            return CGPath(ellipseIn: rect, transform: nil)
        case .ring:
            return CGPath(ellipseIn: rect, transform: nil)
        case .square:
            return CGPath(roundedRect: rect, cornerWidth: rect.width * 0.15, cornerHeight: rect.height * 0.15, transform: nil)
        case .crosshair:
            let path = CGMutablePath()
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let armLength = rect.width / 2
            let armWidth: CGFloat = rect.width * 0.12
            // Horizontal bar
            path.addRoundedRect(in: CGRect(
                x: center.x - armLength,
                y: center.y - armWidth / 2,
                width: armLength * 2,
                height: armWidth
            ), cornerWidth: armWidth / 2, cornerHeight: armWidth / 2)
            // Vertical bar
            path.addRoundedRect(in: CGRect(
                x: center.x - armWidth / 2,
                y: center.y - armLength,
                width: armWidth,
                height: armLength * 2
            ), cornerWidth: armWidth / 2, cornerHeight: armWidth / 2)
            return path
        }
    }

    private func applyShapeStyle(to layer: CAShapeLayer) {
        switch settings.highlightShape {
        case .ring:
            layer.fillColor = NSColor.clear.cgColor
            layer.strokeColor = settings.highlightColor.withAlphaComponent(settings.highlightOpacity).cgColor
            layer.lineWidth = max(settings.highlightSize * 0.15, 4)
        case .crosshair:
            layer.fillColor = settings.highlightColor.withAlphaComponent(settings.highlightOpacity).cgColor
            layer.strokeColor = NSColor.clear.cgColor
            layer.lineWidth = 0
        default:
            layer.fillColor = settings.highlightColor.withAlphaComponent(settings.highlightOpacity).cgColor
            layer.strokeColor = settings.highlightColor.cgColor
            layer.lineWidth = 2.0
        }
    }

    private func setupWindow() {
        guard let screen = NSScreen.main else { return }

        let strokePadding = strokePaddingForCurrentShape()
        let glowExtra: CGFloat = settings.glowEnabled ? settings.glowRadius : strokePadding
        let totalSize = (settings.highlightSize + glowExtra) * 2
        let highlightDiameter = settings.highlightSize * 2

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: totalSize, height: totalSize),
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

        let view = NSView(frame: NSRect(x: 0, y: 0, width: totalSize, height: totalSize))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        let layer = CAShapeLayer()
        let offset = (totalSize - highlightDiameter) / 2
        let circleRect = CGRect(x: offset, y: offset, width: highlightDiameter, height: highlightDiameter)
        layer.path = makeHighlightPath(in: circleRect)
        applyShapeStyle(to: layer)

        // Glow via shadow
        if settings.glowEnabled {
            layer.shadowColor = settings.highlightColor.cgColor
            layer.shadowRadius = settings.glowRadius
            layer.shadowOpacity = 0.8
            layer.shadowOffset = .zero
        } else {
            layer.shadowOpacity = 0
        }

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

    /// Refreshes the highlight appearance from current SettingsManager values.
    /// Call after any settings change (color, size, glow) to update immediately.
    func updateAppearance() {
        guard let window, let highlightLayer, let contentView = window.contentView else { return }

        let strokePadding = strokePaddingForCurrentShape()
        let glowExtra: CGFloat = settings.glowEnabled ? settings.glowRadius : strokePadding
        let totalSize = (settings.highlightSize + glowExtra) * 2
        let highlightDiameter = settings.highlightSize * 2

        // Resize window centered on current position
        let currentCenter = NSPoint(x: window.frame.midX, y: window.frame.midY)
        let newFrame = NSRect(
            x: currentCenter.x - totalSize / 2,
            y: currentCenter.y - totalSize / 2,
            width: totalSize,
            height: totalSize
        )
        window.setFrame(newFrame, display: false)
        contentView.frame = NSRect(x: 0, y: 0, width: totalSize, height: totalSize)

        // Update highlight circle path (centered in window)
        let offset = (totalSize - highlightDiameter) / 2
        let circleRect = CGRect(x: offset, y: offset, width: highlightDiameter, height: highlightDiameter)
        highlightLayer.path = makeHighlightPath(in: circleRect)

        // Update colors based on shape
        applyShapeStyle(to: highlightLayer)

        // Update glow
        if settings.glowEnabled {
            highlightLayer.shadowColor = settings.highlightColor.cgColor
            highlightLayer.shadowRadius = settings.glowRadius
            highlightLayer.shadowOpacity = 0.8
            highlightLayer.shadowOffset = .zero
        } else {
            highlightLayer.shadowOpacity = 0
        }
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
