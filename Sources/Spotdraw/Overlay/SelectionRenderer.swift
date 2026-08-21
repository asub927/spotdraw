// SelectionRenderer.swift
// Draws the dashed marquee rectangle during drag selection and the dashed
// per-item selection outlines while items are selected.
//
// Rendering order: board background → items → marquee and selection outlines
// (Requirement 2.15, 10.7).

import Cocoa
import SpotdrawCore

// MARK: - SelectionRenderer

internal enum SelectionRenderer {

    /// The dash pattern used for both marquee and selection outlines.
    private static let dashPattern: [CGFloat] = [6, 4]

    /// The line width used for selection outlines.
    private static let outlineWidth: CGFloat = 1.5

    /// The color used for selection outlines.
    private static let outlineColor: NSColor = .white

    /// Draws the dashed marquee rectangle spanning the press and current points
    /// (Requirement 2.6).
    static func drawMarquee(from press: CGPoint, to current: CGPoint, in context: CGContext) {
        let rect = normalizedRect(from: press, to: current)
        guard rect.width > 0 || rect.height > 0 else { return }

        context.saveGState()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(1.0)
        context.setLineDash(phase: 0, lengths: dashPattern)
        context.stroke(rect)

        // Semi-transparent fill for visibility
        context.setFillColor(NSColor.white.withAlphaComponent(0.05).cgColor)
        context.fill(rect)

        context.restoreGState()
    }

    /// Draws a dashed outline around each selected item's bounding rectangle
    /// (Requirement 2.11). Renders above every DrawingItem (Requirement 2.15).
    static func drawSelectionOutlines(
        selectedIDs: Set<UUID>,
        items: [any DrawingItem],
        in context: CGContext
    ) {
        guard !selectedIDs.isEmpty else { return }

        context.saveGState()
        context.setStrokeColor(outlineColor.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(outlineWidth)
        context.setLineDash(phase: 0, lengths: dashPattern)

        for item in items where selectedIDs.contains(item.id) {
            let itemBounds = item.bounds
            // Outset slightly so the outline doesn't overlap the item
            let outlineRect = itemBounds.insetBy(dx: -3, dy: -3)
            context.stroke(outlineRect)
        }

        context.restoreGState()
    }

    /// Constructs a normalized rect from two corner points.
    private static func normalizedRect(from a: CGPoint, to b: CGPoint) -> CGRect {
        let x = min(a.x, b.x)
        let y = min(a.y, b.y)
        let w = abs(b.x - a.x)
        let h = abs(b.y - a.y)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
