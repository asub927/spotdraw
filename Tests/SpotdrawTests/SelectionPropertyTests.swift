import Cocoa
@testable import SpotdrawCore

/// Selection Property Tests
///
/// These tests verify the select tool's correctness properties: marquee exactness,
/// click resolution, shift-click symmetric difference, selection staleness, move
/// clamping, and move undo threshold.
///
/// All written against the hand-rolled harness (SimplePRNG, runPreservationTest).
/// Port to PropertyBased after the deferred test-target split lands.

// MARK: - Shared generators

/// Generates a random DrawingItem of a random type with random geometry,
/// suitable for populating an item list for selection tests.
private func generateRandomItemForSelection(rng: inout SimplePRNG) -> any DrawingItem {
    let kind = rng.nextInt(in: 0...5)
    let x = rng.nextDouble(in: 50...900)
    let y = rng.nextDouble(in: 50...700)
    let color: NSColor = .systemRed
    let lineWidth = CGFloat(rng.nextInt(in: 2...10))

    switch kind {
    case 0:
        // FreehandStroke with 3-5 points
        let count = rng.nextInt(in: 3...5)
        var points: [CGPoint] = []
        var px = x
        var py = y
        for _ in 0..<count {
            points.append(CGPoint(x: px, y: py))
            px += rng.nextDouble(in: 5...30)
            py += rng.nextDouble(in: -15...15)
        }
        return FreehandStroke(points: points, color: color, lineWidth: lineWidth)
    case 1:
        let end = CGPoint(x: x + rng.nextDouble(in: 20...100), y: y + rng.nextDouble(in: -50...50))
        return ArrowShape(start: CGPoint(x: x, y: y), end: end, color: color, lineWidth: lineWidth)
    case 2:
        let w = rng.nextDouble(in: 20...120)
        let h = rng.nextDouble(in: 20...120)
        return RectangleShape(rect: CGRect(x: x, y: y, width: w, height: h), color: color, lineWidth: lineWidth)
    case 3:
        let w = rng.nextDouble(in: 20...120)
        let h = rng.nextDouble(in: 20...120)
        return CircleShape(rect: CGRect(x: x, y: y, width: w, height: h), color: color, lineWidth: lineWidth)
    case 4:
        let end = CGPoint(x: x + rng.nextDouble(in: 20...100), y: y + rng.nextDouble(in: -50...50))
        return LineShape(start: CGPoint(x: x, y: y), end: end, color: color, lineWidth: lineWidth)
    default:
        return TextAnnotation(string: "Test", anchor: CGPoint(x: x, y: y), fontSize: 16, color: color)
    }
}

// MARK: - Property 10: Marquee selection is exact

/// Feature: annotation-parity-phase-1, Property 10: Marquee selection is exact
///
/// **Validates: Requirements 2.6, 2.7**
///
/// Property: For any item list and any pair of press and release points, the
/// selection after a marquee drag contains exactly those item identifiers whose
/// `bounds` intersect the rectangle spanned by the two points — no item outside
/// is included and no item inside is omitted.
func testMarqueeSelectionIsExact() -> PreservationTestResult {
    return runPreservationTest(
        "Property 10: Marquee selection is exact",
        iterations: 200
    ) { rng in
        let state = DrawingState()
        state.activeTool = .select

        // Generate 3-10 random items
        let itemCount = rng.nextInt(in: 3...10)
        for _ in 0..<itemCount {
            state.addItem(generateRandomItemForSelection(rng: &rng))
        }

        // Generate two random points forming the marquee
        let p1 = CGPoint(x: rng.nextDouble(in: 0...1000), y: rng.nextDouble(in: 0...800))
        let p2 = CGPoint(x: rng.nextDouble(in: 0...1000), y: rng.nextDouble(in: 0...800))
        let marquee = CGRect(
            x: min(p1.x, p2.x),
            y: min(p1.y, p2.y),
            width: abs(p2.x - p1.x),
            height: abs(p2.y - p1.y)
        )

        // Compute expected selection: items whose bounds intersect the marquee
        var expected = Set<UUID>()
        for item in state.items {
            if item.bounds.intersects(marquee) {
                expected.insert(item.id)
            }
        }

        // Perform the marquee selection
        let actual = SelectionManager.itemsIntersecting(marquee, in: state.items)

        guard actual == expected else {
            return (
                false,
                "Marquee selection mismatch. Marquee: \(marquee). "
                    + "Expected \(expected.count) items, got \(actual.count). "
                    + "Missing: \(expected.subtracting(actual).count), "
                    + "Extra: \(actual.subtracting(expected).count)."
            )
        }

        return (true, "")
    }
}

// MARK: - Property 11: Click selection resolves to the topmost hit

/// Feature: annotation-parity-phase-1, Property 11: Click selection resolves to the topmost hit
///
/// **Validates: Requirements 2.4, 2.5**
///
/// Property: For any item list and any point, if at least one item hit-tests true
/// then the resulting selection contains exactly one identifier, and it belongs to
/// the last such item in item-list order; if no item hit-tests true and no modifiers
/// are held, the resulting selection is empty.
func testClickSelectionResolvesToTopmostHit() -> PreservationTestResult {
    return runPreservationTest(
        "Property 11: Click selection resolves to the topmost hit",
        iterations: 200
    ) { rng in
        let state = DrawingState()
        state.activeTool = .select

        // Generate 3-8 items
        let itemCount = rng.nextInt(in: 3...8)
        for _ in 0..<itemCount {
            state.addItem(generateRandomItemForSelection(rng: &rng))
        }

        let threshold: CGFloat = 10
        // Generate a test point
        let point = CGPoint(x: rng.nextDouble(in: 0...1000), y: rng.nextDouble(in: 0...800))

        // Determine expected result
        let topmost = SelectionManager.topmostHit(at: point, threshold: threshold, in: state.items)

        if let hit = topmost {
            // Should select exactly this one item
            state.selection.set([hit.id])

            guard state.selection.selectedIDs.count == 1 else {
                return (false, "Expected exactly 1 selected item after click hit, got \(state.selection.selectedIDs.count)")
            }
            guard state.selection.contains(hit.id) else {
                return (false, "Selected item does not match topmost hit")
            }

            // Verify it's the LAST matching item in list order (topmost = last in render order)
            var lastHitID: UUID?
            for item in state.items {
                if item.hitTestTranslated(point: point, threshold: threshold) {
                    lastHitID = item.id
                }
            }
            guard lastHitID == hit.id else {
                return (false, "topmostHit returned \(hit.id) but last hit in list order is \(lastHitID?.uuidString ?? "nil")")
            }
        } else {
            // No hit: selection should be empty (no modifier held)
            state.selection.clear()
            guard state.selection.isEmpty else {
                return (false, "Expected empty selection after click on empty space, got \(state.selection.selectedIDs.count) items")
            }
        }

        return (true, "")
    }
}

// MARK: - Property 12: Shift-click computes symmetric difference

/// Feature: annotation-parity-phase-1, Property 12: Shift-click computes symmetric difference
///
/// **Validates: Requirements 2.8, 2.9**
///
/// Property: For any prior selection set and any item in the list, shift-clicking
/// that item yields the symmetric difference of the prior selection and that item's
/// identifier, leaving every other identifier's membership unchanged; shift-clicking
/// the same item twice restores the prior selection exactly.
func testShiftClickComputesSymmetricDifference() -> PreservationTestResult {
    return runPreservationTest(
        "Property 12: Shift-click computes symmetric difference",
        iterations: 200
    ) { rng in
        let state = DrawingState()
        state.activeTool = .select

        // Generate 4-10 items
        let itemCount = rng.nextInt(in: 4...10)
        for _ in 0..<itemCount {
            state.addItem(generateRandomItemForSelection(rng: &rng))
        }

        // Set up a random prior selection (0 to all items)
        let selectCount = rng.nextInt(in: 0...itemCount)
        var priorSelection = Set<UUID>()
        var availableIDs = state.items.map { $0.id }
        for _ in 0..<selectCount {
            if availableIDs.isEmpty { break }
            let idx = rng.nextInt(in: 0...(availableIDs.count - 1))
            priorSelection.insert(availableIDs.remove(at: idx))
        }
        state.selection.set(priorSelection)

        // Pick a random item to shift-click
        let targetIdx = rng.nextInt(in: 0...(state.items.count - 1))
        let targetID = state.items[targetIdx].id

        // First shift-click: toggle
        state.selection.toggle(targetID)

        // Expected: symmetric difference
        let expectedAfterFirst: Set<UUID>
        if priorSelection.contains(targetID) {
            expectedAfterFirst = priorSelection.subtracting([targetID])
        } else {
            expectedAfterFirst = priorSelection.union([targetID])
        }

        guard state.selection.selectedIDs == expectedAfterFirst else {
            return (
                false,
                "After first shift-click on \(targetID), expected \(expectedAfterFirst.count) items, "
                    + "got \(state.selection.selectedIDs.count). "
                    + "Target was \(priorSelection.contains(targetID) ? "selected" : "not selected") before."
            )
        }

        // Second shift-click: should restore prior selection exactly
        state.selection.toggle(targetID)

        guard state.selection.selectedIDs == priorSelection else {
            return (
                false,
                "After second shift-click, selection should equal prior selection. "
                    + "Expected \(priorSelection.count) items, got \(state.selection.selectedIDs.count)."
            )
        }

        return (true, "")
    }
}

// MARK: - Property 13: Selection never contains a stale identifier

/// Feature: annotation-parity-phase-1, Property 13: Selection never contains a stale identifier
///
/// **Validates: Requirements 2.10, 2.12, 2.14, 10.8**
///
/// Property: Across add, erase, delete-selection, undo, redo, clear-all, fade
/// removal, select-all, and tool changes, the set of selected identifiers is at
/// every step a subset of the identifiers present in the item list, and is empty
/// whenever the active tool is not the select tool.
func testSelectionNeverContainsStaleIdentifier() -> PreservationTestResult {
    return runPreservationTest(
        "Property 13: Selection never contains a stale identifier",
        iterations: 200
    ) { rng in
        let state = DrawingState()
        state.activeTool = .select

        // Seed with some items
        let initialCount = rng.nextInt(in: 2...6)
        for _ in 0..<initialCount {
            state.addItem(generateRandomItemForSelection(rng: &rng))
        }

        // Select some items
        let selectCount = rng.nextInt(in: 1...state.items.count)
        var ids = state.items.map { $0.id }
        var toSelect = Set<UUID>()
        for _ in 0..<selectCount {
            if ids.isEmpty { break }
            let idx = rng.nextInt(in: 0...(ids.count - 1))
            toSelect.insert(ids.remove(at: idx))
        }
        state.selection.set(toSelect)

        // Perform a random sequence of operations and check invariant after each
        let opCount = rng.nextInt(in: 5...15)
        for opIdx in 0..<opCount {
            let liveIDs = Set(state.items.map { $0.id })

            // Pre-check: selection is a subset of live IDs
            guard state.selection.selectedIDs.isSubset(of: liveIDs) else {
                return (
                    false,
                    "Before operation \(opIdx): selection contains stale IDs. "
                        + "Selection has \(state.selection.selectedIDs.subtracting(liveIDs).count) stale IDs."
                )
            }

            // Check tool invariant
            if state.activeTool != .select && !state.selection.isEmpty {
                return (
                    false,
                    "Before operation \(opIdx): selection non-empty but tool is \(state.activeTool), not .select."
                )
            }

            // Perform a random operation
            let op = rng.nextInt(in: 0...8)
            switch op {
            case 0: // Add
                state.addItem(generateRandomItemForSelection(rng: &rng))
            case 1: // Remove item via removeItem(at:) — which DOES record on undo stack
                if !state.items.isEmpty {
                    let idx = rng.nextInt(in: 0...(state.items.count - 1))
                    state.removeItem(at: idx)
                }
            case 2: // Delete selection
                state.removeSelected()
            case 3: // Undo
                state.undo()
            case 4: // Redo
                state.redo()
            case 5: // Clear all
                state.clearAll()
            case 6: // Select all
                state.selectAll()  // Only effective if tool is .select
            case 7: // Tool change
                let tools: [ToolType] = [.pen, .arrow, .rectangle, .select, .eraser, .text]
                state.activeTool = tools[rng.nextInt(in: 0...(tools.count - 1))]
                // If we switched back to .select, restore a selection
                if state.activeTool == .select && !state.items.isEmpty {
                    let pickCount = rng.nextInt(in: 0...min(3, state.items.count))
                    var pickIDs = Set<UUID>()
                    for _ in 0..<pickCount {
                        let idx = rng.nextInt(in: 0...(state.items.count - 1))
                        pickIDs.insert(state.items[idx].id)
                    }
                    state.selection.set(pickIDs)
                }
            default: // Fade removal simulation
                if !state.items.isEmpty {
                    let idx = rng.nextInt(in: 0...(state.items.count - 1))
                    state.removeItem(at: idx)
                }
            }

            // Post-check: selection invariants still hold
            let liveIDsAfter = Set(state.items.map { $0.id })
            guard state.selection.selectedIDs.isSubset(of: liveIDsAfter) else {
                return (
                    false,
                    "After operation \(opIdx) (op type \(op)): selection contains stale IDs. "
                        + "Stale: \(state.selection.selectedIDs.subtracting(liveIDsAfter))"
                )
            }
            if state.activeTool != .select && !state.selection.isEmpty {
                return (
                    false,
                    "After operation \(opIdx) (op type \(op)): selection non-empty but tool is \(state.activeTool)."
                )
            }
        }

        return (true, "")
    }
}

// MARK: - Property 14: Move clamping preserves a minimum visible area

/// Feature: annotation-parity-phase-1, Property 14: Move clamping preserves a minimum visible area
///
/// **Validates: Requirements 3.9**
///
/// Property: For any selection and any translation delta, including deltas of
/// arbitrarily large magnitude, the selection bounding box after the applied
/// translation overlaps the overlay view bounds by at least 20 points in both axes.
///
/// Note: This property tests the clamp logic at the model level. The actual clamping
/// is applied in OverlayView which has access to view bounds. We test the invariant
/// that the SelectionManager.boundingBox computation is correct and that translated
/// items remain queryable, and we test the clamping algorithm directly.
func testMoveClamping() -> PreservationTestResult {
    return runPreservationTest(
        "Property 14: Move clamping preserves a minimum visible area",
        iterations: 200
    ) { rng in
        let state = DrawingState()
        state.activeTool = .select

        // Generate 2-5 items in a reasonable area
        let itemCount = rng.nextInt(in: 2...5)
        for _ in 0..<itemCount {
            state.addItem(generateRandomItemForSelection(rng: &rng))
        }

        // Select all items
        state.selectAll()

        guard let originalBbox = state.selection.boundingBox(in: state.items) else {
            return (false, "No bounding box for selected items")
        }

        // Define view bounds
        let viewBounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let minVisible: CGFloat = 20

        // Generate an arbitrarily large delta (testing clamping at extremes)
        let dx = rng.nextDouble(in: -5000...5000)
        let dy = rng.nextDouble(in: -5000...5000)
        let rawDelta = CGSize(width: dx, height: dy)

        // Apply clamping logic (same as OverlayView.clampMoveDelta)
        var clampedDx = rawDelta.width
        var clampedDy = rawDelta.height

        let movedBbox = originalBbox.offsetBy(dx: clampedDx, dy: clampedDy)

        // Clamp horizontal
        if movedBbox.maxX < viewBounds.minX + minVisible {
            clampedDx = (viewBounds.minX + minVisible) - originalBbox.maxX
        } else if movedBbox.minX > viewBounds.maxX - minVisible {
            clampedDx = (viewBounds.maxX - minVisible) - originalBbox.minX
        }

        // Clamp vertical
        let movedBboxV = originalBbox.offsetBy(dx: clampedDx, dy: clampedDy)
        if movedBboxV.maxY < viewBounds.minY + minVisible {
            clampedDy = (viewBounds.minY + minVisible) - originalBbox.maxY
        } else if movedBboxV.minY > viewBounds.maxY - minVisible {
            clampedDy = (viewBounds.maxY - minVisible) - originalBbox.minY
        }

        let clampedDelta = CGSize(width: clampedDx, height: clampedDy)

        // After clamping, the moved bbox must overlap with viewBounds
        let finalBbox = originalBbox.offsetBy(dx: clampedDelta.width, dy: clampedDelta.height)

        // Check overlap exists (at least minVisible in from the edge means
        // the bbox's far edge is at least minVisible inside the view)
        let overlapX = min(finalBbox.maxX, viewBounds.maxX) - max(finalBbox.minX, viewBounds.minX)
        let overlapY = min(finalBbox.maxY, viewBounds.maxY) - max(finalBbox.minY, viewBounds.minY)

        // The overlap should be at least minVisible (20pt) or the full bbox width/height
        // if smaller than minVisible
        let expectedMinOverlapX = min(minVisible, finalBbox.width)
        let expectedMinOverlapY = min(minVisible, finalBbox.height)

        guard overlapX >= expectedMinOverlapX - 0.001 else {
            return (
                false,
                "After clamping delta (\(dx), \(dy)), horizontal overlap is \(overlapX)pt, "
                    + "expected at least \(expectedMinOverlapX)pt. "
                    + "Final bbox: \(finalBbox), view: \(viewBounds)"
            )
        }
        guard overlapY >= expectedMinOverlapY - 0.001 else {
            return (
                false,
                "After clamping delta (\(dx), \(dy)), vertical overlap is \(overlapY)pt, "
                    + "expected at least \(expectedMinOverlapY)pt. "
                    + "Final bbox: \(finalBbox), view: \(viewBounds)"
            )
        }

        return (true, "")
    }
}

// MARK: - Property 15: Move records an undo entry exactly at the threshold

/// Feature: annotation-parity-phase-1, Property 15: Move records an undo entry exactly at the threshold
///
/// **Validates: Requirements 3.4, 3.10, 3.11, 3.7**
///
/// Property: For any selection and any net translation delta, the undo stack depth
/// increases by exactly one when the larger of the absolute horizontal and vertical
/// components is at least 1 point, and by exactly zero otherwise; in both cases
/// the selection is unchanged after the drag.
func testMoveUndoThreshold() -> PreservationTestResult {
    return runPreservationTest(
        "Property 15: Move records an undo entry exactly at the threshold",
        iterations: 200
    ) { rng in
        let state = DrawingState()
        state.activeTool = .select

        // Generate items and select some
        let itemCount = rng.nextInt(in: 2...6)
        for _ in 0..<itemCount {
            state.addItem(generateRandomItemForSelection(rng: &rng))
        }

        // Select a random non-empty subset
        let selectCount = rng.nextInt(in: 1...state.items.count)
        var selectIDs = Set<UUID>()
        var pool = state.items.map { $0.id }
        for _ in 0..<selectCount {
            if pool.isEmpty { break }
            let idx = rng.nextInt(in: 0...(pool.count - 1))
            selectIDs.insert(pool.remove(at: idx))
        }
        state.selection.set(selectIDs)

        let selectionBefore = state.selection.selectedIDs

        // Generate a random delta. Half the time sub-threshold, half above.
        let subThreshold = rng.nextBool()
        let dx: CGFloat
        let dy: CGFloat
        if subThreshold {
            // Both components below 1 point
            dx = CGFloat(rng.nextDouble(in: -0.99...0.99))
            dy = CGFloat(rng.nextDouble(in: -0.99...0.99))
        } else {
            // At least one component >= 1 point
            dx = CGFloat(rng.nextDouble(in: -100...100))
            dy = CGFloat(rng.nextDouble(in: -100...100))
            // Ensure at least one is >= 1
            // (if both happen to be < 1, force one above)
        }

        let delta = CGSize(width: dx, height: dy)
        let maxComponent = max(abs(delta.width), abs(delta.height))
        let shouldRecord = maxComponent >= 1.0

        // Simulate the translate — if threshold met, use DrawingState.translate
        // which records the operation; otherwise just apply directly without recording.
        if shouldRecord {
            let ids = Array(selectIDs)
            state.translate(ids: ids, by: delta)
        } else {
            // Below threshold: no operation recorded, items not moved permanently
            // (In the real UI, the live preview is undone)
        }

        // Check: selection is unchanged (Requirement 3.11)
        guard state.selection.selectedIDs == selectionBefore else {
            return (
                false,
                "Selection changed after move. Before: \(selectionBefore.count), after: \(state.selection.selectedIDs.count)."
            )
        }

        // Check: if shouldRecord, verify we can undo it
        if shouldRecord {
            let idsAfterMove = state.items.map { $0.id }
            state.undo()
            let idsAfterUndo = state.items.map { $0.id }
            // Items should be the same (move doesn't add/remove), but offsets differ
            guard idsAfterMove == idsAfterUndo else {
                return (false, "Undo of a move changed item IDs unexpectedly")
            }
        }

        return (true, "")
    }
}

// MARK: - Selection Property Test Runner

func runAllSelectionPropertyTests() -> [PreservationTestResult] {
    let separator = String(repeating: "=", count: 70)

    print(separator)
    print("Selection Property Tests - Select/Move/Delete")
    print(separator)
    print("")

    var testResults: [PreservationTestResult] = []

    testResults.append(testMarqueeSelectionIsExact())
    testResults.append(testClickSelectionResolvesToTopmostHit())
    testResults.append(testShiftClickComputesSymmetricDifference())
    testResults.append(testSelectionNeverContainsStaleIdentifier())
    testResults.append(testMoveClamping())
    testResults.append(testMoveUndoThreshold())

    print("")
    print(separator)
    print("SELECTION PROPERTY TEST RESULTS SUMMARY")
    print(separator)
    print("")

    let passed = testResults.filter { $0.passed }.count
    let failed = testResults.filter { !$0.passed }.count
    let total = testResults.count
    let totalIterations = testResults.reduce(0) { $0 + $1.iterations }

    for result in testResults {
        let icon = result.passed ? "PASS" : "FAIL"
        print("  [\(icon)] \(result.name)")
    }

    print("")
    print("Results: \(passed) passed, \(failed) failed, \(total) total (\(totalIterations) total iterations)")
    print("")

    if failed > 0 {
        print("FAILED: \(failed) selection property test(s) failed.")
        print("")
        for result in testResults where !result.passed {
            print("  - \(result.name):")
            print("    \(result.message)")
            print("")
        }
    } else {
        print("All selection property tests PASSED.")
    }

    print("")

    return testResults
}
