// TextAnnotation.swift
// A DrawingItem that renders a string at an anchor point using a color and
// font size. Rendering pushes an NSGraphicsContext wrapping the CGContext,
// then draws the attributed string; hit-testing and bounds are derived from
// the measured glyph size. See design.md, "TextAnnotation".

import Cocoa

// MARK: - TextAnnotation

public final class TextAnnotation: DrawingItem {
    public let id: UUID
    public private(set) var string: String
    public private(set) var anchor: CGPoint
    public let fontSize: CGFloat
    public let color: NSColor
    public let createdAt = Date()
    public var opacity: CGFloat = 1.0
    public var offset: CGSize = .zero
    public var screenID: CGDirectDisplayID = CGMainDisplayID()

    /// TextAnnotation has no stroke; it is not a stroked shape.
    public let lineWidth: CGFloat = 0

    public init(string: String, anchor: CGPoint, fontSize: CGFloat, color: NSColor) {
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
    /// the fixed font, color, and paragraph style for multi-line support —
    /// opacity is applied separately via `context.setAlpha` so fade processing
    /// works unchanged (Requirement 10.5).
    private var attributedString: NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = fontSize * 0.2

        return NSAttributedString(
            string: string,
            attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle
            ]
        )
    }

    /// Multi-line bounding rect anchored at `anchor`, using
    /// `.usesLineFragmentOrigin` for correct multi-line measurement.
    /// Cached since `string` is only ever replaced (not mutated) via
    /// `replacingString(_:)` which returns a new instance.
    private lazy var cachedUntranslatedBounds: CGRect = {
        let maxWidth: CGFloat = 400
        let boundingRect = attributedString.boundingRect(
            with: NSSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return CGRect(origin: anchor, size: boundingRect.size)
    }()

    public var untranslatedBounds: CGRect { cachedUntranslatedBounds }

    public func draw(in context: CGContext) {
        context.saveGState()
        context.setAlpha(opacity)

        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = graphicsContext

        let maxWidth: CGFloat = 400
        let drawRect = NSRect(
            x: anchor.x,
            y: anchor.y,
            width: maxWidth,
            height: cachedUntranslatedBounds.height
        )
        attributedString.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])

        NSGraphicsContext.current = previous
        context.restoreGState()
    }

    /// True when `point` lies within the measured glyph bounds, outset by `threshold`.
    public func hitTest(point: CGPoint, threshold: CGFloat) -> Bool {
        untranslatedBounds.insetBy(dx: -threshold, dy: -threshold).contains(point)
    }

    /// Returns a copy with a new string, preserving `id`, `anchor`, `fontSize`,
    /// and `color`. Returning a copy rather than mutating in place is what makes
    /// `.edit(index:before:after:)` trivially invertible — undo just puts the
    /// original back.
    public func replacingString(_ newString: String) -> TextAnnotation {
        let copy = TextAnnotation(id: id, string: newString, anchor: anchor, fontSize: fontSize, color: color)
        copy.opacity = opacity
        copy.offset = offset
        copy.screenID = screenID
        return copy
    }
}
