// SelectionManager.swift
// Owns the set of currently selected DrawingItem identifiers and provides
// operations for selection manipulation, hit testing, and bounding box computation.
//
// Placement: SelectionManager is owned by DrawingState, not OverlayView, because
// a single DrawingState instance is shared across every per-screen OverlayView.
// Selection must be shared for the same reason the item list is: a marquee drag
// on one display and a delete keystroke while another display's window is key
// must refer to the same selection.
//
// See design.md, "SelectionManager" section.

import Cocoa

// MARK: - SelectionManager

internal final class SelectionManager {

    // MARK: - Properties

    /// The set of identifiers for currently selected items.
    private(set) var selectedIDs: Set<UUID> = []

    /// True when the selection is empty.
    var isEmpty: Bool { selectedIDs.isEmpty }

    // MARK: - Mutation

    /// Returns true if the given identifier is in the selection.
    func contains(_ id: UUID) -> Bool {
        selectedIDs.contains(id)
    }

    /// Replaces the selection with the given set of identifiers.
    func set(_ ids: Set<UUID>) {
        selectedIDs = ids
    }

    /// Toggles an item's membership: adds it if absent, removes it if present.
    /// This implements shift-click symmetric difference (Requirements 2.8, 2.9).
    func toggle(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    /// Adds an identifier to the selection.
    func insert(_ id: UUID) {
        selectedIDs.insert(id)
    }

    /// Removes an identifier from the selection (Requirement 2.14).
    func remove(_ id: UUID) {
        selectedIDs.remove(id)
    }

    /// Clears the selection to zero items (Requirements 2.5, 2.12, 2.13, 10.8).
    func clear() {
        selectedIDs.removeAll()
    }

    // MARK: - Queries

    /// Returns the union of the `bounds` of every selected item. Nil when empty.
    func boundingBox(in items: [any DrawingItem]) -> CGRect? {
        guard !selectedIDs.isEmpty else { return nil }
        var result: CGRect?
        for item in items where selectedIDs.contains(item.id) {
            if let existing = result {
                result = existing.union(item.bounds)
            } else {
                result = item.bounds
            }
        }
        return result
    }

    /// Returns the identifiers of every item whose `bounds` intersect `marquee`.
    /// Requirement 2.7.
    static func itemsIntersecting(_ marquee: CGRect, in items: [any DrawingItem]) -> Set<UUID> {
        var result = Set<UUID>()
        for item in items {
            if item.bounds.intersects(marquee) {
                result.insert(item.id)
            }
        }
        return result
    }

    /// Returns the topmost item whose translated hit-test matches the point.
    /// Iterates in reverse so later items (rendered on top) win.
    /// Requirement 2.4.
    static func topmostHit(at point: CGPoint, threshold: CGFloat, in items: [any DrawingItem]) -> (any DrawingItem)? {
        for item in items.reversed() {
            if item.hitTestTranslated(point: point, threshold: threshold) {
                return item
            }
        }
        return nil
    }
}
