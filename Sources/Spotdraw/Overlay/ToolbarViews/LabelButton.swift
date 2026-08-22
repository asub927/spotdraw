// LabelButton.swift
// A text-label button (e.g. size presets S/M/L, zoom +/−) with an active state.

import Cocoa

@MainActor final class LabelButton: NSView {

    let label: String
    let buttonTag: Int
    var isActive: Bool = false { didSet { needsDisplay = true } }
    var onTap: ((Int) -> Void)?

    private let tooltipText: String?

    init(frame frameRect: NSRect, label: String, tag: Int, tooltip: String? = nil) {
        self.label = label
        self.buttonTag = tag
        self.tooltipText = tooltip
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityRole(.button)
        setAccessibilityLabel(tooltip ?? label)
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

        // Background
        if isActive {
            let bgRect = bounds.insetBy(dx: 1, dy: 1)
            let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
            context.addPath(bgPath)
            context.setFillColor(NSColor(white: 0.4, alpha: 0.9).cgColor)
            context.fillPath()
        }

        // Text
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(isActive ? 1.0 : 0.7)
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        let strSize = str.size()
        let strRect = CGRect(
            x: (bounds.width - strSize.width) / 2,
            y: (bounds.height - strSize.height) / 2,
            width: strSize.width,
            height: strSize.height
        )
        str.draw(in: strRect)
    }

    override func mouseDown(with event: NSEvent) {
        onTap?(buttonTag)
    }
}
