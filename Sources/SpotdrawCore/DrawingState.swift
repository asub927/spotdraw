// DrawingState.swift
// Drawing model layer: defines the DrawingItem protocol, tool/board-mode enums,
// and the DrawingState class that owns the undo/redo stack and active
// tool/color/line-width state shared across overlay views.

import Cocoa

// MARK: - ToolType

public enum ToolType: CaseIterable, Hashable, Sendable {
    case pen
    case arrow
    case rectangle
    case circle
    case line
    case highlighter
    case eraser
    case text
    case select
}

// MARK: - BoardMode

public enum BoardMode: Equatable {
    case none
    case white
    case black
    case custom(NSColor)

    /// Returns the next mode in the cycling sequence: none → white → black → none.
    /// Custom mode resets to none.
    public var next: BoardMode {
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
public enum ColorShortcut: CaseIterable {
    case red, blue, green, yellow, white

    /// The NSColor associated with this shortcut.
    public var color: NSColor {
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
public protocol DrawingItem: AnyObject {
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
    /// The display this item belongs to. Used for multi-screen isolation.
    var screenID: CGDirectDisplayID { get set }
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
public final class DrawingState {

    // MARK: - Properties

    public var items: [any DrawingItem] = []
    private var undoStack: [DrawingOperation] = []
    private var redoStack: [DrawingOperation] = []

    /// The selection lives on DrawingState (not OverlayView) because a single
    /// DrawingState instance is shared across every per-screen view.
    public let selection = SelectionManager()

    public var activeTool: ToolType = .pen {
        didSet {
            // Requirement 2.12: clear selection when switching away from select tool.
            if activeTool != .select { selection.clear() }
        }
    }
    public var activeColor: NSColor = .systemRed
    public var activeLineWidth: CGFloat = 3.0
    public var boardMode: BoardMode = .none
    public var fadeMode: Bool = false
    public var fadeDuration: TimeInterval = 3.0

    // MARK: - Mutations

    public init() {}

    /// Appends a new drawing item and clears the redo stack.
    public func addItem(_ item: any DrawingItem) {
        items.append(item)
        undoStack.append(.add(item: item))
        redoStack.removeAll()
    }

    /// Undoes the most recently recorded operation, moving it to the redo stack.
    public func undo() {
        guard let operation = undoStack.popLast() else { return }
        operation.undo(applyingTo: &items)
        redoStack.append(operation)
        pruneSelection()
    }

    /// Reapplies the most recently undone operation, moving it back to the undo stack.
    public func redo() {
        guard let operation = redoStack.popLast() else { return }
        operation.redo(applyingTo: &items)
        undoStack.append(operation)
        pruneSelection()
    }

    /// Removes all items and clears the undo/redo history.
    ///
    /// This does NOT record a `.remove` operation. Recording one would let undo
    /// resurrect every cleared item, a behavior change Requirement 10.8 forbids.
    /// Clearing both stacks directly makes undo (not just redo) inert afterward.
    public func clearAll() {
        items.removeAll()
        undoStack.removeAll()
        redoStack.removeAll()
        selection.clear()
    }

    /// Removes the item at the given index, if valid, recording a `.remove` operation.
    public func removeItem(at index: Int) {
        guard items.indices.contains(index) else { return }
        let entry = (index: index, item: items[index])
        removeItems(at: [entry.index])
        undoStack.append(.remove(entries: [entry]))
        redoStack.removeAll()
    }

    /// Removes all items whose stroke path intersects the given point within `threshold` points.
    /// When `screenID` is provided, only items on that screen are hit-tested.
    public func removeItems(intersecting point: CGPoint, threshold: CGFloat = 10, screenID: CGDirectDisplayID? = nil) {
        let removedIDs = items.filter { item in
            if let screenID, item.screenID != screenID { return false }
            return item.hitTestTranslated(point: point, threshold: threshold)
        }.map { $0.id }
        items.removeAll { item in
            if let screenID, item.screenID != screenID { return false }
            return item.hitTestTranslated(point: point, threshold: threshold)
        }
        for id in removedIDs {
            selection.remove(id)
        }
    }

    /// Translates every item whose `id` is in `ids` by `offset`, recording a `.move` operation.
    public func translate(ids: [UUID], by offset: CGSize) {
        for item in items where ids.contains(item.id) {
            item.translate(by: offset)
        }
        undoStack.append(.move(itemIDs: ids, offset: offset))
        redoStack.removeAll()
    }

    /// Replaces the item at `index` with `item`, preserving its index and recording
    /// an `.edit` operation.
    public func replaceItem(at index: Int, with item: any DrawingItem) {
        guard items.indices.contains(index) else { return }
        let before = items[index]
        items[index] = item
        undoStack.append(.edit(index: index, before: before, after: item))
        redoStack.removeAll()
    }

    /// Returns the item with the given identifier, if present.
    public func item(withID id: UUID) -> (any DrawingItem)? {
        items.first { $0.id == id }
    }

    /// Removes every Drawing_Item in the selection and records one undoable `.remove`
    /// operation. Empty selection is a no-op that records nothing (Requirement 3.7).
    public func removeSelected() {
        guard !selection.isEmpty else { return }
        var entries: [(index: Int, item: any DrawingItem)] = []
        for (index, item) in items.enumerated() where selection.contains(item.id) {
            entries.append((index: index, item: item))
        }
        guard !entries.isEmpty else { return }
        // Remove in reverse index order to avoid index invalidation
        for entry in entries.reversed() {
            items.remove(at: entry.index)
        }
        selection.clear()
        undoStack.append(.remove(entries: entries))
        redoStack.removeAll()
    }

    /// Sets the selection to every DrawingItem in the item list (Requirement 2.10).
    /// Only effective while the select tool is active.
    public func selectAll() {
        guard activeTool == .select else { return }
        selection.set(Set(items.map { $0.id }))
    }

    // MARK: - Shared removal helper

    /// Removes items at the given indices from `items` and prunes the selection.
    ///
    /// Every item-removing mutation routes through this single helper so that
    /// selection pruning holds by construction rather than being scattered across
    /// removal call sites. Requirement 2.14.
    private func removeItems(at indices: [Int]) {
        for index in indices.sorted(by: >) where items.indices.contains(index) {
            selection.remove(items[index].id)
            items.remove(at: index)
        }
    }

    /// Ensures the selection contains only IDs that are currently in the item list.
    /// Called after undo/redo which bypass the removeItems(at:) helper.
    private func pruneSelection() {
        let liveIDs = Set(items.map { $0.id })
        let stale = selection.selectedIDs.subtracting(liveIDs)
        for id in stale {
            selection.remove(id)
        }
    }
}


