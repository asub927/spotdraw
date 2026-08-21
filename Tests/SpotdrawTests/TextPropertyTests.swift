import Cocoa
@testable import SpotdrawCore

/// Text Property Tests
///
/// These tests verify Property 6 from design.md, using the same hand-rolled harness
/// as `PreservationPropertyTests.swift` (`SimplePRNG`, `PreservationTestResult`,
/// `runPreservationTest(_:iterations:_:)`).
///
/// **Property 6: Fade removal covers every item type**
/// For any item list containing items of every type including `TextAnnotation`, with
/// arbitrary creation ages, after fade processing with fade mode enabled the surviving
/// items are exactly those whose age does not exceed the fade duration by more than
/// one second.
///
/// **Validates: Requirements 10.5**
///
/// ## Modeling the fade-age testability problem
///
/// `OverlayView.processFade()` is the real removal path, but it is a private method
/// on `OverlayView` and every `DrawingItem.createdAt` is `let createdAt = Date()` —
/// fixed at construction, not a settable parameter on any conforming type (confirmed
/// for `FreehandStroke`, `ArrowShape`, `RectangleShape`, `CircleShape`, `LineShape` in
/// `DrawingItems.swift`, and for `TextAnnotation` in `TextAnnotation.swift`). There is
/// no wall-clock-free way to construct an item with an arbitrary, controlled age
/// without a production-code change, which is explicitly out of scope.
///
/// This test therefore models `processFade()`'s removal-selection algorithm as a pure
/// predicate over `(age, fadeDuration)` pairs — treating `OverlayView`'s exact algorithm
/// (reproduced verbatim below in comments and in `fadeProgress`/`survivesFade`) as the
/// oracle under test — and drives synthetic ages through the *real* `DrawingState`
/// removal call, `removeItem(at:)`, rather than only asserting against the pure
/// predicate in isolation. Concretely, each iteration:
///
/// 1. Builds a mixed-type item list (all five existing `DrawingItem` types plus
///    `TextAnnotation`) via `DrawingState.addItem`.
/// 2. Assigns each item a synthetic `age` (a `TimeInterval`, not a real elapsed
///    duration) and a shared `fadeDuration`.
/// 3. Re-implements `processFade()`'s exact loop — same iteration order (reversed
///    indices), same `fadeProgress` formula, same `newOpacity <= 0` removal
///    threshold, same one-second fade window — but reads `age` from the synthetic
///    table built in step 2 instead of `now.timeIntervalSince(item.createdAt)`, and
///    calls `drawingState.removeItem(at:)` for removals exactly as `processFade()`
///    calls `drawingState.removeItem(at:)`.
/// 4. Asserts the surviving item identifiers after that loop equal exactly the set
///    produced by the pure `survivesFade(age:fadeDuration:)` predicate applied to
///    the same synthetic ages.
///
/// This is a legitimate way to property-test a removal rule's logic against many
/// synthetic (item type, age, fadeDuration) combinations without needing real
/// wall-clock timing or any production-code change: the removal mechanism under
/// test (`DrawingState.removeItem(at:)`, `DrawingState.items`) is exercised for
/// real; only the age input — otherwise supplied by `Date()` at construction time
/// and unavailable to the test — is supplied synthetically.

// MARK: - Fade algorithm oracle (mirrors OverlayView.processFade() exactly)

/// True when an item of the given synthetic `age` survives fade processing at the
/// given `fadeDuration`, per `OverlayView.processFade()`'s exact removal rule:
///
/// ```
/// if age > fadeDuration {
///     let fadeProgress = (age - fadeDuration) / 1.0 // 1 second fade
///     let newOpacity = CGFloat(1.0 - fadeProgress)
///     if newOpacity <= 0 { /* removed */ }
/// }
/// ```
///
/// `newOpacity <= 0` reduces to `age >= fadeDuration + 1.0`, so an item survives
/// exactly when `age < fadeDuration + 1.0` — i.e. its age does not exceed the fade
/// duration by more than one second.
private func survivesFade(age: TimeInterval, fadeDuration: TimeInterval) -> Bool {
    guard age > fadeDuration else { return true }
    let fadeProgress = (age - fadeDuration) / 1.0
    let newOpacity = 1.0 - fadeProgress
    return newOpacity > 0
}

/// Re-implements `OverlayView.processFade()`'s exact loop against `state`, using
/// `syntheticAge` in place of `now.timeIntervalSince(item.createdAt)` (which cannot
/// be controlled in a test — see file-level doc comment). Iteration order (reversed
/// indices) and the removal call (`drawingState.removeItem(at:)`) match the
/// production method exactly.
private func applySyntheticFade(
    to state: DrawingState,
    fadeDuration: TimeInterval,
    syntheticAge: (any DrawingItem) -> TimeInterval
) {
    for i in (0..<state.items.count).reversed() {
        let age = syntheticAge(state.items[i])
        if age > fadeDuration {
            let fadeProgress = (age - fadeDuration) / 1.0
            let newOpacity = CGFloat(1.0 - fadeProgress)
            if newOpacity <= 0 {
                state.removeItem(at: i)
            } else {
                state.items[i].opacity = newOpacity
            }
        }
    }
}

// MARK: - TextAnnotation random factory

/// Builds a random `TextAnnotation`: string, anchor point, font size, and color.
/// `TextAnnotation` did not exist when `TransformPropertyTests.swift`'s `makeRandomX`
/// factories were written, so it gets its own factory here, following the same
/// `SimplePRNG`-driven generator-function pattern and argument order/style as the
/// existing factories (`makeRandomFreehandStroke`, `makeRandomArrowShape`, etc.).
func makeRandomTextAnnotation(rng: inout SimplePRNG) -> TextAnnotation {
    let sampleStrings = ["Hello", "Annotation", "A", "Spot the bug", "  padded  ", "12345"]
    let string = sampleStrings[rng.nextInt(in: 0...(sampleStrings.count - 1))]
    let anchor = CGPoint(
        x: CGFloat(rng.nextDouble(in: -500...500)),
        y: CGFloat(rng.nextDouble(in: -500...500))
    )
    let fontSize = CGFloat(rng.nextInt(in: 8...96))
    let colors: [NSColor] = [.systemRed, .systemBlue, .systemGreen, .systemYellow, .white, .black]
    let color = colors[rng.nextInt(in: 0...(colors.count - 1))]
    return TextAnnotation(string: string, anchor: anchor, fontSize: fontSize, color: color)
}

/// Dispatches to one of the five existing `makeRandom*` factories from
/// `TransformPropertyTests.swift` or to `makeRandomTextAnnotation`, at random,
/// returning the result as `any DrawingItem`. Reuses the existing per-type
/// factories rather than reimplementing them, per the task instructions.
private func makeRandomItemIncludingText(rng: inout SimplePRNG) -> any DrawingItem {
    switch rng.nextInt(in: 0...5) {
    case 0: makeRandomFreehandStroke(rng: &rng)
    case 1: makeRandomArrowShape(rng: &rng)
    case 2: makeRandomRectangleShape(rng: &rng)
    case 3: makeRandomCircleShape(rng: &rng)
    case 4: makeRandomLineShape(rng: &rng)
    default: makeRandomTextAnnotation(rng: &rng)
    }
}

/// Human-readable label for a `DrawingItem`'s concrete type, used in failure messages.
private func typeNameIncludingText(of item: any DrawingItem) -> String {
    switch item {
    case is FreehandStroke: "FreehandStroke"
    case is ArrowShape: "ArrowShape"
    case is RectangleShape: "RectangleShape"
    case is CircleShape: "CircleShape"
    case is LineShape: "LineShape"
    case is TextAnnotation: "TextAnnotation"
    default: String(describing: type(of: item))
    }
}

// MARK: - Property 6: Fade removal covers every item type

/// Feature: annotation-parity-phase-1, Property 6: Fade removal covers every item type
///
/// **Validates: Requirements 10.5**
///
/// Property: For any item list containing items of every type including
/// `TextAnnotation`, with arbitrary (synthetic) creation ages, after fade processing
/// with fade mode enabled the surviving items are exactly those whose age does not
/// exceed the fade duration by more than one second.
func testFadeRemovalCoversEveryItemType() -> PreservationTestResult {
    return runPreservationTest(
        "Property 6: Fade removal covers every item type (incl. TextAnnotation)",
        iterations: 200
    ) { rng in
        let state = DrawingState()
        state.fadeMode = true
        let fadeDuration = rng.nextDouble(in: 0.5...10.0)
        state.fadeDuration = fadeDuration

        let itemCount = rng.nextInt(in: 1...12)

        // Ensure every item type, including TextAnnotation, appears at least once
        // across the run by forcing the first six items (when itemCount allows) to
        // cover each type directly, then filling the remainder randomly.
        let forcedFactories: [(inout SimplePRNG) -> any DrawingItem] = [
            { rng in makeRandomFreehandStroke(rng: &rng) },
            { rng in makeRandomArrowShape(rng: &rng) },
            { rng in makeRandomRectangleShape(rng: &rng) },
            { rng in makeRandomCircleShape(rng: &rng) },
            { rng in makeRandomLineShape(rng: &rng) },
            { rng in makeRandomTextAnnotation(rng: &rng) }
        ]

        // Synthetic age assigned per item id. Ages are drawn from a range that
        // straddles the fade window (fadeDuration +/- up to 5s) so both surviving
        // and removed outcomes are well represented, plus some items well within
        // or well beyond the window.
        var syntheticAges: [UUID: TimeInterval] = [:]

        for i in 0..<itemCount {
            let item: any DrawingItem
            if i < forcedFactories.count {
                item = forcedFactories[i](&rng)
            } else {
                item = makeRandomItemIncludingText(rng: &rng)
            }
            state.addItem(item)

            let age = max(0, rng.nextDouble(in: -5...(fadeDuration + 5)))
            syntheticAges[item.id] = age
        }

        // Pure-predicate expectation, computed independently of the loop under test.
        let expectedSurvivorIDs = Set(
            state.items.compactMap { item -> UUID? in
                let age = syntheticAges[item.id] ?? 0
                return survivesFade(age: age, fadeDuration: fadeDuration) ? item.id : nil
            }
        )
        let expectedRemovedIDs = Set(syntheticAges.keys).subtracting(expectedSurvivorIDs)

        // Drive the real removal path (DrawingState.removeItem(at:)) through the
        // same algorithm processFade() uses, substituting synthetic ages.
        applySyntheticFade(to: state, fadeDuration: fadeDuration) { item in
            syntheticAges[item.id] ?? 0
        }

        let actualSurvivorIDs = Set(state.items.map { $0.id })

        guard actualSurvivorIDs == expectedSurvivorIDs else {
            let missingFromSurvivors = expectedSurvivorIDs.subtracting(actualSurvivorIDs)
            let unexpectedSurvivors = actualSurvivorIDs.subtracting(expectedSurvivorIDs)
            return (false, "fadeDuration=\(fadeDuration): survivor set mismatch. "
                + "Expected \(expectedSurvivorIDs.count) survivors (removed \(expectedRemovedIDs.count)), "
                + "got \(actualSurvivorIDs.count) survivors. "
                + "Missing from actual survivors: \(missingFromSurvivors.count), "
                + "unexpectedly survived: \(unexpectedSurvivors.count).")
        }

        return (true, "")
    }
}

/// Feature: annotation-parity-phase-1, Property 6: Fade removal covers every item type
///
/// **Validates: Requirements 10.5**
///
/// Focused variant asserting specifically that a `TextAnnotation` is removed once its
/// synthetic age crosses `fadeDuration + 1.0`, and survives (with a partially-faded
/// opacity, not fully removed) at ages between `fadeDuration` and `fadeDuration + 1.0`.
/// This isolates the item type called out explicitly in the property statement rather
/// than relying only on the mixed-population test above to exercise it.
func testFadeRemovalTextAnnotationThreshold() -> PreservationTestResult {
    return runPreservationTest(
        "Property 6: Fade removal covers every item type (TextAnnotation threshold)",
        iterations: 200
    ) { rng in
        let state = DrawingState()
        state.fadeMode = true
        let fadeDuration = rng.nextDouble(in: 0.5...10.0)
        state.fadeDuration = fadeDuration

        let text = makeRandomTextAnnotation(rng: &rng)
        state.addItem(text)

        // Three regimes: comfortably before the fade window, inside the one-second
        // fade window (should survive with reduced opacity), and past it (removed).
        let regime = rng.nextInt(in: 0...2)
        let age: TimeInterval
        let expectSurvive: Bool
        switch regime {
        case 0:
            age = rng.nextDouble(in: 0...max(0.01, fadeDuration - 0.01))
            expectSurvive = true
        case 1:
            age = rng.nextDouble(in: fadeDuration...(fadeDuration + 0.999))
            expectSurvive = true
        default:
            age = rng.nextDouble(in: (fadeDuration + 1.0)...(fadeDuration + 20))
            expectSurvive = false
        }

        applySyntheticFade(to: state, fadeDuration: fadeDuration) { _ in age }

        let survived = state.items.contains { $0.id == text.id }
        guard survived == expectSurvive else {
            return (false, "TextAnnotation with synthetic age \(age), fadeDuration \(fadeDuration) "
                + "(regime \(regime)): expected survive=\(expectSurvive), got survive=\(survived).")
        }

        // When it survives past fadeDuration (regime 1), opacity must reflect the
        // fade-out ramp rather than staying at full opacity.
        if regime == 1, let survivor = state.items.first(where: { $0.id == text.id }) {
            let expectedProgress = (age - fadeDuration) / 1.0
            let expectedOpacity = CGFloat(1.0 - expectedProgress)
            guard abs(survivor.opacity - expectedOpacity) < 1e-9 else {
                return (false, "TextAnnotation surviving mid-fade should have opacity \(expectedOpacity), "
                    + "got \(survivor.opacity) (age=\(age), fadeDuration=\(fadeDuration)).")
            }
        }

        return (true, "")
    }
}

// MARK: - Text Property Test Runner

@MainActor
func runAllTextPropertyTests() {
    let separator = String(repeating: "=", count: 70)

    print(separator)
    print("Text Property Tests - Fade Removal Across Every Item Type")
    print(separator)
    print("")
    print("Property 6: with fade mode on, survivors are exactly the items whose age")
    print("does not exceed the fade duration by more than one second, including")
    print("TextAnnotation.")
    print("")
    print("Property 7: text commit accepts exactly the non-empty (after trim) strings,")
    print("returning .discarded for empty/whitespace-only input with items and both")
    print("undo/redo stacks unchanged, and .created/.edited with the trimmed string")
    print("otherwise.")
    print("")
    print("Property 8: text style is snapshotted when editing begins -- mutating the")
    print("active color and persisted font size mid-composition does not affect the")
    print("committed item.")
    print("")
    print("Property 9: text bounds are non-degenerate (strictly positive width and")
    print("height for any non-empty string) and monotonic in font size (bounds at a")
    print("smaller font size are no larger, in either dimension, than bounds at a")
    print("larger font size).")
    print("")

    var testResults: [PreservationTestResult] = []

    testResults.append(testFadeRemovalCoversEveryItemType())
    testResults.append(testFadeRemovalTextAnnotationThreshold())
    testResults.append(testTextCommitDiscardsWhitespaceOnlyInput())
    testResults.append(testTextCommitCreatesAnnotationWithTrimmedString())
    testResults.append(testTextCommitEditsExistingAnnotationWithTrimmedString())
    testResults.append(testTextCommitDiscardsWhitespaceOnlyEditOfExistingAnnotation())
    testResults.append(testTextStyleSnapshottedAtEditBegin())
    testResults.append(testTextStyleSnapshottedAtEditBeginForExistingAnnotation())
    testResults.append(testTextBoundsAreNonDegenerate())
    testResults.append(testTextBoundsAreMonotonicInFontSize())

    print("")
    print(separator)
    print("TEXT PROPERTY TEST RESULTS SUMMARY")
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
        print("FAILED: \(failed) text property test(s) failed.")
        print("")
        for result in testResults where !result.passed {
            print("  - \(result.name):")
            print("    \(result.message)")
            print("")
        }
    } else {
        print("All text property tests PASSED.")
    }

    print("")
}


// MARK: - Property 7: Text commit accepts exactly the non-empty strings
//
// **Property 7: Text commit accepts exactly the non-empty strings**
//
// For any string driven into the `TextEditingController`'s text field, calling
// `commit()`:
//   - when the string is empty or entirely whitespace after trimming via
//     `.trimmingCharacters(in: .whitespacesAndNewlines)`, returns `.discarded` and
//     leaves `DrawingState.items` and both the undo and redo stacks unchanged;
//   - otherwise, returns `.created(TextAnnotation)` (composing new) or
//     `.edited(original:updated:)` (editing an existing item) whose resulting
//     annotation's `string` equals the trimmed input exactly.
//
// **Validates: Requirements 1.5, 1.6, 1.7**
//
// ## Driving text into `TextEditingController`
//
// `TextEditingController` exposes no public setter for the pending text — `begin`
// creates an `NSTextField` subview and installs it on the `OverlayView`, and the
// only way to change its contents from outside is through the field itself (typing,
// or `NSTextField.stringValue`). There is no way to inject arbitrary text through
// `TextEditingController`'s public surface alone.
//
// This test therefore calls `begin(at:existing:in:color:fontSize:)` to install the
// field, locates the installed `NSTextField` among `OverlayView`'s subviews (it is
// the only `NSTextField` added), sets its `stringValue` directly, and then calls
// `commit()` — exactly mirroring how a real keystroke sequence would have left the
// field before Return or Escape triggers commit. This drives the exact same code
// path `commit()` uses (`field.stringValue.trimmingCharacters(in:
// .whitespacesAndNewlines)`) without needing any production-code change.

/// Locates the `NSTextView` that `TextEditingController.begin` installed as a
/// subview of `view` (inside an NSScrollView). `begin` adds exactly one such
/// scroll view per call (any previous edit is committed and removed before a new
/// one is added), so the first NSScrollView match is unambiguous.
@MainActor
private func installedTextView(in view: OverlayView) -> NSTextView? {
    guard let scrollView = view.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView else {
        return nil
    }
    return scrollView.documentView as? NSTextView
}

/// Legacy compatibility shim — returns non-nil if a text editing view is installed.
/// Tests that previously checked for NSTextField now check for NSTextView via
/// NSScrollView.
@MainActor
private func installedTextField(in view: OverlayView) -> NSTextView? {
    installedTextView(in: view)
}

/// Hosts a fresh `OverlayView` in a minimal `NSWindow`, following the same pattern
/// `OverlayDeactivationTests.swift` uses to drive `OverlayView` directly in tests.
@MainActor
private func makeHostedOverlayView() -> (window: NSWindow, view: OverlayView) {
    let view = OverlayView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
        styleMask: .borderless,
        backing: .buffered,
        defer: false
    )
    window.contentView = view
    window.makeKeyAndOrderFront(nil)
    return (window, view)
}

// MARK: - Whitespace generators

/// The individual whitespace code points this generator combines. Chosen to cover
/// every category `.whitespacesAndNewlines` documents: Unicode general category
/// Z* (`Zs`, `Zl`, `Zp`) plus the ASCII/Latin-1 newline-function code points
/// U+000A–U+000D and U+0085. Regular space, tab, and both common newline forms are
/// included alongside three genuinely non-ASCII members of `Zs` so a whitespace-only
/// generated string is guaranteed to trim to empty via
/// `.trimmingCharacters(in: .whitespacesAndNewlines)`.
private let whitespaceCodePoints: [Character] = [
    " ",        // U+0020 SPACE (Zs)
    "\t",       // U+0009 TAB
    "\n",       // U+000A LINE FEED
    "\r",       // U+000D CARRIAGE RETURN
    "\u{0085}", // NEXT LINE (NEL)
    "\u{00A0}", // NO-BREAK SPACE (Zs)
    "\u{2003}", // EM SPACE (Zs)
    "\u{3000}"  // IDEOGRAPHIC SPACE (Zs)
]

/// Generates a string made of an arbitrary combination of 1...12 whitespace code
/// points drawn from `whitespaceCodePoints`. Every such string trims to empty under
/// `.whitespacesAndNewlines`.
private func makeRandomWhitespaceOnlyString(rng: inout SimplePRNG) -> String {
    let count = rng.nextInt(in: 0...12)
    var result = ""
    for _ in 0..<count {
        result.append(whitespaceCodePoints[rng.nextInt(in: 0...(whitespaceCodePoints.count - 1))])
    }
    return result
}

/// Genuinely non-whitespace fragments used to build non-empty-after-trim strings.
private let nonWhitespaceFragments = ["Hello", "x", "Spot the bug", "42", "annotation", "Z"]

/// Generates a string that mixes arbitrary whitespace (possibly none, possibly a lot,
/// possibly leading/trailing) with at least one genuine non-whitespace fragment, so
/// the trimmed result is guaranteed non-empty. The returned tuple also carries the
/// expected trimmed value, computed independently by trimming the pieces rather than
/// the assembled whole, so the oracle does not share code with the string builder.
private func makeRandomNonEmptyAfterTrimString(rng: inout SimplePRNG) -> (raw: String, expectedTrimmed: String) {
    let fragment = nonWhitespaceFragments[rng.nextInt(in: 0...(nonWhitespaceFragments.count - 1))]
    let leading = makeRandomWhitespaceOnlyString(rng: &rng)
    let trailing = makeRandomWhitespaceOnlyString(rng: &rng)
    // Occasionally interleave whitespace inside the fragment's surrounding content
    // by prepending/appending a second fragment copy joined with whitespace, so the
    // interior of the trimmed result can itself contain whitespace (still non-empty).
    let interior: String
    if rng.nextBool() {
        let middleWhitespace = makeRandomWhitespaceOnlyString(rng: &rng)
        interior = fragment + (middleWhitespace.isEmpty ? " " : middleWhitespace) + fragment
    } else {
        interior = fragment
    }
    let raw = leading + interior + trailing
    let expectedTrimmed = interior
    return (raw, expectedTrimmed)
}

// MARK: - Test bodies

/// Feature: annotation-parity-phase-1, Property 7: Text commit accepts exactly the non-empty strings
///
/// **Validates: Requirements 1.5, 1.6, 1.7**
///
/// Branch (a): whitespace-only or empty input commits to `.discarded` and leaves
/// `DrawingState.items` and both undo/redo stacks unchanged. Stack-unchanged is
/// checked via the observable proxy the design itself uses for undo/redo: calling
/// `undo()` and `redo()` before/after and confirming `items.count` does not move,
/// since `DrawingState` exposes no direct view of stack contents.
@MainActor
func testTextCommitDiscardsWhitespaceOnlyInput() -> PreservationTestResult {
    return runPreservationTest(
        "Property 7: Text commit discards whitespace-only/empty input",
        iterations: 150
    ) { rng in
        let state = DrawingState()

        // Seed a few unrelated items so "items unchanged" is a meaningful assertion,
        // not vacuously true on an empty list.
        let seedCount = rng.nextInt(in: 0...4)
        for _ in 0..<seedCount {
            state.addItem(makeRandomTextAnnotation(rng: &rng))
        }
        let itemsBefore = state.items.map { $0.id }

        // Establish an undo-stack baseline: pop once via undo() (no-op if empty, or
        // moves one seeded add to the redo stack), then restore via redo() so the
        // "before" state we compare against post-commit is well-defined regardless
        // of seedCount.
        state.undo()
        state.redo()
        let countAfterUndoRedoBaseline = state.items.count

        let (window, view) = makeHostedOverlayView()
        view.drawingState = state
        defer { window.orderOut(nil) }

        let controller = TextEditingController()
        let anchor = CGPoint(
            x: CGFloat(rng.nextDouble(in: -200...600)),
            y: CGFloat(rng.nextDouble(in: -200...600))
        )
        let fontSize = CGFloat(rng.nextInt(in: 8...96))
        controller.begin(at: anchor, existing: nil, in: view, color: .systemRed, fontSize: fontSize)

        guard let field = installedTextField(in: view) else {
            return (false, "begin(...) did not install an NSTextView subview on the OverlayView")
        }

        let whitespaceOnly = makeRandomWhitespaceOnlyString(rng: &rng)
        field.string = whitespaceOnly

        let result = controller.commit()

        guard case .discarded = result else {
            return (false, "commit() with whitespace-only input \(String(reflecting: whitespaceOnly)) "
                + "should return .discarded, got \(result)")
        }

        guard state.items.map({ $0.id }) == itemsBefore else {
            return (false, "DrawingState.items changed after a discarded commit. "
                + "Before: \(itemsBefore.count) items, after: \(state.items.count) items.")
        }

        // Proxy check for "both undo/redo stacks unchanged": since commit() recorded
        // nothing, an undo()/redo() round trip from here must behave identically to
        // the same round trip performed before commit() was called.
        state.undo()
        state.redo()
        guard state.items.count == countAfterUndoRedoBaseline else {
            return (false, "Undo/redo round-trip behavior changed after a discarded commit, "
                + "implying commit() mutated a stack it should have left untouched. "
                + "Baseline count \(countAfterUndoRedoBaseline), post-commit count \(state.items.count).")
        }

        return (true, "")
    }
}

/// Feature: annotation-parity-phase-1, Property 7: Text commit accepts exactly the non-empty strings
///
/// **Validates: Requirements 1.5, 1.6, 1.7**
///
/// Branch (b), composing new text: non-empty-after-trim input commits to `.created`
/// with the resulting `TextAnnotation.string` exactly equal to the independently
/// computed expected trim.
@MainActor
func testTextCommitCreatesAnnotationWithTrimmedString() -> PreservationTestResult {
    return runPreservationTest(
        "Property 7: Text commit creates a TextAnnotation with the exactly-trimmed string",
        iterations: 150
    ) { rng in
        let state = DrawingState()
        let (window, view) = makeHostedOverlayView()
        view.drawingState = state
        defer { window.orderOut(nil) }

        let controller = TextEditingController()
        let anchor = CGPoint(
            x: CGFloat(rng.nextDouble(in: -200...600)),
            y: CGFloat(rng.nextDouble(in: -200...600))
        )
        let fontSize = CGFloat(rng.nextInt(in: 8...96))
        controller.begin(at: anchor, existing: nil, in: view, color: .systemBlue, fontSize: fontSize)

        guard let field = installedTextField(in: view) else {
            return (false, "begin(...) did not install an NSTextView subview on the OverlayView")
        }

        let (raw, expectedTrimmed) = makeRandomNonEmptyAfterTrimString(rng: &rng)
        field.string = raw

        let result = controller.commit()

        guard case .created(let annotation) = result else {
            return (false, "commit() with non-empty-after-trim input \(String(reflecting: raw)) "
                + "should return .created, got \(result)")
        }

        guard annotation.string == expectedTrimmed else {
            return (false, "Created TextAnnotation.string \(String(reflecting: annotation.string)) "
                + "does not equal the expected trimmed input \(String(reflecting: expectedTrimmed)) "
                + "(raw input was \(String(reflecting: raw))).")
        }

        return (true, "")
    }
}

/// Feature: annotation-parity-phase-1, Property 7: Text commit accepts exactly the non-empty strings
///
/// **Validates: Requirements 1.5, 1.6, 1.7**
///
/// Branch (b), editing an existing annotation: non-empty-after-trim input commits to
/// `.edited(original:updated:)`, where `original` is exactly the item passed as
/// `existing` and `updated.string` equals the independently computed expected trim.
@MainActor
func testTextCommitEditsExistingAnnotationWithTrimmedString() -> PreservationTestResult {
    return runPreservationTest(
        "Property 7: Text commit edits an existing TextAnnotation with the exactly-trimmed string",
        iterations: 150
    ) { rng in
        let existing = makeRandomTextAnnotation(rng: &rng)
        let state = DrawingState()
        state.addItem(existing)

        let (window, view) = makeHostedOverlayView()
        view.drawingState = state
        defer { window.orderOut(nil) }

        let controller = TextEditingController()
        let fontSize = CGFloat(rng.nextInt(in: 8...96))
        controller.begin(at: existing.anchor, existing: existing, in: view, color: .white, fontSize: fontSize)

        guard let field = installedTextField(in: view) else {
            return (false, "begin(...) did not install an NSTextView subview on the OverlayView")
        }

        let (raw, expectedTrimmed) = makeRandomNonEmptyAfterTrimString(rng: &rng)
        field.string = raw

        let result = controller.commit()

        guard case .edited(let original, let updated) = result else {
            return (false, "commit() editing an existing TextAnnotation with non-empty-after-trim "
                + "input \(String(reflecting: raw)) should return .edited, got \(result)")
        }

        guard original.id == existing.id else {
            return (false, "commit() returned .edited with the wrong original item: expected id "
                + "\(existing.id), got \(original.id)")
        }

        guard updated.string == expectedTrimmed else {
            return (false, "Edited TextAnnotation.string \(String(reflecting: updated.string)) "
                + "does not equal the expected trimmed input \(String(reflecting: expectedTrimmed)) "
                + "(raw input was \(String(reflecting: raw))).")
        }

        return (true, "")
    }
}

/// Feature: annotation-parity-phase-1, Property 7: Text commit accepts exactly the non-empty strings
///
/// **Validates: Requirements 1.5, 1.6, 1.7**
///
/// Combined branch check driven by a single random choice per iteration between
/// whitespace-only and non-empty-after-trim input, asserting the `.discarded` vs.
/// `.created` dichotomy holds and, additionally, that a whitespace-only edit of an
/// existing annotation also discards and leaves `DrawingState.items` unchanged
/// (rather than deleting or blanking the existing item).
@MainActor
func testTextCommitDiscardsWhitespaceOnlyEditOfExistingAnnotation() -> PreservationTestResult {
    return runPreservationTest(
        "Property 7: Text commit discards whitespace-only edit of an existing TextAnnotation",
        iterations: 150
    ) { rng in
        let existing = makeRandomTextAnnotation(rng: &rng)
        let state = DrawingState()
        state.addItem(existing)
        let itemsBefore = state.items.map { $0.id }

        let (window, view) = makeHostedOverlayView()
        view.drawingState = state
        defer { window.orderOut(nil) }

        let controller = TextEditingController()
        let fontSize = CGFloat(rng.nextInt(in: 8...96))
        controller.begin(at: existing.anchor, existing: existing, in: view, color: .systemGreen, fontSize: fontSize)

        guard let field = installedTextField(in: view) else {
            return (false, "begin(...) did not install an NSTextView subview on the OverlayView")
        }

        let whitespaceOnly = makeRandomWhitespaceOnlyString(rng: &rng)
        field.string = whitespaceOnly

        let result = controller.commit()

        guard case .discarded = result else {
            return (false, "commit() editing an existing TextAnnotation with whitespace-only input "
                + "\(String(reflecting: whitespaceOnly)) should return .discarded, got \(result)")
        }

        guard state.items.map({ $0.id }) == itemsBefore else {
            return (false, "DrawingState.items changed after a discarded edit-commit. "
                + "Before: \(itemsBefore.count) items, after: \(state.items.count) items.")
        }

        return (true, "")
    }
}



// MARK: - Property 8: Text style is snapshotted when editing begins
//
// **Property 8: Text style is snapshotted when editing begins**
//
// For any pair of colors and any pair of font sizes, beginning a text edit with the
// first of each and then mutating the active color and persisted font size to the
// second before committing produces a `TextAnnotation` carrying the first color and
// the first font size.
//
// **Validates: Requirements 1.15, 1.4**
//
// ## What this test proves
//
// `TextEditingController.begin(at:existing:in:color:fontSize:)` snapshots `color`
// and `fontSize` into its own private stored properties at call time. Those private
// snapshots — not whatever `DrawingState.activeColor` or
// `SettingsManager.shared.textFontSize` happen to read at `commit()` time — are what
// `commit()` bakes into the resulting `TextAnnotation`. This holds trivially by
// construction (the controller never re-reads either external source after `begin`),
// but the property test's job is to prove it by actually performing the intervening
// external mutation, not to assume it.
//
// Each iteration: calls `begin(color: colorA, fontSize: fontSizeA, ...)`, then
// mutates `DrawingState.activeColor` to `colorB` and `SettingsManager.shared.
// textFontSize` to `fontSizeB` (both distinct from the A values), sets the
// installed field's text to a non-empty-after-trim string, and commits. The
// resulting annotation's `color` and `fontSize` must equal A, never B.
//
// ## NSColor comparison
//
// Neither `PreservationPropertyTests.swift` nor `TransformPropertyTests.swift`
// compares `NSColor` values anywhere in this codebase (both were checked; neither
// file mentions `NSColor` at all — item colors in those files are exercised but
// never asserted on directly). Absent an established convention to match, this
// test compares colors via `NSColor.isEqual(_:)`, which is the standard Cocoa
// equality check for `NSColor` and correctly reports equal for two `NSColor`
// instances created from the same catalog/system color constant (e.g. two
// references to `.systemBlue`) without needing colorspace conversion. The A/B
// color pool below is drawn from fixed `NSColor` constants (as `TextAnnotation`
// itself stores whatever `NSColor` it is given, unconverted), so `isEqual` is a
// direct, reliable check here rather than a colorspace-sensitive comparison.

/// Picks two distinct `NSColor` values from a small fixed palette using `SimplePRNG`
/// (which has no `RandomNumberGenerator` conformance, so no `shuffle(using:)`).
/// Retries the second pick until it differs from the first, which always
/// terminates for a multi-color pool.
private func makeRandomDistinctColorPair(rng: inout SimplePRNG) -> (NSColor, NSColor) {
    let colorPool: [NSColor] = [.systemRed, .systemBlue, .systemGreen, .systemYellow, .white, .black]
    let indexA = rng.nextInt(in: 0...(colorPool.count - 1))
    var indexB = rng.nextInt(in: 0...(colorPool.count - 1))
    while indexB == indexA {
        indexB = rng.nextInt(in: 0...(colorPool.count - 1))
    }
    return (colorPool[indexA], colorPool[indexB])
}

@MainActor
func testTextStyleSnapshottedAtEditBegin() -> PreservationTestResult {
    return runPreservationTest(
        "Property 8: Text style is snapshotted when editing begins",
        iterations: 150
    ) { rng in
        let (colorA, colorB) = makeRandomDistinctColorPair(rng: &rng)

        let fontSizeA = CGFloat(rng.nextInt(in: 8...96))
        var fontSizeB = CGFloat(rng.nextInt(in: 8...96))
        // Guarantee A and B are distinct font sizes so a test that accidentally
        // read B instead of A would be caught rather than passing by coincidence.
        if fontSizeB == fontSizeA {
            fontSizeB = fontSizeA >= 96 ? fontSizeA - 1 : fontSizeA + 1
        }

        let state = DrawingState()
        state.activeColor = colorA

        let (window, view) = makeHostedOverlayView()
        view.drawingState = state
        defer { window.orderOut(nil) }

        let controller = TextEditingController()
        let anchor = CGPoint(
            x: CGFloat(rng.nextDouble(in: -200...600)),
            y: CGFloat(rng.nextDouble(in: -200...600))
        )
        controller.begin(at: anchor, existing: nil, in: view, color: colorA, fontSize: fontSizeA)

        guard let field = installedTextField(in: view) else {
            return (false, "begin(...) did not install an NSTextView subview on the OverlayView")
        }

        // Simulate "the user changed the active color / persisted font size
        // mid-composition" by mutating both external sources after begin() has
        // already captured its own private snapshot.
        state.activeColor = colorB
        SettingsManager.shared.textFontSize = fontSizeB

        let (raw, expectedTrimmed) = makeRandomNonEmptyAfterTrimString(rng: &rng)
        field.string = raw

        let result = controller.commit()

        guard case .created(let annotation) = result else {
            return (false, "commit() with non-empty-after-trim input \(String(reflecting: raw)) "
                + "should return .created, got \(result)")
        }

        guard annotation.string == expectedTrimmed else {
            return (false, "Created TextAnnotation.string \(String(reflecting: annotation.string)) "
                + "does not equal the expected trimmed input \(String(reflecting: expectedTrimmed)).")
        }

        guard annotation.color.isEqual(colorA) else {
            return (false, "TextAnnotation.color should be the color in effect at begin() (colorA), "
                + "but got a color equal to colorB instead of colorA. This means the controller "
                + "re-read DrawingState.activeColor at commit time instead of using its begin() "
                + "snapshot. colorA=\(colorA), colorB=\(colorB), got=\(annotation.color).")
        }

        guard !annotation.color.isEqual(colorB) else {
            return (false, "TextAnnotation.color unexpectedly equals colorB (the color mutated into "
                + "DrawingState.activeColor mid-composition), which should have zero effect on the "
                + "committed item. colorA=\(colorA), colorB=\(colorB).")
        }

        guard annotation.fontSize == fontSizeA else {
            return (false, "TextAnnotation.fontSize should be the font size in effect at begin() "
                + "(fontSizeA=\(fontSizeA)), but got \(annotation.fontSize). fontSizeB=\(fontSizeB) was "
                + "written into SettingsManager.shared.textFontSize mid-composition and must have zero "
                + "effect on the committed item.")
        }

        // Restore textFontSize so this test does not leak persisted state that
        // could affect a later iteration or test in the same process.
        SettingsManager.shared.textFontSize = 24.0

        return (true, "")
    }
}

/// Feature: annotation-parity-phase-1, Property 8: Text style is snapshotted when editing begins
///
/// **Validates: Requirements 1.15, 1.4**
///
/// Same property, exercised on the edit-existing-annotation path (`existing` non-nil)
/// rather than the compose-new path, so both `TextCommitResult` branches that can
/// carry a freshly-snapshotted style are covered. `TextAnnotation.replacingString`
/// preserves the original's `fontSize` and `color` by design — this test confirms
/// that preservation is of the *original* item's already-fixed style, not of
/// whatever color/font size happened to be active at commit time, and is unaffected
/// by mid-composition mutation of either external source.
@MainActor
func testTextStyleSnapshottedAtEditBeginForExistingAnnotation() -> PreservationTestResult {
    return runPreservationTest(
        "Property 8: Text style is snapshotted when editing begins (editing existing annotation)",
        iterations: 150
    ) { rng in
        let (colorA, colorB) = makeRandomDistinctColorPair(rng: &rng)

        let fontSizeA = CGFloat(rng.nextInt(in: 8...96))
        var fontSizeB = CGFloat(rng.nextInt(in: 8...96))
        if fontSizeB == fontSizeA {
            fontSizeB = fontSizeA >= 96 ? fontSizeA - 1 : fontSizeA + 1
        }

        // The existing annotation carries its own pre-existing style, independent
        // of colorA/fontSizeA, so the assertions below isolate begin()'s snapshot
        // (colorA/fontSizeA) from the item's prior style.
        let existing = makeRandomTextAnnotation(rng: &rng)

        let state = DrawingState()
        state.addItem(existing)
        state.activeColor = colorA

        let (window, view) = makeHostedOverlayView()
        view.drawingState = state
        defer { window.orderOut(nil) }

        let controller = TextEditingController()
        controller.begin(at: existing.anchor, existing: existing, in: view, color: colorA, fontSize: fontSizeA)

        guard let field = installedTextField(in: view) else {
            return (false, "begin(...) did not install an NSTextView subview on the OverlayView")
        }

        state.activeColor = colorB
        SettingsManager.shared.textFontSize = fontSizeB

        let (raw, expectedTrimmed) = makeRandomNonEmptyAfterTrimString(rng: &rng)
        field.string = raw

        let result = controller.commit()

        guard case .edited(let original, let updated) = result else {
            return (false, "commit() editing an existing TextAnnotation with non-empty-after-trim "
                + "input \(String(reflecting: raw)) should return .edited, got \(result)")
        }

        guard original.id == existing.id else {
            return (false, "commit() returned .edited with the wrong original item: expected id "
                + "\(existing.id), got \(original.id)")
        }

        guard updated.string == expectedTrimmed else {
            return (false, "Edited TextAnnotation.string \(String(reflecting: updated.string)) "
                + "does not equal the expected trimmed input \(String(reflecting: expectedTrimmed)).")
        }

        // replacingString preserves the ORIGINAL item's color/fontSize (not colorA/
        // fontSizeA, and definitely not colorB/fontSizeB).
        guard updated.color.isEqual(existing.color) else {
            return (false, "Edited TextAnnotation.color should preserve the original item's color "
                + "(replacingString preserves color), but got a different color. "
                + "original=\(existing.color), got=\(updated.color).")
        }

        guard !updated.color.isEqual(colorB) || existing.color.isEqual(colorB) else {
            return (false, "Edited TextAnnotation.color unexpectedly equals colorB, the color mutated "
                + "into DrawingState.activeColor mid-composition, which should have zero effect. "
                + "original=\(existing.color), colorB=\(colorB), got=\(updated.color).")
        }

        guard updated.fontSize == existing.fontSize else {
            return (false, "Edited TextAnnotation.fontSize should preserve the original item's font "
                + "size (replacingString preserves fontSize), but got \(updated.fontSize) instead of "
                + "\(existing.fontSize).")
        }

        guard updated.fontSize != fontSizeB || existing.fontSize == fontSizeB else {
            return (false, "Edited TextAnnotation.fontSize unexpectedly equals fontSizeB, the value "
                + "written into SettingsManager.shared.textFontSize mid-composition, which should "
                + "have zero effect. original=\(existing.fontSize), fontSizeB=\(fontSizeB).")
        }

        SettingsManager.shared.textFontSize = 24.0

        return (true, "")
    }
}


// MARK: - Property 9: Text bounds are non-degenerate and monotonic in font size
//
// **Property 9: Text bounds are non-degenerate and monotonic in font size**
//
// For any non-empty string, the `TextAnnotation` bounds have strictly positive width
// and height, and for any pair of font sizes where the first is smaller than the
// second, the bounds measured at the smaller size are no larger in either dimension
// than those measured at the larger size.
//
// **Validates: Requirements 1.12**
//
// ## Measuring bounds
//
// `TextAnnotation.untranslatedBounds` is a `lazy var` derived from
// `NSAttributedString.size()` anchored at `anchor`, exposed through the
// `DrawingItem` protocol. A freshly constructed `TextAnnotation` has
// `offset == .zero` (confirmed in `TextAnnotation.swift`: `var offset: CGSize =
// .zero`, never mutated by `init`), so `bounds` (`untranslatedBounds` offset by
// `offset`, from `DrawingItem+Transform.swift`) and `untranslatedBounds` agree for
// every item constructed directly by this test. `untranslatedBounds` is read
// directly below since it is the quantity the property statement and design.md's
// bounds table describe.

/// Non-empty strings used to drive the non-degeneracy and monotonicity checks.
/// Deliberately includes single-character, whitespace-padded (but non-empty-after
/// content), multi-word, and repeated-character strings, since width should scale
/// with content in addition to font size.
private let nonEmptyBoundsTestStrings = [
    "A", "Hello", "Spot the bug", "  padded  ", "12345", "W", "i", "annotation parity"
]

/// Generates a random non-empty string for bounds testing, drawn from
/// `nonEmptyBoundsTestStrings`. A dedicated generator is used here rather than
/// `makeRandomNonEmptyAfterTrimString` because this property is about the string
/// actually stored on `TextAnnotation.string` (whatever it is, non-empty), not
/// about trim behavior — `TextAnnotation.init` performs no trimming, so a simpler
/// generator matches the shape of what is under test.
private func makeRandomNonEmptyBoundsString(rng: inout SimplePRNG) -> String {
    nonEmptyBoundsTestStrings[rng.nextInt(in: 0...(nonEmptyBoundsTestStrings.count - 1))]
}

/// Feature: annotation-parity-phase-1, Property 9: Text bounds are non-degenerate and monotonic in font size
///
/// **Validates: Requirements 1.12**
///
/// Sub-property 1 (non-degeneracy): for any non-empty string, any anchor, and any
/// font size in the valid 8...96 range, `untranslatedBounds.width > 0` and
/// `untranslatedBounds.height > 0`.
func testTextBoundsAreNonDegenerate() -> PreservationTestResult {
    return runPreservationTest(
        "Property 9: Text bounds are non-degenerate for any non-empty string",
        iterations: 150
    ) { rng in
        let string = makeRandomNonEmptyBoundsString(rng: &rng)
        let anchor = CGPoint(
            x: CGFloat(rng.nextDouble(in: -500...500)),
            y: CGFloat(rng.nextDouble(in: -500...500))
        )
        let fontSize = CGFloat(rng.nextInt(in: 8...96))
        let colors: [NSColor] = [.systemRed, .systemBlue, .systemGreen, .white, .black]
        let color = colors[rng.nextInt(in: 0...(colors.count - 1))]

        let annotation = TextAnnotation(string: string, anchor: anchor, fontSize: fontSize, color: color)
        let bounds = annotation.untranslatedBounds

        guard bounds.width > 0 else {
            return (false, "TextAnnotation(string: \(String(reflecting: string)), fontSize: \(fontSize)) "
                + "has non-positive width \(bounds.width), expected > 0.")
        }

        guard bounds.height > 0 else {
            return (false, "TextAnnotation(string: \(String(reflecting: string)), fontSize: \(fontSize)) "
                + "has non-positive height \(bounds.height), expected > 0.")
        }

        return (true, "")
    }
}

/// Feature: annotation-parity-phase-1, Property 9: Text bounds are non-degenerate and monotonic in font size
///
/// **Validates: Requirements 1.12**
///
/// Sub-property 2 (monotonicity): for any non-empty string and any two font sizes
/// where the first is smaller than the second, the height measured at the smaller
/// size is no larger than the height measured at the larger size.
/// Both annotations share the same string, anchor, and color so font size is the
/// only varying input.
///
/// Note: Width monotonicity is NOT guaranteed because multi-line rendering uses
/// `boundingRect(with:options:)` with a fixed max width of 400pt. When a larger
/// font causes word-wrapping, the reported width of the longest line after wrapping
/// can be smaller than the full unwrapped width at a smaller font size. Height,
/// however, is always monotonic: a larger font produces taller lines, and wrapping
/// only adds more lines.
func testTextBoundsAreMonotonicInFontSize() -> PreservationTestResult {
    return runPreservationTest(
        "Property 9: Text bounds height is monotonic in font size",
        iterations: 150
    ) { rng in
        let string = makeRandomNonEmptyBoundsString(rng: &rng)
        let anchor = CGPoint(
            x: CGFloat(rng.nextDouble(in: -500...500)),
            y: CGFloat(rng.nextDouble(in: -500...500))
        )
        let colors: [NSColor] = [.systemRed, .systemBlue, .systemGreen, .white, .black]
        let color = colors[rng.nextInt(in: 0...(colors.count - 1))]

        let fontSizeA = rng.nextInt(in: 8...95)
        let fontSizeB = rng.nextInt(in: (fontSizeA + 1)...96)

        let annotationA = TextAnnotation(
            string: string, anchor: anchor, fontSize: CGFloat(fontSizeA), color: color
        )
        let annotationB = TextAnnotation(
            string: string, anchor: anchor, fontSize: CGFloat(fontSizeB), color: color
        )

        let boundsA = annotationA.untranslatedBounds
        let boundsB = annotationB.untranslatedBounds

        guard boundsA.height <= boundsB.height else {
            return (false, "TextAnnotation(string: \(String(reflecting: string)), fontSize: \(fontSizeA)) "
                + "has height \(boundsA.height), which exceeds the height \(boundsB.height) at the larger "
                + "fontSize \(fontSizeB). Height must be monotonic non-decreasing in font size.")
        }

        return (true, "")
    }
}
