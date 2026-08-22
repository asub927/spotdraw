// TooltipWindow.swift
// A small floating window that displays tooltip text near the cursor.
// Used because NSToolTip does not fire for .nonactivatingPanel + .borderless windows.

import Cocoa

@MainActor final class TooltipWindow {
    static let shared = TooltipWindow()

    private var window: NSWindow?
    private var textField: NSTextField?
    private var hideTimer: Timer?
    private var showTimer: Timer?

    func show(_ text: String, near point: NSPoint) {
        showTimer?.invalidate()
        showTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.displayTooltip(text, near: point)
            }
        }
    }

    private func displayTooltip(_ text: String, near point: NSPoint) {
        hide()

        let font = NSFont.systemFont(ofSize: 11)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let hPadding: CGFloat = 12
        let vPadding: CGFloat = 6
        // Add extra width buffer to prevent NSTextField internal clipping
        let width = ceil(textSize.width) + hPadding * 2 + 4
        let height = ceil(textSize.height) + vPadding * 2

        let frame = NSRect(
            x: point.x - width / 2,
            y: point.y - height - 4,
            width: width,
            height: height
        )

        let win = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 10)
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = true
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces]
        win.isReleasedWhenClosed = false

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor(white: 0.2, alpha: 0.95).cgColor
        contentView.layer?.cornerRadius = 4

        // Use the full content width for the label so text is never clipped
        let label = NSTextField(frame: NSRect(x: 0, y: 0, width: width, height: height))
        label.isEditable = false
        label.isBordered = false
        label.isSelectable = false
        label.drawsBackground = false
        label.backgroundColor = .clear
        label.textColor = .white
        label.font = font
        label.stringValue = text
        label.alignment = .center
        label.lineBreakMode = .byClipping
        label.cell?.truncatesLastVisibleLine = false
        contentView.addSubview(label)

        win.contentView = contentView
        win.orderFrontRegardless()
        self.window = win

        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    func hide() {
        showTimer?.invalidate()
        showTimer = nil
        hideTimer?.invalidate()
        hideTimer = nil
        window?.orderOut(nil)
        window = nil
    }
}
