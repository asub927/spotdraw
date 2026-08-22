// DismissButtonView.swift
// The trailing "hide toolbar" button in the floating panel.

import Cocoa

@MainActor final class DismissButtonView: NSView {

    var onTap: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityRole(.button)
        setAccessibilityLabel("Hide toolbar")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard NSGraphicsContext.current?.cgContext != nil else { return }

        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        if let baseImage = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Dismiss toolbar")?.withSymbolConfiguration(config) {
            let tintColor = NSColor.white.withAlphaComponent(0.7)
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
        onTap?()
    }
}
