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
    private var undoStack: [any DrawingItem] = []

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
        undoStack.removeAll()
    }

    /// Moves the most recent item from the canvas to the redo stack.
    func undo() {
        guard let last = items.popLast() else { return }
        undoStack.append(last)
    }

    /// Restores the most recently undone item back to the canvas.
    func redo() {
        guard let last = undoStack.popLast() else { return }
        items.append(last)
    }

    /// Removes all items and clears the undo/redo history.
    func clearAll() {
        items.removeAll()
        undoStack.removeAll()
    }

    /// Removes the item at the given index, if valid.
    func removeItem(at index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
    }

    /// Removes all items whose stroke path intersects the given point within `threshold` points.
    func removeItems(intersecting point: CGPoint, threshold: CGFloat = 10) {
        items.removeAll { $0.hitTest(point: point, threshold: threshold) }
    }
}


