// AnnotationColorSwatchButton.swift
// A circular color swatch for the annotation color row, keyed to a ColorShortcut.

import Cocoa
import SpotdrawCore

@MainActor final class AnnotationColorSwatchButton: NSView {

    let swatchColor: NSColor
    let shortcut: ColorShortcut
    var isActive: Bool = false { didSet { needsDisplay = true } }
    var onTap: ((ColorShortcut) -> Void)?

    private let tooltipText: String?

    init(frame frameRect: NSRect, swatchColor: NSColor, shortcut: ColorShortcut, tooltip: String? = nil) {
        self.swatchColor = swatchColor
        self.shortcut = shortcut
        self.tooltipText = tooltip
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityRole(.button)
        setAccessibilityLabel(tooltip ?? "Color swatch")
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

        let inset: CGFloat = isActive ? 2 : 1
        let circleRect = bounds.insetBy(dx: inset, dy: inset)
        context.setFillColor(swatchColor.cgColor)
        context.fillEllipse(in: circleRect)

        if isActive {
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(2)
            context.strokeEllipse(in: bounds.insetBy(dx: 1, dy: 1))
        }
    }

    override func mouseDown(with event: NSEvent) {
        onTap?(shortcut)
    }
}
