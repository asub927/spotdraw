import Cocoa

/// Operation Property Tests
///
/// These tests verify the operation-stack undo/redo model introduced by
/// DrawingOperation and the reshaped DrawingState (design.md, Decision 1).
///
/// Unlike the preservation tests, which observe undo/redo only through
/// `state.items.count`, these tests compare full identifier sequences and
/// accumulated offsets — the oracle strong enough to catch a `.remove`
/// inverse that reinserts items at the wrong indices while leaving the
/// count untouched.

// MARK: - Reusable operation-sequence generator

/// A single step in a generated operation sequence, paired with enough
/// information for the caller to apply it against a `DrawingState` and
/// know which mutating call to make.
internal enum GeneratedStep {
    /// Add a brand-new item (not drawn from the pool).
    case add(item: any DrawingItem)
    /// Move a random non-empty subset of currently-live item ids by `offset`.
    case move(itemIDs: [UUID], offset: CGSize)
    /// Replace the item at `index` (an index into the *current* live list at
    /// generation time) with a freshly generated replacement item.
    case edit(index: Int, replacement: any DrawingItem)
    /// Remove the item at `index` (an index into the *current* live list at
    /// generation time).
    case remove(index: Int)
}

/// Builds a fresh `FreehandStroke` with coordinates and color derived from `rng`,
/// suitable for use as a generic "some item" in operation-sequence generation.
internal func generateRandomItem(rng: inout SimplePRNG) -> any DrawingItem {
    let x = rng.nextDouble(in: -500...500)
    let y = rng.nextDouble(in: -500...500)
    let colors: [NSColor] = [.systemRed, .systemBlue, .systemGreen, .systemYellow, .white]
    let color = colors[rng.nextInt(in: 0...(colors.count - 1))]
    let lineWidth = CGFloat(rng.nextInt(in: 1...20))
    return FreehandStroke(
        points: [CGPoint(x: x, y: y), CGPoint(x: x + 10, y: y + 10)],
        color: color,
        lineWidth: lineWidth
    )
}

/// Generates a random sequence of `DrawingState`-level mutation steps (add, move,
/// edit, remove) driven by `rng`, simulating against a lightweight in-memory
/// mirror of "currently live ids" so that move/edit/remove steps always target
/// ids that genuinely exist at that point in the sequence.
///
/// This is intentionally reusable: tasks 1.9 (redo invalidation on add) and 7.12
/// (selection staleness) are both expected to drive the same kind of randomized
/// operation sequence against a `DrawingState` and need the same generator.
///
/// - Parameters:
///   - rng: The PRNG driving generation. Threaded through so callers get
///     deterministic, reproducible sequences per-iteration seed.
///   - initialIDs: The ids already present in the `DrawingState` before any
///     step in the returned sequence is applied.
///   - stepCount: How many steps to generate.
/// - Returns: An ordered list of `GeneratedStep`, safe to apply in order against
///   a `DrawingState` that starts with exactly `initialIDs` present, in order.
internal func generateRandomOperationSequence(
    rng: inout SimplePRNG,
    initialIDs: [UUID],
    stepCount: Int
) -> [GeneratedStep] {
    var steps: [GeneratedStep] = []
    // Mirror of "currently live ids, in list order" so generated indices/id
    // subsets always refer to items that exist at that point in the sequence.
    var liveIDs = initialIDs

    for _ in 0..<stepCount {
        // Choose among add / move / edit / remove, but only offer move/edit/remove
        // when there is at least one live item to target.
        let choices: [Int] = liveIDs.isEmpty ? [0] : [0, 1, 2, 3]
        let choice = choices[rng.nextInt(in: 0...(choices.count - 1))]

        switch choice {
        case 0:
            let item = generateRandomItem(rng: &rng)
            steps.append(.add(item: item))
            liveIDs.append(item.id)

        case 1:
            // Move a random non-empty subset of live ids.
            let subsetSize = rng.nextInt(in: 1...liveIDs.count)
            var pool = liveIDs
            var subset: [UUID] = []
            for _ in 0..<subsetSize {
                let idx = rng.nextInt(in: 0...(pool.count - 1))
                subset.append(pool.remove(at: idx))
            }
            let dx = rng.nextDouble(in: -200...200)
            let dy = rng.nextDouble(in: -200...200)
            steps.append(.move(itemIDs: subset, offset: CGSize(width: dx, height: dy)))
            // Move does not change the live id set.

        case 2:
            let index = rng.nextInt(in: 0...(liveIDs.count - 1))
            let replacement = generateRandomItem(rng: &rng)
            steps.append(.edit(index: index, replacement: replacement))
            liveIDs[index] = replacement.id

        default:
            let index = rng.nextInt(in: 0...(liveIDs.count - 1))
            steps.append(.remove(index: index))
            liveIDs.remove(at: index)
        }
    }

    return steps
}

/// Applies a single `GeneratedStep` against `state`, using the same public
/// mutating API a real caller would use (`addItem`, `translate(ids:by:)`,
/// `replaceItem(at:with:)`, `removeItem(at:)`), each of which records exactly
/// one operation on the undo stack.
internal func apply(_ step: GeneratedStep, to state: DrawingState) {
    switch step {
    case .add(let item):
        state.addItem(item)
    case .move(let itemIDs, let offset):
        state.translate(ids: itemIDs, by: offset)
    case .edit(let index, let replacement):
        state.replaceItem(at: index, with: replacement)
    case .remove(let index):
        state.removeItem(at: index)
    }
}

// MARK: - Snapshot helpers

/// A snapshot of the observable, order-sensitive state this property cares
/// about: identifier sequence and each item's accumulated offset, in list order.
private struct StateSnapshot: Equatable {
    let ids: [UUID]
    let offsets: [CGSize]

    init(_ state: DrawingState) {
        ids = state.items.map { $0.id }
        offsets = state.items.map { $0.offset }
    }
}

// MARK: - Property 1: Operation-stack invertibility

/// Feature: annotation-parity-phase-1, Property 1: Operation-stack invertibility
///
/// **Validates: Requirements 3.5, 3.6, 3.8, 1.9, 10.3**
///
/// Property: For any sequence of drawing operations (add, remove, move, edit)
/// applied to any initial item list, undoing every operation in reverse order
/// restores the exact prior state — the same item identifiers in the same
/// order, each with the same accumulated offset.
///
/// This intentionally does NOT compare `state.items.count`. Count equality is
/// too weak an oracle: a `.remove` inverse that reinserts entries in descending
/// index order (rather than the required ascending order) would still leave the
/// count correct while silently corrupting item order. Comparing the full
/// identifier sequence (and offsets) catches that class of bug.
func testOperationStackInvertibility() -> PreservationTestResult {
    return runPreservationTest(
        "Property 1: Operation-stack invertibility (undo restores exact prior state)",
        iterations: 200
    ) { rng in
        let state = DrawingState()

        // Seed an initial item list of random size (0...5 items) so the
        // property also covers starting from empty.
        let initialCount = rng.nextInt(in: 0...5)
        for _ in 0..<initialCount {
            state.addItem(generateRandomItem(rng: &rng))
        }

        // Capture the exact prior state before any of the operations under
        // test are applied. Any adds performed above are "setup", not part
        // of the sequence being tested for invertibility, so we snapshot
        // AFTER setup, undo back to this same point, and compare against it.
        let priorState = StateSnapshot(state)

        // Generate and apply a random sequence of add/move/edit/remove steps.
        let stepCount = rng.nextInt(in: 1...8)
        let steps = generateRandomOperationSequence(
            rng: &rng,
            initialIDs: priorState.ids,
            stepCount: stepCount
        )

        var appliedCount = 0
        for step in steps {
            apply(step, to: state)
            appliedCount += 1
        }

        // Undo every operation just performed, in reverse order (undo()
        // itself pops the stack, so calling it appliedCount times undoes
        // exactly the steps applied above, most-recent-first).
        for _ in 0..<appliedCount {
            state.undo()
        }

        let restoredState = StateSnapshot(state)

        guard restoredState.ids == priorState.ids else {
            return (
                false,
                "After applying \(appliedCount) operations and undoing all of them, "
                    + "item identifier sequence does not match the original. "
                    + "Expected \(priorState.ids), got \(restoredState.ids)."
            )
        }

        // Offsets are compared with a small floating-point tolerance rather than
        // exact equality. `.move`'s undo applies `offset + delta` then
        // `offset - delta`; this is arithmetically an identity but is not
        // guaranteed to be bit-exact for arbitrary Doubles (e.g. round-trips
        // through large-magnitude intermediate sums can leave residue on the
        // order of 1e-14). That is a floating-point precision artifact, not a
        // reordering or logic bug, so an exact `==` here would be too strict an
        // oracle for the property actually under test — the property under test
        // is "restores the same items in the same order with the same offset",
        // not "every Double addition is bit-exact".
        let tolerance = 1e-9
        guard restoredState.offsets.count == priorState.offsets.count else {
            return (
                false,
                "After applying \(appliedCount) operations and undoing all of them, "
                    + "offset count does not match the original. "
                    + "Expected \(priorState.offsets.count) offsets, got \(restoredState.offsets.count)."
            )
        }
        for (expected, actual) in zip(priorState.offsets, restoredState.offsets) {
            let dw = abs(expected.width - actual.width)
            let dh = abs(expected.height - actual.height)
            guard dw <= tolerance && dh <= tolerance else {
                return (
                    false,
                    "After applying \(appliedCount) operations and undoing all of them, "
                        + "accumulated offsets do not match the original within tolerance \(tolerance). "
                        + "Expected \(priorState.offsets), got \(restoredState.offsets)."
                )
            }
        }

        return (true, "")
    }
}

// MARK: - Property 2: Redo invalidation on add

/// Feature: annotation-parity-phase-1, Property 2: Redo invalidation on add
///
/// **Validates: Requirements 10.4**
///
/// Property: For any sequence of operations followed by at least one undo and
/// then an add, a subsequent redo is a no-op: the item list is unchanged.
func testRedoInvalidationOnAdd() -> PreservationTestResult {
    return runPreservationTest(
        "Property 2: Redo invalidation on add (add after undo clears redo)",
        iterations: 200
    ) { rng in
        let state = DrawingState()

        // Seed an initial item list of random size (0...5 items).
        let initialCount = rng.nextInt(in: 0...5)
        for _ in 0..<initialCount {
            state.addItem(generateRandomItem(rng: &rng))
        }

        // Apply a random operation sequence so there is a non-trivial undo
        // stack to work with. Each generated step is guaranteed to target ids
        // that genuinely exist at that point (see generateRandomOperationSequence).
        let liveIDsBeforeSequence = state.items.map { $0.id }
        let stepCount = rng.nextInt(in: 1...8)
        let steps = generateRandomOperationSequence(
            rng: &rng,
            initialIDs: liveIDsBeforeSequence,
            stepCount: stepCount
        )
        for step in steps {
            apply(step, to: state)
        }

        // At least one undo. Guard against an operation sequence that produced
        // zero recorded operations (not possible given stepCount >= 1, but the
        // undo stack could still be empty if, hypothetically, a step recorded
        // nothing) by checking whether items differ after the undo -- absence
        // of a recorded operation would make this a no-op undo, which is still
        // a valid precondition for the property under test (redo should still
        // be a no-op after any subsequent add).
        let undoCount = rng.nextInt(in: 1...max(1, stepCount))
        for _ in 0..<undoCount {
            state.undo()
        }

        // Add a fresh item. This must clear the redo stack regardless of how
        // many undos preceded it.
        let freshItem = generateRandomItem(rng: &rng)
        state.addItem(freshItem)

        let idsBeforeRedo = state.items.map { $0.id }

        // Redo must now be a no-op.
        state.redo()

        let idsAfterRedo = state.items.map { $0.id }

        guard idsAfterRedo == idsBeforeRedo else {
            return (
                false,
                "After \(undoCount) undo(s) followed by an add, redo() changed the item list. "
                    + "Expected \(idsBeforeRedo), got \(idsAfterRedo)."
            )
        }

        return (true, "")
    }
}

// MARK: - Operation Property Test Runner

func runAllOperationPropertyTests() -> [PreservationTestResult] {
    let separator = String(repeating: "=", count: 70)

    print(separator)
    print("Operation Property Tests - Operation-Stack Undo/Redo Model")
    print(separator)
    print("")

    var testResults: [PreservationTestResult] = []

    testResults.append(testOperationStackInvertibility())
    testResults.append(testRedoInvalidationOnAdd())

    print("")
    print(separator)
    print("OPERATION PROPERTY TEST RESULTS SUMMARY")
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
        print("FAILED: \(failed) operation property test(s) failed.")
        print("")
        for result in testResults where !result.passed {
            print("  - \(result.name):")
            print("    \(result.message)")
            print("")
        }
    } else {
        print("All operation property tests PASSED.")
    }

    print("")

    return testResults
}
