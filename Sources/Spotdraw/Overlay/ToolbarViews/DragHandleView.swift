// DragHandleView.swift
// The leading grab-dots handle used to reposition the floating toolbar panel.

import Cocoa

@MainActor final class DragHandleView: NSView {

    var onDrag: ((CGPoint) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityRole(.handle)
        setAccessibilityLabel("Drag to reposition toolbar")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let dotSize: CGFloat = 3
        let hSpacing: CGFloat = 5
        let vSpacing: CGFloat = 5
        let cols = 2
        let rows = 3

        let totalW = CGFloat(cols) * dotSize + CGFloat(cols - 1) * (hSpacing - dotSize)
        let totalH = CGFloat(rows) * dotSize + CGFloat(rows - 1) * (vSpacing - dotSize)
        let startX = (bounds.width - totalW) / 2
        let startY = (bounds.height - totalH) / 2

        context.setFillColor(NSColor(white: 0.6, alpha: 0.8).cgColor)

        for row in 0..<rows {
            for col in 0..<cols {
                let x = startX + CGFloat(col) * hSpacing
                let y = startY + CGFloat(row) * vSpacing
                let dotRect = CGRect(x: x, y: y, width: dotSize, height: dotSize)
                context.fillEllipse(in: dotRect)
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        onDrag?(CGPoint(x: event.deltaX, y: -event.deltaY))
    }

    override func mouseDown(with event: NSEvent) {}

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}
