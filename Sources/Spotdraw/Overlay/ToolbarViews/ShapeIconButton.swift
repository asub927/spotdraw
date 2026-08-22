// ShapeIconButton.swift
// A button for selecting a cursor-highlight shape, rendered as an SF Symbol.

import Cocoa
import SpotdrawCore

@MainActor final class ShapeIconButton: NSView {

    let shape: HighlightShape
    private let symbolName: String
    var isActive: Bool = false { didSet { needsDisplay = true } }
    var onTap: ((HighlightShape) -> Void)?

    private let tooltipText: String?

    init(frame frameRect: NSRect, shape: HighlightShape, symbolName: String, tooltip: String? = nil) {
        self.shape = shape
        self.symbolName = symbolName
        self.tooltipText = tooltip
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityRole(.button)
        setAccessibilityLabel(tooltip ?? shape.displayName)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        guard let tip = tooltipText else { return }
        let screenPoint = window?.convertPoint(toScreen: convert(bounds.origin, to: nil)) ?? .zero
        TooltipWindow.shared.show(tip, near: NSPoint(x: screenPoint.x + bounds.width / 2, y: screenPoint.y))
    }

    override func mouseExited(with event: NSEvent) {
        TooltipWindow.shared.hide()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        if isActive {
            let bgRect = bounds.insetBy(dx: 1, dy: 1)
            let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
            context.addPath(bgPath)
            context.setFillColor(NSColor(white: 0.4, alpha: 0.9).cgColor)
            context.fillPath()
        }

        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        if let baseImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            let tintColor = NSColor.white.withAlphaComponent(isActive ? 1.0 : 0.7)
            let tintedImage = NSImage(size: baseImage.size, flipped: false) { rect in
                baseImage.draw(in: rect)
                tintColor.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            let imageSize = tintedImage.size
            let imageRect = CGRect(
                x: (bounds.width - imageSize.width) / 2,
                y: (bounds.height - imageSize.height) / 2,
                width: imageSize.width,
                height: imageSize.height
            )
            tintedImage.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
    }

    override func mouseDown(with event: NSEvent) {
        onTap?(shape)
    }
}
