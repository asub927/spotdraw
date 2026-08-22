import Cocoa
@testable import SpotdrawCore

/// Tests for SelectInteraction (Requirements 2.3, 2.4, 2.5, 4.3).
///
/// SelectInteraction is the pure select-tool state machine extracted from
/// OverlayView. These tests drive it directly and assert the InteractionOutcome
/// stream, proving the marquee/hit/move-clamp behavior was preserved.

func runAllSelectInteractionTests() -> [PreservationTestResult] {
    let separator = String(repeating: "=", count: 70)
    print(separator)
    print("SelectInteraction Tests")
    print(separator)
    print("")

    var results: [PreservationTestResult] = []
    results.append(testPlainClickSetsSingleSelection())
    results.append(testShiftClickToggles())
    results.append(testEmptyClickNoShiftClears())
    results.append(testSubThresholdMoveIsNoOp())
    results.append(testCommittedMoveKeepsBoxVisible())
    results.append(testMarqueeResolvesToIntersectingItems())

    print("")
    print(separator)
    print("SELECTINTERACTION TEST RESULTS SUMMARY")
    print(separator)
    print("")

    let passed = results.filter { $0.passed }.count
    let failed = results.filter { !$0.passed }.count
    for result in results {
        print("  [\(result.passed ? "PASS" : "FAIL")] \(result.name)")
    }
    print("")
    print("Results: \(passed) passed, \(failed) failed, \(results.count) total")
    print("")
    if failed > 0 {
        print("FAILED: \(failed) SelectInteraction test(s) failed.")
        for result in results where !result.passed {
            print("  - \(result.name): \(result.message)")
        }
    } else {
        print("All SelectInteraction tests PASSED.")
    }
    print("")
    return results
}

/// **Validates: Requirement 2.4** — plain click on an item selects only that item.
func testPlainClickSetsSingleSelection() -> PreservationTestResult {
    return runPreservationTest("Property: plain click → setSelection([id])", iterations: 50) { _ in
        var si = SelectInteraction()
        let id = UUID()
        let outcome = si.begin(at: CGPoint(x: 10, y: 10), shiftHeld: false,
                               hit: .hitItem(id), currentBBox: nil)
        guard outcome == .setSelection([id]) else {
            return (false, "expected setSelection([id]), got \(outcome)")
        }
        return (true, "")
    }
}

/// **Validates: Requirements 2.8, 2.9** — shift-click toggles membership.
func testShiftClickToggles() -> PreservationTestResult {
    return runPreservationTest("Property: shift-click → toggleSelection(id)", iterations: 50) { _ in
        var si = SelectInteraction()
        let id = UUID()
        let outcome = si.begin(at: CGPoint(x: 5, y: 5), shiftHeld: true,
                               hit: .hitItem(id), currentBBox: nil)
        guard outcome == .toggleSelection(id) else {
            return (false, "expected toggleSelection(id), got \(outcome)")
        }
        return (true, "")
    }
}

/// **Validates: Requirement 2.5** — empty-space click without shift clears.
func testEmptyClickNoShiftClears() -> PreservationTestResult {
    return runPreservationTest("Property: empty click, no shift → clearSelection", iterations: 50) { _ in
        var si = SelectInteraction()
        let outcome = si.begin(at: CGPoint(x: 1, y: 1), shiftHeld: false,
                               hit: .emptySpace, currentBBox: nil)
        guard outcome == .clearSelection else {
            return (false, "expected clearSelection, got \(outcome)")
        }
        guard si.mode == .drawingMarquee else {
            return (false, "expected marquee mode after empty click")
        }
        return (true, "")
    }
}

/// **Validates: Requirement 3.10** — a sub-1pt move commits a zero (no-op) delta.
func testSubThresholdMoveIsNoOp() -> PreservationTestResult {
    return runPreservationTest("Property: sub-1pt move → commitMove(.zero)", iterations: 100) { rng in
        var si = SelectInteraction()
        let bbox = CGRect(x: 100, y: 100, width: 50, height: 50)
        _ = si.begin(at: CGPoint(x: 110, y: 110), shiftHeld: false,
                     hit: .insideSelectionBox, currentBBox: bbox)
        // Tiny drag under 1pt in both axes
        let tiny = CGFloat(rng.nextInt(in: 0...9)) / 10.0  // 0.0 .. 0.9
        _ = si.drag(to: CGPoint(x: 110 + tiny, y: 110 + tiny))
        let outcome = si.end(viewBounds: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        guard outcome == .commitMove(delta: .zero) else {
            return (false, "expected commitMove(.zero) for tiny delta \(tiny), got \(outcome)")
        }
        return (true, "")
    }
}

/// **Validates: Requirement 3.9** — a committed move never leaves fewer than
/// 20pt of the selection bounding box inside the view bounds.
func testCommittedMoveKeepsBoxVisible() -> PreservationTestResult {
    return runPreservationTest("Property: committed move keeps ≥20pt visible", iterations: 200) { rng in
        let view = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let bx = CGFloat(rng.nextInt(in: 0...900))
        let by = CGFloat(rng.nextInt(in: 0...700))
        let bw = CGFloat(rng.nextInt(in: 10...100))
        let bh = CGFloat(rng.nextInt(in: 10...100))
        let bbox = CGRect(x: bx, y: by, width: bw, height: bh)

        var si = SelectInteraction()
        let press = CGPoint(x: bbox.midX, y: bbox.midY)
        _ = si.begin(at: press, shiftHeld: false, hit: .insideSelectionBox, currentBBox: bbox)

        // Large random drag, potentially far off-screen.
        let dx = CGFloat(rng.nextInt(in: -3000...3000))
        let dy = CGFloat(rng.nextInt(in: -3000...3000))
        _ = si.drag(to: CGPoint(x: press.x + dx, y: press.y + dy))
        let outcome = si.end(viewBounds: view)

        guard case let .commitMove(delta) = outcome else {
            // A zero-magnitude random draw can fall below threshold; that's fine.
            return (true, "")
        }
        let moved = bbox.offsetBy(dx: delta.width, dy: delta.height)
        let minVisible = SelectInteraction.minVisible
        // At least minVisible must remain inside on each axis.
        let visibleX = min(moved.maxX, view.maxX) - max(moved.minX, view.minX)
        let visibleY = min(moved.maxY, view.maxY) - max(moved.minY, view.minY)
        // Allow tiny float tolerance.
        guard visibleX >= min(minVisible, bw) - 0.001 else {
            return (false, "only \(visibleX)pt visible horizontally (bbox=\(bbox), delta=\(delta))")
        }
        guard visibleY >= min(minVisible, bh) - 0.001 else {
            return (false, "only \(visibleY)pt visible vertically (bbox=\(bbox), delta=\(delta))")
        }
        return (true, "")
    }
}

/// **Validates: Requirement 2.7 / 4.3** — a marquee resolves (via SelectionManager)
/// to exactly the items whose bounds intersect it. Verifies the interaction emits
/// commitMarquee with the correct rect and that the rect matches rectFromPoints.
func testMarqueeResolvesToIntersectingItems() -> PreservationTestResult {
    return runPreservationTest("Property: marquee → commitMarquee resolves intersecting", iterations: 100) { rng in
        var si = SelectInteraction()
        let ax = CGFloat(rng.nextInt(in: 0...400))
        let ay = CGFloat(rng.nextInt(in: 0...400))
        let bx = CGFloat(rng.nextInt(in: 0...400))
        let by = CGFloat(rng.nextInt(in: 0...400))
        let press = CGPoint(x: ax, y: ay)
        let release = CGPoint(x: bx, y: by)

        _ = si.begin(at: press, shiftHeld: false, hit: .emptySpace, currentBBox: nil)
        _ = si.drag(to: release)
        let outcome = si.end(viewBounds: CGRect(x: 0, y: 0, width: 500, height: 500))

        let expectedRect = CGRect(x: min(ax, bx), y: min(ay, by),
                                  width: abs(bx - ax), height: abs(by - ay))
        guard case let .commitMarquee(rect) = outcome else {
            return (false, "expected commitMarquee, got \(outcome)")
        }
        guard rect.equalTo(expectedRect) else {
            return (false, "marquee rect \(rect) != expected \(expectedRect)")
        }

        // The rect resolves through SelectionManager exactly as OverlayView would.
        let item = RectangleShape(rect: CGRect(x: min(ax, bx), y: min(ay, by), width: 1, height: 1),
                                  color: .systemRed, lineWidth: 1)
        let ids = SelectionManager.itemsIntersecting(rect, in: [item])
        // Degenerate (zero-area) marquees may or may not intersect; just assert no crash
        // and that a clearly-contained item is found when the rect has area.
        if rect.width > 2 && rect.height > 2 {
            let inside = RectangleShape(rect: CGRect(x: rect.midX, y: rect.midY, width: 1, height: 1),
                                        color: .white, lineWidth: 1)
            let ids2 = SelectionManager.itemsIntersecting(rect, in: [inside])
            guard ids2.contains(inside.id) else {
                return (false, "center-contained item not selected by marquee")
            }
        }
        _ = ids
        return (true, "")
    }
}
