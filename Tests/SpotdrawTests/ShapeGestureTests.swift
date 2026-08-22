import Cocoa
@testable import SpotdrawCore

/// Tests for ShapeGesture (Requirements 1.2, 1.3, 1.4, 1.5).
///
/// ShapeGesture is the pure value type extracted from OverlayView's shape/freehand
/// mouse handling. These tests exercise it directly — no NSView — proving the
/// geometry rules were preserved exactly during extraction.

func runAllShapeGestureTests() -> [PreservationTestResult] {
    let separator = String(repeating: "=", count: 70)

    print(separator)
    print("ShapeGesture Tests")
    print(separator)
    print("")

    var results: [PreservationTestResult] = []
    results.append(testShiftSquaresRectangleAndCircle())
    results.append(testShiftConstrainsArrowAndLineAngle())
    results.append(testHighlighterCommitWidthAndAlpha())
    results.append(testPenCommitWidthAndAlpha())
    results.append(testMouseUpCommitEqualsDrainCommit())
    results.append(testSinglePointStrokeCommitsToNil())

    print("")
    print(separator)
    print("SHAPEGESTURE TEST RESULTS SUMMARY")
    print(separator)
    print("")

    let passed = results.filter { $0.passed }.count
    let failed = results.filter { !$0.passed }.count
    let total = results.count

    for result in results {
        let icon = result.passed ? "PASS" : "FAIL"
        print("  [\(icon)] \(result.name)")
    }

    print("")
    print("Results: \(passed) passed, \(failed) failed, \(total) total")
    print("")

    if failed > 0 {
        print("FAILED: \(failed) ShapeGesture test(s) failed.")
        for result in results where !result.passed {
            print("  - \(result.name): \(result.message)")
        }
    } else {
        print("All ShapeGesture tests PASSED.")
    }
    print("")
    return results
}

/// **Validates: Requirement 1.2** — shift squares rectangle and circle.
func testShiftSquaresRectangleAndCircle() -> PreservationTestResult {
    return runPreservationTest("Property: shift squares rectangle & circle", iterations: 100) { rng in
        let sx = CGFloat(rng.nextInt(in: 0...500))
        let sy = CGFloat(rng.nextInt(in: 0...500))
        let w = CGFloat(rng.nextInt(in: 1...400))
        let h = CGFloat(rng.nextInt(in: 1...400))
        let start = CGPoint(x: sx, y: sy)
        let end = CGPoint(x: sx + w, y: sy + h)
        let expectedSide = max(w, h)

        for tool in [ToolType.rectangle, .circle] {
            var g = ShapeGesture(tool: tool, startingAt: start)
            g.extend(to: end)
            guard let item = g.commit(shiftHeld: true, color: .systemRed, lineWidth: 3, screenID: CGMainDisplayID()) else {
                return (false, "\(tool) commit returned nil")
            }
            let rect: CGRect
            if let r = item as? RectangleShape { rect = r.rect }
            else if let c = item as? CircleShape { rect = c.rect }
            else { return (false, "\(tool) produced wrong item type") }

            guard abs(rect.width - expectedSide) < 0.001, abs(rect.height - expectedSide) < 0.001 else {
                return (false, "\(tool) not squared: got \(rect.size), expected side \(expectedSide)")
            }
        }
        return (true, "")
    }
}

/// **Validates: Requirement 1.2** — shift applies 45° angle constraint to arrow/line.
func testShiftConstrainsArrowAndLineAngle() -> PreservationTestResult {
    return runPreservationTest("Property: shift angle-constrains arrow & line", iterations: 100) { rng in
        let sx = CGFloat(rng.nextInt(in: 0...400))
        let sy = CGFloat(rng.nextInt(in: 0...400))
        let ex = CGFloat(rng.nextInt(in: 0...400))
        let ey = CGFloat(rng.nextInt(in: 0...400))
        let start = CGPoint(x: sx, y: sy)
        let end = CGPoint(x: ex, y: ey)
        let expectedEnd = DrawingRenderer.constrainToAngles(from: start, to: end)

        for tool in [ToolType.arrow, .line] {
            var g = ShapeGesture(tool: tool, startingAt: start)
            g.extend(to: end)
            guard let item = g.commit(shiftHeld: true, color: .systemBlue, lineWidth: 2, screenID: CGMainDisplayID()) else {
                return (false, "\(tool) commit returned nil")
            }
            let actualEnd: CGPoint
            if let a = item as? ArrowShape { actualEnd = a.end }
            else if let l = item as? LineShape { actualEnd = l.end }
            else { return (false, "\(tool) produced wrong item type") }

            guard abs(actualEnd.x - expectedEnd.x) < 0.001, abs(actualEnd.y - expectedEnd.y) < 0.001 else {
                return (false, "\(tool) end not constrained: got \(actualEnd), expected \(expectedEnd)")
            }
        }
        return (true, "")
    }
}

/// **Validates: Requirement 1.3** — highlighter commits at 4× width and 0.3 alpha.
func testHighlighterCommitWidthAndAlpha() -> PreservationTestResult {
    return runPreservationTest("Property: highlighter commit = 4x width, 0.3 alpha", iterations: 100) { rng in
        let baseWidth = CGFloat(rng.nextInt(in: 1...20))
        var g = ShapeGesture(tool: .highlighter, startingAt: CGPoint(x: 0, y: 0))
        g.extend(to: CGPoint(x: 10, y: 10))
        g.extend(to: CGPoint(x: 20, y: 5))
        guard let stroke = g.commit(shiftHeld: false, color: .systemYellow, lineWidth: baseWidth, screenID: CGMainDisplayID()) as? FreehandStroke else {
            return (false, "highlighter did not produce a FreehandStroke")
        }
        guard abs(stroke.lineWidth - baseWidth * 4) < 0.001 else {
            return (false, "highlighter width \(stroke.lineWidth) != \(baseWidth * 4)")
        }
        guard abs(stroke.alpha - 0.3) < 0.001 else {
            return (false, "highlighter alpha \(stroke.alpha) != 0.3")
        }
        return (true, "")
    }
}

/// **Validates: Requirement 1.3** — pen commits at base width and full alpha.
func testPenCommitWidthAndAlpha() -> PreservationTestResult {
    return runPreservationTest("Property: pen commit = base width, alpha 1.0", iterations: 100) { rng in
        let baseWidth = CGFloat(rng.nextInt(in: 1...20))
        var g = ShapeGesture(tool: .pen, startingAt: CGPoint(x: 0, y: 0))
        g.extend(to: CGPoint(x: 10, y: 10))
        g.extend(to: CGPoint(x: 20, y: 5))
        guard let stroke = g.commit(shiftHeld: false, color: .white, lineWidth: baseWidth, screenID: CGMainDisplayID()) as? FreehandStroke else {
            return (false, "pen did not produce a FreehandStroke")
        }
        guard abs(stroke.lineWidth - baseWidth) < 0.001 else {
            return (false, "pen width \(stroke.lineWidth) != \(baseWidth)")
        }
        guard abs(stroke.alpha - 1.0) < 0.001 else {
            return (false, "pen alpha \(stroke.alpha) != 1.0")
        }
        return (true, "")
    }
}

/// **Validates: Requirement 1.5** — committing after appending the release point
/// (the old mouseUp path) equals committing without it (the old drain path), for
/// shapes, since both read the same start/current. This guards the dedup of
/// mouseUp and commitCurrentDrawing.
func testMouseUpCommitEqualsDrainCommit() -> PreservationTestResult {
    return runPreservationTest("Property: mouseUp-commit == drain-commit (shapes)", iterations: 100) { rng in
        let start = CGPoint(x: CGFloat(rng.nextInt(in: 0...300)), y: CGFloat(rng.nextInt(in: 0...300)))
        let end = CGPoint(x: CGFloat(rng.nextInt(in: 0...300)), y: CGFloat(rng.nextInt(in: 0...300)))
        let shift = rng.nextBool()

        for tool in [ToolType.rectangle, .circle, .arrow, .line] {
            // Drain path: extend only during "drag", commit with points as-is.
            var drain = ShapeGesture(tool: tool, startingAt: start)
            drain.extend(to: end)

            // MouseUp path: same drag, then extend again with the release point
            // (which for shapes equals the last drag point in this scenario).
            var mouseUp = ShapeGesture(tool: tool, startingAt: start)
            mouseUp.extend(to: end)
            mouseUp.extend(to: end)

            let color = NSColor.systemGreen
            let a = drain.commit(shiftHeld: shift, color: color, lineWidth: 3, screenID: CGMainDisplayID())
            let b = mouseUp.commit(shiftHeld: shift, color: color, lineWidth: 3, screenID: CGMainDisplayID())

            guard shapesGeometricallyEqual(a, b) else {
                return (false, "\(tool): drain and mouseUp commits differ")
            }
        }
        return (true, "")
    }
}

/// **Validates: Requirement 1.4** — a freehand gesture with a single point commits to nil.
func testSinglePointStrokeCommitsToNil() -> PreservationTestResult {
    return runPreservationTest("Property: single-point stroke commits to nil", iterations: 20) { _ in
        for tool in [ToolType.pen, .highlighter] {
            let g = ShapeGesture(tool: tool, startingAt: CGPoint(x: 5, y: 5))
            if g.commit(shiftHeld: false, color: .white, lineWidth: 3, screenID: CGMainDisplayID()) != nil {
                return (false, "\(tool) single point should commit to nil")
            }
        }
        return (true, "")
    }
}

/// Compares two committed shape items by their defining geometry.
private func shapesGeometricallyEqual(_ a: (any DrawingItem)?, _ b: (any DrawingItem)?) -> Bool {
    switch (a, b) {
    case let (x as RectangleShape, y as RectangleShape): return x.rect.equalTo(y.rect)
    case let (x as CircleShape, y as CircleShape): return x.rect.equalTo(y.rect)
    case let (x as ArrowShape, y as ArrowShape): return x.start == y.start && x.end == y.end
    case let (x as LineShape, y as LineShape): return x.start == y.start && x.end == y.end
    default: return false
    }
}
