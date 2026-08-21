// DrawingOperation.swift
// A reversible change to the drawing model. DrawingState records one DrawingOperation
// per mutation on its undo stack; undo() and redo() apply the inverse/forward
// transformation described here rather than mutating two parallel item arrays.
//
// See design.md, Decision 1 ("Undo model: operation stack replaces the
// two-array model") for the full rationale and the inverse table this file implements.

import Cocoa

// MARK: - DrawingOperation

/// A reversible change to the drawing model.
public enum DrawingOperation {
    /// An item was appended to the end of the item list.
    case add(item: any DrawingItem)
    /// Items were removed, paired with the indices they occupied before removal.
    case remove(entries: [(index: Int, item: any DrawingItem)])
    /// Items were translated by an offset.
    case move(itemIDs: [UUID], offset: CGSize)
    /// An item was replaced in place, preserving its index.
    case edit(index: Int, before: any DrawingItem, after: any DrawingItem)
}

// MARK: - Inverse application

extension DrawingOperation {

    /// Applies this operation's **undo** direction to `items`.
    ///
    /// | Operation | Undo |
    /// | --- | --- |
    /// | `.add(item)` | remove the last item |
    /// | `.remove(entries)` | reinsert at recorded indices in ascending index order |
    /// | `.move(ids, offset)` | translate each item by the negated offset |
    /// | `.edit(index, before, after)` | replace element at `index` with `before` |
    func undo(applyingTo items: inout [any DrawingItem]) {
        switch self {
        case .add:
            _ = items.popLast()

        case .remove(let entries):
            // CRITICAL: reinsert in ascending index order. Descending reinsertion
            // would place a later-index entry into a list that does not yet
            // contain the earlier-index entries, shifting everything wrong.
            // e.g. entries [(0, a), (2, c)] must insert a at 0 first, then c at 2 —
            // inserting c at 2 first would insert it before a exists at index 0.
            for entry in entries.sorted(by: { $0.index < $1.index }) {
                items.insert(entry.item, at: entry.index)
            }

        case .move(let itemIDs, let offset):
            let negated = CGSize(width: -offset.width, height: -offset.height)
            translate(itemIDs: itemIDs, by: negated, in: &items)

        case .edit(let index, let before, _):
            guard items.indices.contains(index) else { return }
            items[index] = before
        }
    }

    /// Applies this operation's **redo** direction to `items`.
    ///
    /// | Operation | Redo |
    /// | --- | --- |
    /// | `.add(item)` | append `item` |
    /// | `.remove(entries)` | remove those items again |
    /// | `.move(ids, offset)` | translate by the offset |
    /// | `.edit(index, before, after)` | replace with `after` |
    func redo(applyingTo items: inout [any DrawingItem]) {
        switch self {
        case .add(let item):
            items.append(item)

        case .remove(let entries):
            let idsToRemove = Set(entries.map { $0.item.id })
            items.removeAll { idsToRemove.contains($0.id) }

        case .move(let itemIDs, let offset):
            translate(itemIDs: itemIDs, by: offset, in: &items)

        case .edit(let index, _, let after):
            guard items.indices.contains(index) else { return }
            items[index] = after
        }
    }

    /// Translates every item in `items` whose `id` is in `itemIDs` by `delta`.
    ///
    /// Depends on `DrawingItem.translate(by:)` from the `DrawingItem+Transform`
    /// protocol extension (task 1.3), which accumulates `delta` into the item's
    /// `offset`.
    private func translate(itemIDs: [UUID], by delta: CGSize, in items: inout [any DrawingItem]) {
        guard !itemIDs.isEmpty else { return }
        let idSet = Set(itemIDs)
        for item in items where idSet.contains(item.id) {
            item.translate(by: delta)
        }
    }
}
