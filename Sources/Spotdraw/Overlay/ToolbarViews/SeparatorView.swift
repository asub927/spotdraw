// SeparatorView.swift
// A thin vertical divider between toolbar sections.

import Cocoa

@MainActor final class SeparatorView: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(NSColor(white: 0.5, alpha: 0.5).cgColor)
        context.fill(bounds)
    }
}
