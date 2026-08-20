// ModeIndicatorView.swift
// Badge view that reports whether the overlay is currently capturing mouse
// input or passing it through to the application beneath. Shown when the
// overlay is active AND (Interactive Mode is enabled OR the overlay is in
// passthrough state). Requirements 8.3, 8.6, 8.7, 9.8.

import Cocoa

// MARK: - ModeIndicatorView

@MainActor internal final class ModeIndicatorView: NSView {

    // MARK: - State

    /// Whether the overlay is currently capturing mouse input.
    var isCapturing: Bool = true {
        didSet { needsDisplay = true }
    }

    // MARK: - Layout Constants

    private let badgeHeight: CGFloat = 24
    private let horizontalPadding: CGFloat = 12
    private let cornerRadius: CGFloat = 12

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

        let text = isCapturing ? "Capturing" : "Passthrough"
        let bgColor: NSColor = isCapturing
            ? NSColor.systemGreen.withAlphaComponent(0.8)
            : NSColor.systemOrange.withAlphaComponent(0.8)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attrString.size()

        let badgeWidth = textSize.width + horizontalPadding * 2
        let badgeRect = CGRect(
            x: (bounds.width - badgeWidth) / 2,
            y: (bounds.height - badgeHeight) / 2,
            width: badgeWidth,
            height: badgeHeight
        )

        // Draw background pill
        let path = CGPath(roundedRect: badgeRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        context.addPath(path)
        context.setFillColor(bgColor.cgColor)
        context.fillPath()

        // Draw text centered in badge
        let textOrigin = CGPoint(
            x: badgeRect.origin.x + horizontalPadding,
            y: badgeRect.origin.y + (badgeHeight - textSize.height) / 2
        )
        attrString.draw(at: textOrigin)
    }

    // MARK: - Sizing

    override var intrinsicContentSize: NSSize {
        NSSize(width: 120, height: badgeHeight + 8)
    }
}
