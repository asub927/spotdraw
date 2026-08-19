// TextAnnotation.swift
// A DrawingItem that renders a string at an anchor point using a color and
// font size. Rendering pushes an NSGraphicsContext wrapping the CGContext,
// then draws the attributed string; hit-testing and bounds are derived from
// the measured glyph size. See design.md, "TextAnnotation".

import Cocoa

// MARK: - TextAnnotation

internal final class TextAnnotation: DrawingItem {
    let id: UUID
    private(set) var string: String
    private(set) var anchor: CGPoint
    let fontSize: CGFloat
    let color: NSColor
    let createdAt = Date()
    var opacity: CGFloat = 1.0
    var offset: CGSize = .zero

    /// TextAnnotation has no stroke; it is not a stroked shape.
    let lineWidth: CGFloat = 0

    init(string: String, anchor: CGPoint, fontSize: CGFloat, color: NSColor) {
        self.id = UUID()
        self.string = string
        self.anchor = anchor
        self.fontSize = fontSize
        self.color = color
    }

    private init(id: UUID, string: String, anchor: CGPoint, fontSize: CGFloat, color: NSColor) {
        self.id = id
        self.string = string
        self.anchor = anchor
        self.fontSize = fontSize
        self.color = color
    }

    /// The attributed string used for both drawing and measurement, built with
    /// the fixed font and color — opacity is applied separately via
    /// `context.setAlpha` so fade processing works unchanged (Requirement 10.5).
    private var attributedString: NSAttributedString {
        NSAttributedString(
            string: string,
            attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: color
            ]
        )
    }

    /// Measured glyph bounds anchored at `anchor`, cached since `string` is only
    /// ever replaced (not mutated) via `replacingString(_:)`.
    private lazy var cachedUntranslatedBounds: CGRect = {
        let size = attributedString.size()
        return CGRect(origin: anchor, size: size)
    }()

    var untranslatedBounds: CGRect { cachedUntranslatedBounds }

    func draw(in context: CGContext) {
        context.saveGState()
        context.setAlpha(opacity)

        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = graphicsContext
        attributedString.draw(at: anchor)
        NSGraphicsContext.current = previous

        context.restoreGState()
    }

    /// True when `point` lies within the measured glyph bounds, outset by `threshold`.
    func hitTest(point: CGPoint, threshold: CGFloat) -> Bool {
        untranslatedBounds.insetBy(dx: -threshold, dy: -threshold).contains(point)
    }

    /// Returns a copy with a new string, preserving `id`, `anchor`, `fontSize`,
    /// and `color`. Returning a copy rather than mutating in place is what makes
    /// `.edit(index:before:after:)` trivially invertible — undo just puts the
    /// original back.
    func replacingString(_ newString: String) -> TextAnnotation {
        let copy = TextAnnotation(id: id, string: newString, anchor: anchor, fontSize: fontSize, color: color)
        copy.opacity = opacity
        copy.offset = offset
        return copy
    }
}
