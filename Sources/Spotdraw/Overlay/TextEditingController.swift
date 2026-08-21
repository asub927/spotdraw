// TextEditingController.swift
// Manages the lifecycle of a borderless, transparent NSTextView subview used
// to compose or edit a TextAnnotation in place on an OverlayView. Escape and
// Cmd+Return commit; commit() trims whitespace and reports .discarded for an
// empty result, leaving DrawingState untouched. See design.md, "TextEditingController".

import Cocoa
import SpotdrawCore

// MARK: - TextCommitResult

/// The outcome of committing an in-progress text edit.
internal enum TextCommitResult {
    /// The field was empty or contained only whitespace; no state change.
    case discarded
    /// A brand-new TextAnnotation should be added to DrawingState.
    case created(TextAnnotation)
    /// An existing TextAnnotation should be replaced in place. `original` is the
    /// item as it was before editing began; `updated` is the edited replacement.
    case edited(original: TextAnnotation, updated: TextAnnotation)
}

// MARK: - TextEditingController

/// Owns the NSTextView subview used while a TextAnnotation is being composed
/// or edited. The text view is a real first responder — inheriting caret handling,
/// input-method support, and the system Edit menu for free — configured
/// borderless and transparent so it visually matches the committed
/// `TextAnnotation` it will become.
@MainActor internal final class TextEditingController: NSObject, NSTextViewDelegate {

    // MARK: - Properties

    private(set) var isEditing = false

    /// The item being edited, or nil when composing a new annotation.
    private(set) var editingItem: TextAnnotation?

    /// Receives results produced by a commit gesture or by begin()
    /// superseding an active edit. Direct commit() callers still receive the
    /// result synchronously and are not routed a second time.
    var onCommit: ((TextCommitResult) -> Void)?

    /// The scroll view's frame in the owner view's coordinate space, for
    /// click-outside detection in OverlayView.
    var scrollViewFrame: NSRect? {
        scrollView?.frame
    }

    private weak var ownerView: OverlayView?
    private var scrollView: NSScrollView?
    private var textView: NSTextView?
    private var anchor: CGPoint = .zero
    private var color: NSColor = .systemRed
    private var fontSize: CGFloat = 24

    // MARK: - Lifecycle

    /// Begins editing. `existing` nil means compose a new annotation at `anchor`;
    /// non-nil means edit that annotation's current string, still anchored at
    /// `anchor`. Beginning an edit while one is already active commits the first
    /// before beginning the second.
    ///
    /// `color` and `fontSize` are snapshotted here and carried through to the
    /// committed item, so later changes to the active color or persisted font
    /// size do not affect an edit already in progress (Requirement 1.15).
    func begin(at anchor: CGPoint, existing: TextAnnotation?, in view: OverlayView,
               color: NSColor, fontSize: CGFloat) {
        if isEditing {
            let result = commit()
            onCommit?(result)
        }

        self.anchor = anchor
        self.color = color
        self.fontSize = fontSize
        self.editingItem = existing
        self.ownerView = view

        let frame = fieldFrame(in: view)

        // NSScrollView container — borderless, transparent
        let scrollView = NSScrollView(frame: frame)
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear

        // NSTextView — the actual editing surface
        let textView = NSTextView(frame: NSRect(origin: .zero, size: frame.size))
        textView.isRichText = false
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = color
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: frame.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.delegate = self
        textView.string = existing?.string ?? ""

        scrollView.documentView = textView
        view.addSubview(scrollView)
        view.window?.makeFirstResponder(textView)

        self.scrollView = scrollView
        self.textView = textView
        isEditing = true
    }

    /// Commits the text view's current contents and tears the view down. Trims
    /// leading/trailing whitespace; an empty result after trimming leaves
    /// `DrawingState.items` and both undo/redo stacks untouched.
    @discardableResult
    func commit() -> TextCommitResult {
        guard isEditing, let textView else { return .discarded }

        let trimmed = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)

        scrollView?.removeFromSuperview()
        scrollView = nil
        self.textView = nil
        isEditing = false
        let original = editingItem
        editingItem = nil
        let ownerView = self.ownerView
        self.ownerView = nil
        if let ownerView, let window = ownerView.window {
            window.makeFirstResponder(ownerView)
        }

        guard !trimmed.isEmpty else { return .discarded }

        if let original {
            let updated = original.replacingString(trimmed)
            return .edited(original: original, updated: updated)
        }

        let created = TextAnnotation(string: trimmed, anchor: anchor, fontSize: fontSize, color: color)
        return .created(created)
    }

    internal func commitAndNotify() {
        guard isEditing else { return }
        let result = commit()
        onCommit?(result)
    }

    // MARK: - NSTextViewDelegate

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // Escape commits (Requirement 5.3)
        if commandSelector == #selector(NSStandardKeyBindingResponding.cancelOperation(_:)) {
            commitAndNotify()
            return true
        }
        // All other commands (including insertNewline:) pass through to NSTextView
        return false
    }

    func textDidChange(_ notification: Notification) {
        guard let textView, let scrollView else { return }
        // Recalculate height based on content
        textView.sizeToFit()
        var frame = scrollView.frame
        frame.size.height = max(fontSize * 1.4, textView.frame.height + 4)
        scrollView.frame = frame
    }

    // MARK: - Frame Calculation

    /// A generous frame anchored at `anchor` in the view's
    /// (flipped-off, bottom-left-origin) coordinate space, matching how
    /// `TextAnnotation` measures and draws its own glyph bounds.
    private func fieldFrame(in view: OverlayView) -> NSRect {
        let width: CGFloat = 400
        let height = fontSize * 1.4
        return NSRect(x: anchor.x, y: anchor.y, width: width, height: height)
    }
}
