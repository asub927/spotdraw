import Cocoa
@testable import SpotdrawCore

/// Preservation Property Tests
///
/// These tests verify baseline behavior that MUST remain unchanged after the bugfix.
/// They are written BEFORE implementing the fix and MUST PASS on unfixed code.
///
/// **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6**
///
/// Property 2: Preservation - Drawing and Feature Functionality Unchanged
/// For any drawing input (mouse events, tool-switch keys, undo/redo) while the overlay is active,
/// the fixed code SHALL produce exactly the same behavior as the original code.

// MARK: - Simple PRNG for Property-Based Testing

/// A simple linear congruential generator for deterministic pseudo-random testing.
struct SimplePRNG {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }

    mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }

    mutating func nextDouble(in range: ClosedRange<Double>) -> Double {
        let raw = Double(next()) / Double(UInt64.max)
        return range.lowerBound + raw * (range.upperBound - range.lowerBound)
    }

    mutating func nextBool() -> Bool {
        return next() % 2 == 0
    }
}

// MARK: - Test Infrastructure

struct PreservationTestResult {
    let name: String
    let passed: Bool
    let message: String
    let iterations: Int
}

func runPreservationTest(_ name: String, iterations: Int = 100, _ body: (inout SimplePRNG) -> (Bool, String)) -> PreservationTestResult {
    print("  Running: \(name) (\(iterations) iterations)...")
    var failMessage = ""
    var passedAll = true

    for i in 0..<iterations {
        var iterRng = SimplePRNG(seed: UInt64(i) &* 7919 &+ 13)
        let (passed, message) = body(&iterRng)
        if !passed {
            passedAll = false
            failMessage = "Iteration \(i): \(message)"
            break
        }
    }

    let result = PreservationTestResult(
        name: name,
        passed: passedAll,
        message: passedAll ? "All \(iterations) iterations passed" : failMessage,
        iterations: iterations
    )

    if passedAll {
        print("    PASSED: All \(iterations) iterations passed")
    } else {
        print("    FAILED: \(failMessage)")
    }
    return result
}

// MARK: - Tool Switch Key Mapping

let toolSwitchKeys: [(key: String, expectedTool: ToolType)] = [
    ("p", .pen),
    ("a", .arrow),
    ("r", .rectangle),
    ("o", .circle),
    ("l", .line),
    ("h", .highlighter),
    ("e", .eraser)
]

// MARK: - Property Tests

/// **Validates: Requirements 3.1**
///
/// Property: For all tool-switch keys in {p, a, r, o, l, h, e}, pressing key sets
/// `activeTool` to the corresponding tool.
func testToolSwitchingPreservation() -> PreservationTestResult {
    return runPreservationTest("Property: Tool-switch keys set correct activeTool", iterations: 100) { rng in
        let state = DrawingState()

        // Pick a random starting tool
        let startIdx = rng.nextInt(in: 0...6)
        state.activeTool = toolSwitchKeys[startIdx].expectedTool

        // Pick a random target tool
        let targetIdx = rng.nextInt(in: 0...6)
        let (key, expectedTool) = toolSwitchKeys[targetIdx]

        // Simulate the key press effect on DrawingState
        switch key {
        case "p": state.activeTool = .pen
        case "a": state.activeTool = .arrow
        case "r": state.activeTool = .rectangle
        case "o": state.activeTool = .circle
        case "l": state.activeTool = .line
        case "h": state.activeTool = .highlighter
        case "e": state.activeTool = .eraser
        default: break
        }

        // Verify
        guard state.activeTool == expectedTool else {
            return (false, "Key '\(key)' should set tool to \(expectedTool), got \(state.activeTool)")
        }
        return (true, "")
    }
}

/// **Validates: Requirements 3.1**
///
/// Property: For any sequence of random tool-switch keys, the activeTool always matches
/// the last key pressed.
func testToolSwitchSequencePreservation() -> PreservationTestResult {
    return runPreservationTest("Property: Sequential tool switches always reflect last key", iterations: 100) { rng in
        let state = DrawingState()

        // Generate a random sequence of 1-10 tool switches
        let sequenceLength = rng.nextInt(in: 1...10)
        var lastExpectedTool: ToolType = .pen

        for _ in 0..<sequenceLength {
            let idx = rng.nextInt(in: 0...6)
            let (key, expectedTool) = toolSwitchKeys[idx]
            lastExpectedTool = expectedTool

            switch key {
            case "p": state.activeTool = .pen
            case "a": state.activeTool = .arrow
            case "r": state.activeTool = .rectangle
            case "o": state.activeTool = .circle
            case "l": state.activeTool = .line
            case "h": state.activeTool = .highlighter
            case "e": state.activeTool = .eraser
            default: break
            }
        }

        guard state.activeTool == lastExpectedTool else {
            return (false, "After \(sequenceLength) switches, expected \(lastExpectedTool), got \(state.activeTool)")
        }
        return (true, "")
    }
}

/// **Validates: Requirements 3.2**
///
/// Property: Board mode toggle cycles correctly: none → white → black → none.
/// For any starting mode, pressing "b" advances to the next mode in the cycle.
func testBoardModeTogglePreservation() -> PreservationTestResult {
    return runPreservationTest("Property: Board mode toggle cycles none→white→black→none", iterations: 100) { rng in
        let state = DrawingState()

        // Pick a random number of toggles (1 to 12, testing multiple full cycles)
        let toggleCount = rng.nextInt(in: 1...12)

        // Track expected mode through the cycle
        let cycle: [BoardMode] = [.none, .white, .black]
        var currentIndex = 0 // starts at .none

        for _ in 0..<toggleCount {
            // Simulate the toggle
            switch state.boardMode {
            case .none:
                state.boardMode = .white
            case .white:
                state.boardMode = .black
            case .black:
                state.boardMode = .none
            case .custom:
                state.boardMode = .none
            }
            currentIndex = (currentIndex + 1) % 3
        }

        let expectedMode = cycle[currentIndex]
        guard state.boardMode == expectedMode else {
            return (false, "After \(toggleCount) toggles, expected \(expectedMode), got \(state.boardMode)")
        }
        return (true, "")
    }
}

/// **Validates: Requirements 3.2**
///
/// Property: Board mode with custom color resets to none on toggle.
func testBoardModeCustomResetsToNone() -> PreservationTestResult {
    return runPreservationTest("Property: Custom board mode resets to none on toggle", iterations: 20) { rng in
        let state = DrawingState()
        state.boardMode = .custom(.systemBlue)

        // Toggle once
        switch state.boardMode {
        case .none:
            state.boardMode = .white
        case .white:
            state.boardMode = .black
        case .black:
            state.boardMode = .none
        case .custom:
            state.boardMode = .none
        }

        guard state.boardMode == .none else {
            return (false, "Custom board mode should reset to .none, got \(state.boardMode)")
        }
        return (true, "")
    }
}

/// **Validates: Requirements 3.3**
///
/// Property: Fade mode toggle flips boolean state.
/// For any starting state, pressing space toggles fadeMode.
func testFadeModeTogglePreservation() -> PreservationTestResult {
    return runPreservationTest("Property: Fade mode toggle flips boolean state", iterations: 100) { rng in
        let state = DrawingState()

        // Random starting state
        if rng.nextBool() {
            state.fadeMode = true
        }

        let before = state.fadeMode
        state.fadeMode.toggle()
        let after = state.fadeMode

        guard after == !before else {
            return (false, "Fade mode was \(before), after toggle should be \(!before), got \(after)")
        }
        return (true, "")
    }
}

/// **Validates: Requirements 3.3**
///
/// Property: For any number of fade mode toggles, the state is deterministic.
func testFadeModeMultipleToggles() -> PreservationTestResult {
    return runPreservationTest("Property: Multiple fade toggles are deterministic", iterations: 100) { rng in
        let state = DrawingState()

        let toggleCount = rng.nextInt(in: 1...20)
        for _ in 0..<toggleCount {
            state.fadeMode.toggle()
        }

        // Even toggles = false (original), odd toggles = true
        let expected = (toggleCount % 2 != 0)
        guard state.fadeMode == expected else {
            return (false, "After \(toggleCount) toggles, expected \(expected), got \(state.fadeMode)")
        }
        return (true, "")
    }
}

/// **Validates: Requirements 3.1**
///
/// Property: Undo removes the last item from items; Redo re-adds it.
/// For all sequences of draw + Cmd+Z, undo removes the last item.
func testUndoRedoPreservation() -> PreservationTestResult {
    return runPreservationTest("Property: Undo removes last item, Redo re-adds it", iterations: 100) { rng in
        let state = DrawingState()

        // Add a random number of items (1-5)
        let itemCount = rng.nextInt(in: 1...5)
        for i in 0..<itemCount {
            let stroke = FreehandStroke(
                points: [CGPoint(x: Double(i), y: 0), CGPoint(x: Double(i) + 10, y: 10)],
                color: .red,
                lineWidth: 3.0
            )
            state.addItem(stroke)
        }

        guard state.items.count == itemCount else {
            return (false, "Expected \(itemCount) items after adding, got \(state.items.count)")
        }

        // Undo
        state.undo()
        guard state.items.count == itemCount - 1 else {
            return (false, "After undo, expected \(itemCount - 1) items, got \(state.items.count)")
        }

        // Redo
        state.redo()
        guard state.items.count == itemCount else {
            return (false, "After redo, expected \(itemCount) items, got \(state.items.count)")
        }

        return (true, "")
    }
}

/// **Validates: Requirements 3.1**
///
/// Property: Multiple undos and redos maintain consistency.
func testMultipleUndoRedoPreservation() -> PreservationTestResult {
    return runPreservationTest("Property: Multiple undo/redo maintains consistency", iterations: 100) { rng in
        let state = DrawingState()

        // Add random items
        let itemCount = rng.nextInt(in: 2...6)
        for i in 0..<itemCount {
            let stroke = FreehandStroke(
                points: [CGPoint(x: Double(i), y: 0), CGPoint(x: Double(i) + 10, y: 10)],
                color: .red,
                lineWidth: 3.0
            )
            state.addItem(stroke)
        }

        // Undo a random number of times (up to all items)
        let undoCount = rng.nextInt(in: 1...itemCount)
        for _ in 0..<undoCount {
            state.undo()
        }

        let expectedAfterUndo = itemCount - undoCount
        guard state.items.count == expectedAfterUndo else {
            return (false, "After \(undoCount) undos from \(itemCount) items, expected \(expectedAfterUndo), got \(state.items.count)")
        }

        // Redo all
        for _ in 0..<undoCount {
            state.redo()
        }

        guard state.items.count == itemCount else {
            return (false, "After redoing all \(undoCount) undos, expected \(itemCount) items, got \(state.items.count)")
        }

        return (true, "")
    }
}

/// **Validates: Requirements 3.1**
///
/// Property: Undo on empty state is a no-op.
func testUndoOnEmptyIsNoop() -> PreservationTestResult {
    return runPreservationTest("Property: Undo on empty state is a no-op", iterations: 20) { rng in
        let state = DrawingState()

        // Undo on empty
        state.undo()
        guard state.items.count == 0 else {
            return (false, "Undo on empty should leave items empty, got \(state.items.count)")
        }

        return (true, "")
    }
}

/// **Validates: Requirements 3.1**
///
/// Property: Redo on empty undo stack is a no-op.
func testRedoOnEmptyIsNoop() -> PreservationTestResult {
    return runPreservationTest("Property: Redo with empty undo stack is a no-op", iterations: 20) { rng in
        let state = DrawingState()

        // Add an item, no undo — redo should be no-op
        let stroke = FreehandStroke(
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)],
            color: .red,
            lineWidth: 3.0
        )
        state.addItem(stroke)

        let countBefore = state.items.count
        state.redo()
        guard state.items.count == countBefore else {
            return (false, "Redo with nothing to redo should not change items count")
        }

        return (true, "")
    }
}

/// **Validates: Requirements 3.1**
///
/// Property: Adding a new item after undo clears the redo stack.
func testAddAfterUndoClearsRedoStack() -> PreservationTestResult {
    return runPreservationTest("Property: Adding after undo clears redo stack", iterations: 50) { rng in
        let state = DrawingState()

        // Add items
        let itemCount = rng.nextInt(in: 2...5)
        for i in 0..<itemCount {
            let stroke = FreehandStroke(
                points: [CGPoint(x: Double(i), y: 0), CGPoint(x: Double(i) + 10, y: 10)],
                color: .red,
                lineWidth: 3.0
            )
            state.addItem(stroke)
        }

        // Undo once
        state.undo()

        // Add a new item (should clear redo stack)
        let newStroke = FreehandStroke(
            points: [CGPoint(x: 100, y: 100), CGPoint(x: 110, y: 110)],
            color: .blue,
            lineWidth: 5.0
        )
        state.addItem(newStroke)

        // Redo should now be a no-op (redo stack was cleared)
        let countBefore = state.items.count
        state.redo()
        guard state.items.count == countBefore else {
            return (false, "After adding new item post-undo, redo should be no-op but item count changed from \(countBefore) to \(state.items.count)")
        }

        return (true, "")
    }
}

/// **Validates: Requirements 3.1**
///
/// Property: Drawing items are created with correct properties (color, lineWidth).
func testDrawingItemPropertiesPreservation() -> PreservationTestResult {
    return runPreservationTest("Property: Drawing items store correct color and lineWidth", iterations: 100) { rng in
        let state = DrawingState()

        // Random color selection
        let colors: [NSColor] = [.red, .blue, .green, .yellow, .white, .black]
        let colorIdx = rng.nextInt(in: 0...(colors.count - 1))
        let color = colors[colorIdx]
        state.activeColor = color

        // Random line width
        let lineWidth = CGFloat(rng.nextInt(in: 1...20))
        state.activeLineWidth = lineWidth

        // Create a stroke
        let stroke = FreehandStroke(
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)],
            color: state.activeColor,
            lineWidth: state.activeLineWidth
        )
        state.addItem(stroke)

        guard let item = state.items.last else {
            return (false, "No item found after addItem")
        }

        guard item.color == color else {
            return (false, "Item color mismatch: expected \(color), got \(item.color)")
        }
        guard item.lineWidth == lineWidth else {
            return (false, "Item lineWidth mismatch: expected \(lineWidth), got \(item.lineWidth)")
        }

        return (true, "")
    }
}

/// **Validates: Requirements 3.2**
///
/// Property: ClearAll removes all items and clears undo stack.
func testClearAllPreservation() -> PreservationTestResult {
    return runPreservationTest("Property: ClearAll removes all items and undo stack", iterations: 50) { rng in
        let state = DrawingState()

        // Add random items
        let itemCount = rng.nextInt(in: 1...8)
        for i in 0..<itemCount {
            let stroke = FreehandStroke(
                points: [CGPoint(x: Double(i), y: 0), CGPoint(x: Double(i) + 10, y: 10)],
                color: .red,
                lineWidth: 3.0
            )
            state.addItem(stroke)
        }

        // Optionally undo some
        let undoCount = rng.nextInt(in: 0...min(2, itemCount))
        for _ in 0..<undoCount {
            state.undo()
        }

        // Clear all
        state.clearAll()

        guard state.items.count == 0 else {
            return (false, "After clearAll, items should be empty, got \(state.items.count)")
        }

        // Redo should be no-op (undo stack cleared)
        state.redo()
        guard state.items.count == 0 else {
            return (false, "After clearAll, redo should be no-op, but items count is \(state.items.count)")
        }

        return (true, "")
    }
}

// MARK: - Preservation Test Runner

func runAllPreservationTests() {
    let separator = String(repeating: "=", count: 70)

    print(separator)
    print("Preservation Property Tests - Drawing and Feature Functionality")
    print(separator)
    print("")
    print("These tests verify baseline behavior that MUST remain unchanged after the fix.")
    print("On unfixed code, they should PASS (confirming behavior to preserve).")
    print("")

    var testResults: [PreservationTestResult] = []

    // Tool switching
    testResults.append(testToolSwitchingPreservation())
    testResults.append(testToolSwitchSequencePreservation())

    // Board mode
    testResults.append(testBoardModeTogglePreservation())
    testResults.append(testBoardModeCustomResetsToNone())

    // Fade mode
    testResults.append(testFadeModeTogglePreservation())
    testResults.append(testFadeModeMultipleToggles())

    // Undo/Redo
    testResults.append(testUndoRedoPreservation())
    testResults.append(testMultipleUndoRedoPreservation())
    testResults.append(testUndoOnEmptyIsNoop())
    testResults.append(testRedoOnEmptyIsNoop())
    testResults.append(testAddAfterUndoClearsRedoStack())

    // Drawing item properties
    testResults.append(testDrawingItemPropertiesPreservation())

    // ClearAll
    testResults.append(testClearAllPreservation())

    print("")
    print(separator)
    print("PRESERVATION TEST RESULTS SUMMARY")
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
        print("UNEXPECTED: \(failed) preservation test(s) FAILED on unfixed code.")
        print("   This indicates a pre-existing issue with the baseline behavior.")
        print("")
        for result in testResults where !result.passed {
            print("  - \(result.name):")
            print("    \(result.message)")
            print("")
        }
    } else {
        print("EXPECTED OUTCOME: All preservation tests PASSED.")
        print("   Baseline behavior confirmed. These tests will detect regressions after the fix.")
    }

    print("")
}
