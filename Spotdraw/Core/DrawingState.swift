// DrawingState.swift
// Drawing model layer: defines the DrawingItem protocol, tool/board-mode enums,
// and the DrawingState class that owns the undo/redo stack and active
// tool/color/line-width state shared across overlay views.

import Cocoa

// MARK: - ToolType

internal enum ToolType: CaseIterable, Hashable, Sendable {
    case pen
    case arrow
    case rectangle
    case circle
    case line
    case highlighter
    case eraser

    /// The keyboard shortcut character that activates this tool.
    var keyCharacter: String {
        switch self {
        case .pen: "p"
        case .arrow: "a"
        case .rectangle: "r"
        case .circle: "o"
        case .line: "l"
        case .highlighter: "h"
        case .eraser: "e"
        }
    }
}

// MARK: - BoardMode

internal enum BoardMode: Equatable {
    case none
    case white
    case black
    case custom(NSColor)

    /// Returns the next mode in the cycling sequence: none → white → black → none.
    /// Custom mode resets to none.
    var next: BoardMode {
        switch self {
        case .none: .white
        case .white: .black
        case .black: .none
        case .custom: .none
        }
    }
}

// BoardMode uses @unchecked Sendable because NSColor is not Sendable,
// but BoardMode instances are created and used exclusively on the main thread.
extension BoardMode: @unchecked Sendable {}

// MARK: - ColorShortcut

/// Maps number keys to stroke color presets for quick switching during annotation.
internal enum ColorShortcut: CaseIterable {
    case red, blue, green, yellow, white

    /// The keyboard character that activates this color.
    var keyCharacter: String {
        switch self {
        case .red: "1"
        case .blue: "2"
        case .green: "3"
        case .yellow: "4"
        case .white: "5"
        }
    }

    /// The NSColor associated with this shortcut.
    var color: NSColor {
        switch self {
        case .red: .systemRed
        case .blue: .systemBlue
        case .green: .systemGreen
        case .yellow: .systemYellow
        case .white: .white
        }
    }
}

// MARK: - DrawingItem Protocol

/// A drawable annotation element that can be rendered, hit-tested, and faded over time.
internal protocol DrawingItem: AnyObject {
    /// Unique identifier for this drawing item.
    var id: UUID { get }
    /// The stroke or fill color used when rendering.
    var color: NSColor { get }
    /// The stroke width in points.
    var lineWidth: CGFloat { get }
    /// The timestamp when this item was created, used for fade calculations.
    var createdAt: Date { get }
    /// Current opacity (0–1). Mutated by the fade timer to animate item removal.
    var opacity: CGFloat { get set }
    /// Accumulated translation applied at render and hit-test time.
    var offset: CGSize { get set }
    /// The smallest rectangle containing this item's rendered geometry, before `offset`.
    var untranslatedBounds: CGRect { get }
    /// Renders this item into the given Core Graphics context.
    func draw(in context: CGContext)
    /// Returns `true` if `point` lies within `threshold` points of this item's stroke path.
    func hitTest(point: CGPoint, threshold: CGFloat) -> Bool
}

// MARK: - DrawingState

/// Owns the shared drawing model: active items, undo/redo stack, and tool configuration.
///
/// DrawingState is intentionally a reference type (class) because multiple OverlayView
/// instances across different screens share the same drawing state. Changes to items,
/// undo/redo, and tool state must be visible across all overlay windows without explicit
/// synchronization.
internal final class DrawingState {

    // MARK: - Properties

    var items: [any DrawingItem] = []
    private var undoStack: [DrawingOperation] = []
    private var redoStack: [DrawingOperation] = []

    var activeTool: ToolType = .pen
    var activeColor: NSColor = .systemRed
    var activeLineWidth: CGFloat = 3.0
    var boardMode: BoardMode = .none
    var fadeMode: Bool = false
    var fadeDuration: TimeInterval = 3.0

    // MARK: - Mutations

    /// Appends a new drawing item and clears the redo stack.
    func addItem(_ item: any DrawingItem) {
        items.append(item)
        undoStack.append(.add(item: item))
        redoStack.removeAll()
    }

    /// Undoes the most recently recorded operation, moving it to the redo stack.
    func undo() {
        guard let operation = undoStack.popLast() else { return }
        operation.undo(applyingTo: &items)
        redoStack.append(operation)
    }

    /// Reapplies the most recently undone operation, moving it back to the undo stack.
    func redo() {
        guard let operation = redoStack.popLast() else { return }
        operation.redo(applyingTo: &items)
        undoStack.append(operation)
    }

    /// Removes all items and clears the undo/redo history.
    ///
    /// This does NOT record a `.remove` operation. Recording one would let undo
    /// resurrect every cleared item, a behavior change Requirement 10.8 forbids.
    /// Clearing both stacks directly makes undo (not just redo) inert afterward.
    func clearAll() {
        items.removeAll()
        undoStack.removeAll()
        redoStack.removeAll()
    }

    /// Removes the item at the given index, if valid, recording a `.remove` operation.
    func removeItem(at index: Int) {
        guard items.indices.contains(index) else { return }
        let entry = (index: index, item: items[index])
        removeItems(at: [entry.index])
        undoStack.append(.remove(entries: [entry]))
        redoStack.removeAll()
    }

    /// Removes all items whose stroke path intersects the given point within `threshold` points.
    func removeItems(intersecting point: CGPoint, threshold: CGFloat = 10) {
        items.removeAll { $0.hitTestTranslated(point: point, threshold: threshold) }
    }

    /// Translates every item whose `id` is in `ids` by `offset`, recording a `.move` operation.
    func translate(ids: [UUID], by offset: CGSize) {
        for item in items where ids.contains(item.id) {
            item.translate(by: offset)
        }
        undoStack.append(.move(itemIDs: ids, offset: offset))
        redoStack.removeAll()
    }

    /// Replaces the item at `index` with `item`, preserving its index and recording
    /// an `.edit` operation.
    func replaceItem(at index: Int, with item: any DrawingItem) {
        guard items.indices.contains(index) else { return }
        let before = items[index]
        items[index] = item
        undoStack.append(.edit(index: index, before: before, after: item))
        redoStack.removeAll()
    }

    /// Returns the item with the given identifier, if present.
    func item(withID id: UUID) -> (any DrawingItem)? {
        items.first { $0.id == id }
    }

    // MARK: - Shared removal helper

    /// Removes items at the given indices from `items`.
    ///
    /// Every item-removing mutation routes through this single helper so that a
    /// later phase's selection-pruning logic has one place to attach rather than
    /// being scattered across removal call sites. No selection exists yet, so
    /// this is a plain removal for now.
    private func removeItems(at indices: [Int]) {
        for index in indices.sorted(by: >) where items.indices.contains(index) {
            items.remove(at: index)
        }
    }
}


