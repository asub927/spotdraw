// IconButton.swift
// A button that renders an SF Symbol icon with an active highlight.
// Used for spotlight size/dim controls with tooltips.

import Cocoa

@MainActor final class IconButton: NSView {

    let buttonTag: Int
    private let symbolName: String
    private let pointSize: CGFloat
    var isActive: Bool = false { didSet { needsDisplay = true } }
    var onTap: ((Int) -> Void)?

    init(frame frameRect: NSRect, symbolName: String, pointSize: CGFloat, tag: Int, tooltip: String) {
        self.symbolName = symbolName
        self.pointSize = pointSize
        self.buttonTag = tag
        super.init(frame: frameRect)
        wantsLayer = true
        self.toolTip = tooltip
        setAccessibilityRole(.button)
        setAccessibilityLabel(tooltip)
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

        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
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
        onTap?(buttonTag)
    }
}
