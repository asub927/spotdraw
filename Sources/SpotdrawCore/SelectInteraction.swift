// SelectInteraction.swift
// A pure value-type state machine for the select tool's press/drag/release
// lifecycle: marquee drawing, hit selection, and move-with-clamp.
//
// Extracted from OverlayView (see .kiro/specs/overlay-gesture-extraction). The
// interaction returns InteractionOutcome values describing *intent* and performs
// no side effects: it never mutates DrawingItems, never touches DrawingState, and
// never triggers a redraw. OverlayView interprets each outcome.
//
// This type is nonisolated (no @MainActor): it holds only value math.
//
// A note on the move-clamp: OverlayView's old clampMoveDelta ran against items
// that already had the live preview applied, so it reconstructed the pre-drag
// bounding box as "current bbox minus total delta" — the source of a confusing
// comment. Here the pre-drag box is captured explicitly at `begin` (as
// `originalBBox`) so the clamp math reads directly.

import Cocoa

// MARK: - SelectDragMode

public enum SelectDragMode: Equatable {
    case none
    case movingSelection
    case drawingMarquee
}

// MARK: - HitResult

/// What the view found at the press point. Hit-testing stays in the view (it needs
/// SelectionManager and the item list); only the result crosses the seam.
public enum HitResult: Equatable {
    /// The press landed inside the current (non-empty) selection's bounding box.
    case insideSelectionBox
    /// The press hit an item with this id.
    case hitItem(UUID)
    /// The press landed on empty space.
    case emptySpace
}

// MARK: - InteractionOutcome

/// The intent produced by a select interaction step. The view executes it.
public enum InteractionOutcome: Equatable {
    case none
    /// Replace the selection with exactly these ids.
    case setSelection(Set<UUID>)
    /// Toggle this id's membership (shift-click).
    case toggleSelection(UUID)
    /// Clear the selection.
    case clearSelection
    /// Live-preview translate the selected items by this per-drag delta.
    case previewTranslate(CGSize)
    /// Render a marquee rectangle (in progress).
    case marquee(CGRect)
    /// Resolve this marquee rect to intersecting items and set the selection.
    case commitMarquee(CGRect)
    /// Commit a finished move: undo the live preview, then apply this final
    /// clamped delta once through DrawingState. `.zero` means "no-op move"
    /// (below threshold): the view still undoes the preview, records nothing.
    case commitMove(delta: CGSize)
}

// MARK: - SelectInteraction

public struct SelectInteraction {

    /// Minimum points of the selection bounding box that must remain inside the
    /// view after a move (Requirement 3.9 of annotation-parity).
    public static let minVisible: CGFloat = 20

    /// Moves whose net magnitude is below this are treated as no-ops (Requirement 3.10).
    public static let moveThreshold: CGFloat = 1.0

    public private(set) var mode: SelectDragMode = .none

    private var pressPoint: CGPoint = .zero
    private var lastPoint: CGPoint = .zero
    private var currentPoint: CGPoint = .zero
    private var totalDelta: CGSize = .zero
    /// The selection bounding box captured at `begin`, before any live preview.
    private var originalBBox: CGRect?

    public init() {}

    /// Total accumulated move delta so far (for the view to undo the live preview).
    public var accumulatedMoveDelta: CGSize { totalDelta }

    /// The in-progress marquee rectangle, if a marquee drag is active.
    public var marqueeRect: CGRect? {
        mode == .drawingMarquee ? Self.rect(from: pressPoint, to: currentPoint) : nil
    }

    // MARK: - Lifecycle

    /// Handle a press. `currentBBox` is the selection's bounding box now (nil if
    /// empty). `hit` describes what the view found at the point.
    public mutating func begin(at point: CGPoint,
                               shiftHeld: Bool,
                               hit: HitResult,
                               currentBBox: CGRect?) -> InteractionOutcome {
        pressPoint = point
        currentPoint = point
        lastPoint = point
        totalDelta = .zero

        switch hit {
        case .insideSelectionBox:
            // Begin a move drag of the current selection.
            mode = .movingSelection
            originalBBox = currentBBox
            return .none

        case .hitItem(let id):
            mode = .none
            if shiftHeld {
                return .toggleSelection(id)   // Requirements 2.8, 2.9
            } else {
                return .setSelection([id])    // Requirement 2.4
            }

        case .emptySpace:
            // Start a marquee. Clear first unless shift is held (Requirement 2.5).
            mode = .drawingMarquee
            return shiftHeld ? .marquee(Self.rect(from: point, to: point))
                             : .clearSelection
        }
    }

    /// Handle a drag to `point`.
    public mutating func drag(to point: CGPoint) -> InteractionOutcome {
        switch mode {
        case .none:
            return .none
        case .movingSelection:
            let incremental = CGSize(width: point.x - lastPoint.x,
                                     height: point.y - lastPoint.y)
            lastPoint = point
            totalDelta = CGSize(width: totalDelta.width + incremental.width,
                                height: totalDelta.height + incremental.height)
            return .previewTranslate(incremental)
        case .drawingMarquee:
            currentPoint = point
            return .marquee(Self.rect(from: pressPoint, to: point))
        }
    }

    /// Handle release. `viewBounds` is used to clamp a committed move.
    public mutating func end(viewBounds: CGRect) -> InteractionOutcome {
        defer { resetAfterEnd() }
        switch mode {
        case .none:
            return .none
        case .movingSelection:
            let netMax = max(abs(totalDelta.width), abs(totalDelta.height))
            if netMax < Self.moveThreshold {
                // Below threshold: view undoes preview, records nothing.
                return .commitMove(delta: .zero)
            }
            let clamped = clampedDelta(viewBounds: viewBounds)
            return .commitMove(delta: clamped)
        case .drawingMarquee:
            return .commitMarquee(Self.rect(from: pressPoint, to: currentPoint))
        }
    }

    // MARK: - Clamp

    /// Clamps `totalDelta` so at least `minVisible` points of the selection's
    /// pre-drag bounding box remain inside `viewBounds` (Requirement 3.9).
    /// Uses the explicitly captured `originalBBox`, not the preview-shifted box.
    private func clampedDelta(viewBounds: CGRect) -> CGSize {
        guard let original = originalBBox else { return totalDelta }

        var dx = totalDelta.width
        var dy = totalDelta.height

        let movedH = original.offsetBy(dx: dx, dy: 0)
        if movedH.maxX < viewBounds.minX + Self.minVisible {
            dx = (viewBounds.minX + Self.minVisible) - original.maxX
        } else if movedH.minX > viewBounds.maxX - Self.minVisible {
            dx = (viewBounds.maxX - Self.minVisible) - original.minX
        }

        let movedV = original.offsetBy(dx: dx, dy: dy)
        if movedV.maxY < viewBounds.minY + Self.minVisible {
            dy = (viewBounds.minY + Self.minVisible) - original.maxY
        } else if movedV.minY > viewBounds.maxY - Self.minVisible {
            dy = (viewBounds.maxY - Self.minVisible) - original.minY
        }

        return CGSize(width: dx, height: dy)
    }

    private mutating func resetAfterEnd() {
        mode = .none
        pressPoint = .zero
        lastPoint = .zero
        currentPoint = .zero
        totalDelta = .zero
        originalBBox = nil
    }

    // MARK: - Geometry

    /// Normalized rect from two corner points (matches OverlayView.rectFromPoints).
    static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x),
               y: min(a.y, b.y),
               width: abs(b.x - a.x),
               height: abs(b.y - a.y))
    }
}
