// TextEditingController.swift
// Manages the lifecycle of a borderless, transparent NSTextField subview used
// to compose or edit a TextAnnotation in place on an OverlayView. Both Return
// and Escape commit; commit() trims whitespace and reports .discarded for an
// empty result, leaving DrawingState untouched. See design.md, "TextEditingController".

import Cocoa

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

/// Owns the NSTextField subview used while a Text_Annotation is being composed
/// or edited. The field is a real first responder — inheriting caret handling,
/// input-method support, and the system Edit menu for free — configured
/// borderless and transparent so it visually matches the committed
/// `TextAnnotation` it will become.
@MainActor internal final class TextEditingController: NSObject, NSTextFieldDelegate {

    // MARK: - Properties

    private(set) var isEditing = false

    /// The item being edited, or nil when composing a new annotation.
    private(set) var editingItem: TextAnnotation?

    /// Receives results produced by a real NSTextField command or by begin()
    /// superseding an active edit. Direct commit() callers still receive the
    /// result synchronously and are not routed a second time.
    var onCommit: ((TextCommitResult) -> Void)?

    private weak var ownerView: OverlayView?
    private var textField: NSTextField?
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

        let field = NSTextField(frame: fieldFrame(in: view))
        field.stringValue = existing?.string ?? ""
        field.font = .systemFont(ofSize: fontSize)
        field.textColor = color
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.delegate = self

        view.addSubview(field)
        view.window?.makeFirstResponder(field)

        textField = field
        isEditing = true
    }

    /// Commits the field's current contents and tears the field down. Trims
    /// leading/trailing whitespace; an empty result after trimming leaves
    /// `DrawingState.items` and both undo/redo stacks untouched.
    @discardableResult
    func commit() -> TextCommitResult {
        guard isEditing, let field = textField else { return .discarded }

        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        field.removeFromSuperview()
        textField = nil
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

    private func commitAndNotify() {
        guard isEditing else { return }
        let result = commit()
        onCommit?(result)
    }

    // MARK: - NSTextFieldDelegate

    /// NSTextField sends Return and Escape through this command path while it is
    /// first responder. Both commands commit per the text annotation requirements;
    /// Escape is intentionally not treated as cancellation.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        let commits = commandSelector == #selector(NSStandardKeyBindingResponding.insertNewline(_:))
            || commandSelector == #selector(NSStandardKeyBindingResponding.cancelOperation(_:))
        guard commits else { return false }
        commitAndNotify()
        return true
    }

    // MARK: - Frame Calculation

    /// A generous single-line frame anchored at `anchor` in the view's
    /// (flipped-off, bottom-left-origin) coordinate space, matching how
    /// `TextAnnotation` measures and draws its own glyph bounds.
    private func fieldFrame(in view: OverlayView) -> NSRect {
        let width: CGFloat = 400
        let height = fontSize * 1.4
        return NSRect(x: anchor.x, y: anchor.y, width: width, height: height)
    }
}
