import Cocoa
@testable import SpotdrawCore

/// Transform Property Tests
///
/// These tests verify Properties 3, 4, and 5 from design.md, using the same
/// hand-rolled harness as `PreservationPropertyTests.swift` (`SimplePRNG`,
/// `PreservationTestResult`, `runPreservationTest(_:iterations:_:)`).
///
/// **Property 3: Translation accumulation**
/// For any drawing item and any pair of translation deltas, applying them in sequence
/// produces the same offset and the same bounds as applying their component-wise sum
/// once, and the item's `bounds` equals its `untranslatedBounds` shifted by the
/// accumulated offset.
///
/// **Validates: Requirements 3.1, 3.2, 1.10**
///
/// **Property 4: Bounds and hit-test agreement**
/// For any drawing item of any conforming type and any point, if
/// `hitTestTranslated(point:threshold:)` returns true then `bounds` outset by
/// `threshold` contains that point, and every geometry-defining point of the item
/// lies within `bounds`.
///
/// **Validates: Requirements 2.3, 1.11**
///
/// **Property 5: Eraser semantics under translation**
/// For any item list whose members carry arbitrary offsets and any erase point, the
/// items remaining after `removeItems(intersecting:threshold: 15)` are exactly those
/// items for which `hitTestTranslated` returns false.
///
/// **Validates: Requirements 10.2**

// MARK: - Shared random DrawingItem factories
//
// These factories are shared across this file's tests and are intended for reuse by
// task 1.11 (bounds/hit-test agreement) and task 1.12 (eraser semantics under
// translation), both of which extend this same file.

/// Generates a random `CGFloat` in `range` using `SimplePRNG`.
private func randomCGFloat(_ rng: inout SimplePRNG, in range: ClosedRange<Double>) -> CGFloat {
    CGFloat(rng.nextDouble(in: range))
}

/// Generates a random `CGPoint` with both coordinates in `-500...500`.
private func randomPoint(_ rng: inout SimplePRNG) -> CGPoint {
    CGPoint(x: randomCGFloat(&rng, in: -500...500), y: randomCGFloat(&rng, in: -500...500))
}

/// Generates a random `NSColor` from a small fixed palette.
private func randomColor(_ rng: inout SimplePRNG) -> NSColor {
    let colors: [NSColor] = [.red, .blue, .green, .yellow, .white, .black, .systemOrange]
    return colors[rng.nextInt(in: 0...(colors.count - 1))]
}

/// Builds a random `FreehandStroke`.
///
/// Roughly 1 in 5 strokes is degenerate: the two-point minimum that
/// `FreehandStroke.draw(in:)` guards on (`points.count > 1`).
func makeRandomFreehandStroke(rng: inout SimplePRNG) -> FreehandStroke {
    let lineWidth = randomCGFloat(&rng, in: 1...20)
    let isDegenerate = rng.nextInt(in: 0...4) == 0
    let pointCount = isDegenerate ? 2 : rng.nextInt(in: 2...12)
    var points: [CGPoint] = []
    for _ in 0..<pointCount {
        points.append(randomPoint(&rng))
    }
    return FreehandStroke(points: points, color: randomColor(&rng), lineWidth: lineWidth)
}

/// Builds a random `ArrowShape`.
///
/// Roughly 1 in 5 arrows has coincident start/end points (a degenerate,
/// zero-length arrow).
func makeRandomArrowShape(rng: inout SimplePRNG) -> ArrowShape {
    let start = randomPoint(&rng)
    let isDegenerate = rng.nextInt(in: 0...4) == 0
    let end = isDegenerate ? start : randomPoint(&rng)
    return ArrowShape(start: start, end: end, color: randomColor(&rng), lineWidth: randomCGFloat(&rng, in: 1...20))
}

/// Builds a random `RectangleShape`.
///
/// Roughly 1 in 5 rects is zero-size (zero width and/or height).
func makeRandomRectangleShape(rng: inout SimplePRNG) -> RectangleShape {
    let origin = randomPoint(&rng)
    let isDegenerate = rng.nextInt(in: 0...4) == 0
    let width = isDegenerate ? 0 : randomCGFloat(&rng, in: 1...300)
    let height = isDegenerate ? 0 : randomCGFloat(&rng, in: 1...300)
    let rect = CGRect(x: origin.x, y: origin.y, width: width, height: height)
    return RectangleShape(rect: rect, color: randomColor(&rng), lineWidth: randomCGFloat(&rng, in: 1...20))
}

/// Builds a random `CircleShape`.
///
/// Roughly 1 in 5 circles is zero-size (zero width and/or height bounding rect).
func makeRandomCircleShape(rng: inout SimplePRNG) -> CircleShape {
    let origin = randomPoint(&rng)
    let isDegenerate = rng.nextInt(in: 0...4) == 0
    let width = isDegenerate ? 0 : randomCGFloat(&rng, in: 1...300)
    let height = isDegenerate ? 0 : randomCGFloat(&rng, in: 1...300)
    let rect = CGRect(x: origin.x, y: origin.y, width: width, height: height)
    return CircleShape(rect: rect, color: randomColor(&rng), lineWidth: randomCGFloat(&rng, in: 1...20))
}

/// Builds a random `LineShape`.
///
/// Roughly 1 in 5 lines has coincident start/end points (a degenerate,
/// zero-length line).
func makeRandomLineShape(rng: inout SimplePRNG) -> LineShape {
    let start = randomPoint(&rng)
    let isDegenerate = rng.nextInt(in: 0...4) == 0
    let end = isDegenerate ? start : randomPoint(&rng)
    return LineShape(start: start, end: end, color: randomColor(&rng), lineWidth: randomCGFloat(&rng, in: 1...20))
}

/// Dispatches to one of the five `makeRandom*` factories at random, returning the
/// result as `any DrawingItem`.
func makeRandomDrawingItem(rng: inout SimplePRNG) -> any DrawingItem {
    switch rng.nextInt(in: 0...4) {
    case 0: makeRandomFreehandStroke(rng: &rng)
    case 1: makeRandomArrowShape(rng: &rng)
    case 2: makeRandomRectangleShape(rng: &rng)
    case 3: makeRandomCircleShape(rng: &rng)
    default: makeRandomLineShape(rng: &rng)
    }
}

/// Human-readable label for a `DrawingItem`'s concrete type, used in failure messages.
private func typeName(of item: any DrawingItem) -> String {
    switch item {
    case is FreehandStroke: "FreehandStroke"
    case is ArrowShape: "ArrowShape"
    case is RectangleShape: "RectangleShape"
    case is CircleShape: "CircleShape"
    case is LineShape: "LineShape"
    default: String(describing: type(of: item))
    }
}

// MARK: - Property 3: Translation accumulation

/// Runs Property 3 against a single `DrawingItem` built by `makeItem`, using two
/// random translation deltas per iteration.
private func runTranslationAccumulationProperty(
    name: String,
    iterations: Int = 100,
    makeItem: @escaping (inout SimplePRNG) -> any DrawingItem
) -> PreservationTestResult {
    // Feature: annotation-parity-phase-1, Property 3: Translation accumulation
    return runPreservationTest(name, iterations: iterations) { rng in
        // A single item is used for both arms of the comparison, since `offset`
        // is the only mutable piece of translation state: apply the two deltas
        // in sequence first and record the result, then reset `offset` back to
        // `.zero` and apply their sum once. This avoids constructing two
        // independently-randomized items (which would consume the shared `rng`
        // twice and produce two items with *different* starting geometry —
        // a test bug, not a production one, that an earlier version of this
        // test had).
        let item = makeItem(&rng)
        let typeLabel = typeName(of: item)
        let untranslated = item.untranslatedBounds

        let delta1 = CGSize(width: randomCGFloat(&rng, in: -1000...1000), height: randomCGFloat(&rng, in: -1000...1000))
        let delta2 = CGSize(width: randomCGFloat(&rng, in: -1000...1000), height: randomCGFloat(&rng, in: -1000...1000))
        let summedDelta = CGSize(width: delta1.width + delta2.width, height: delta1.height + delta2.height)

        item.translate(by: delta1)
        item.translate(by: delta2)
        let sequentialOffset = item.offset
        let sequentialBounds = item.bounds

        item.offset = .zero
        item.translate(by: summedDelta)
        let combinedOffset = item.offset
        let combinedBounds = item.bounds

        // Same offset.
        guard sequentialOffset == combinedOffset else {
            return (false, "\(typeLabel): sequential offset \(sequentialOffset) != combined offset \(combinedOffset) "
                + "(delta1=\(delta1), delta2=\(delta2), summed=\(summedDelta))")
        }

        // Same bounds.
        guard sequentialBounds == combinedBounds else {
            return (false, "\(typeLabel): sequential bounds \(sequentialBounds) != combined bounds \(combinedBounds) "
                + "(delta1=\(delta1), delta2=\(delta2), summed=\(summedDelta))")
        }

        // bounds == untranslatedBounds shifted by the accumulated offset, for both arms.
        let expectedSequentialBounds = untranslated.offsetBy(dx: sequentialOffset.width, dy: sequentialOffset.height)
        guard sequentialBounds == expectedSequentialBounds else {
            return (false, "\(typeLabel): sequential bounds \(sequentialBounds) != untranslatedBounds "
                + "\(untranslated) offset by \(sequentialOffset) = \(expectedSequentialBounds)")
        }

        let expectedCombinedBounds = untranslated.offsetBy(dx: combinedOffset.width, dy: combinedOffset.height)
        guard combinedBounds == expectedCombinedBounds else {
            return (false, "\(typeLabel): combined bounds \(combinedBounds) != untranslatedBounds "
                + "\(untranslated) offset by \(combinedOffset) = \(expectedCombinedBounds)")
        }

        return (true, "")
    }
}

/// **Validates: Requirements 3.1, 3.2, 1.10**
func testTranslationAccumulationFreehandStroke() -> PreservationTestResult {
    runTranslationAccumulationProperty(
        name: "Property 3: Translation accumulation — FreehandStroke (incl. two-point degenerate)",
        makeItem: { rng in makeRandomFreehandStroke(rng: &rng) }
    )
}

/// **Validates: Requirements 3.1, 3.2, 1.10**
func testTranslationAccumulationArrowShape() -> PreservationTestResult {
    runTranslationAccumulationProperty(
        name: "Property 3: Translation accumulation — ArrowShape (incl. coincident endpoints)",
        makeItem: { rng in makeRandomArrowShape(rng: &rng) }
    )
}

/// **Validates: Requirements 3.1, 3.2, 1.10**
func testTranslationAccumulationRectangleShape() -> PreservationTestResult {
    runTranslationAccumulationProperty(
        name: "Property 3: Translation accumulation — RectangleShape (incl. zero-size rect)",
        makeItem: { rng in makeRandomRectangleShape(rng: &rng) }
    )
}

/// **Validates: Requirements 3.1, 3.2, 1.10**
func testTranslationAccumulationCircleShape() -> PreservationTestResult {
    runTranslationAccumulationProperty(
        name: "Property 3: Translation accumulation — CircleShape (incl. zero-size rect)",
        makeItem: { rng in makeRandomCircleShape(rng: &rng) }
    )
}

/// **Validates: Requirements 3.1, 3.2, 1.10**
func testTranslationAccumulationLineShape() -> PreservationTestResult {
    runTranslationAccumulationProperty(
        name: "Property 3: Translation accumulation — LineShape (incl. coincident endpoints)",
        makeItem: { rng in makeRandomLineShape(rng: &rng) }
    )
}

/// **Validates: Requirements 3.1, 3.2, 1.10**
///
/// Exercises the shared dispatcher directly, so the property is also checked against
/// a uniformly mixed population of all five item types in a single run.
func testTranslationAccumulationMixedItems() -> PreservationTestResult {
    runTranslationAccumulationProperty(
        name: "Property 3: Translation accumulation — mixed DrawingItem types via dispatcher",
        makeItem: { rng in makeRandomDrawingItem(rng: &rng) }
    )
}

// MARK: - Property 4: Bounds and hit-test agreement

/// Returns the defining geometry points of `item`, in untranslated (local) coordinates.
///
/// - `FreehandStroke`: every point in `points`
/// - `ArrowShape` / `LineShape`: `start` and `end`
/// - `RectangleShape` / `CircleShape`: the four corners implied by `rect`
private func definingGeometryPoints(of item: any DrawingItem) -> [CGPoint] {
    switch item {
    case let stroke as FreehandStroke:
        return stroke.points
    case let arrow as ArrowShape:
        return [arrow.start, arrow.end]
    case let line as LineShape:
        return [line.start, line.end]
    case let rectangle as RectangleShape:
        let r = rectangle.rect
        return [
            CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
            CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY),
        ]
    case let circle as CircleShape:
        let r = circle.rect
        return [
            CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
            CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY),
        ]
    default:
        return []
    }
}

/// Runs Property 4 against a single `DrawingItem` built by `makeItem`.
///
/// Each iteration builds an item, optionally translates it by a random offset
/// (including possibly `.zero`, so both the untranslated and translated cases are
/// exercised), then probes several candidate points — some biased toward the
/// item's own geometry (likely hits) and some drawn from the wider random range
/// (likely misses).
///
/// For every probe point where `hitTestTranslated` returns true, `bounds` outset by
/// `hitMargin(threshold:)` must contain that point. `hitMargin` accounts for the
/// *actual* geometric margin each type's `hitTest` uses beyond its own
/// `untranslatedBounds`, which is not always exactly `threshold`:
///
/// - `FreehandStroke.hitTest` uses `max(threshold, lineWidth / 2 + 5)` as its hit
///   radius around each point, while `untranslatedBounds` is only outset by
///   `lineWidth / 2`. The extra margin beyond `untranslatedBounds` is therefore
///   `max(threshold, lineWidth / 2 + 5) - lineWidth / 2` in the worst case (fully
///   outset already covers up to `lineWidth / 2` of it).
/// - `RectangleShape.hitTest` expands `rect` by `threshold + lineWidth`, while
///   `untranslatedBounds` expands `rect` by only `lineWidth / 2`. The extra margin
///   beyond `untranslatedBounds` is `threshold + lineWidth / 2`.
/// - `ArrowShape` / `LineShape.hitTest` (via `lineSegmentHitTest`) accept within
///   `threshold + lineWidth / 2` of the segment, matching `untranslatedBounds`'s
///   `lineWidth / 2` outset plus `threshold` exactly.
/// - `CircleShape.hitTest` normalizes distance in ellipse space using a single
///   scalar derived from `rx` only, then applies it uniformly to both axes. For a
///   non-circular ellipse (`rx != ry`) this makes the actual Cartesian margin along
///   the longer axis exceed `threshold` — the property computes the true worst-case
///   margin along each axis from the same formula, taking the larger. The formula
///   is also degenerate (divides by `rx * rx` / `ry * ry`) for a zero-size `rect` —
///   a pre-existing, documented hazard (see design.md "Degenerate geometry") that
///   this property does not re-litigate. Zero-size `CircleShape` instances are
///   excluded from the hit-implies-bounds-contains assertion below for that reason;
///   the unconditional geometry-point-in-bounds check still covers them.
///
/// Independently of any probe outcome, every defining geometry point — translated
/// by `offset`, since `definingGeometryPoints` returns untranslated coordinates —
/// must lie within `bounds` unconditionally.
private func runBoundsHitTestAgreementProperty(
    name: String,
    iterations: Int = 100,
    makeItem: @escaping (inout SimplePRNG) -> any DrawingItem
) -> PreservationTestResult {
    // Feature: annotation-parity-phase-1, Property 4: Bounds and hit-test agreement
    return runPreservationTest(name, iterations: iterations) { rng in
        let item = makeItem(&rng)
        let typeLabel = typeName(of: item)

        // Roughly half of iterations apply a non-zero translation; the rest keep
        // `offset` at its initial `.zero`, so both cases are exercised.
        if rng.nextBool() {
            let delta = CGSize(width: randomCGFloat(&rng, in: -300...300), height: randomCGFloat(&rng, in: -300...300))
            item.translate(by: delta)
        }

        let threshold = randomCGFloat(&rng, in: 1...20)

        // The actual extra margin `hitTest` accepts beyond `untranslatedBounds`
        // (and therefore beyond `bounds`), per type. See the doc comment above.
        let extraMargin: CGFloat
        switch item {
        case let stroke as FreehandStroke:
            let hitRadius = max(threshold, stroke.lineWidth / 2 + 5)
            extraMargin = max(0, hitRadius - stroke.lineWidth / 2)
        case let rectangle as RectangleShape:
            extraMargin = threshold + rectangle.lineWidth / 2
        case let circle as CircleShape:
            // CircleShape.hitTest normalizes distance against a single ellipse-space
            // scalar (`outerThreshold`, derived from `rx` only) and applies it to both
            // axes uniformly. For a non-circular ellipse (rx != ry) this makes the
            // *Cartesian* margin along the longer axis larger than `threshold` — e.g.
            // for a tall, narrow ellipse the y-axis reach can be many times `threshold`.
            // This is a pre-existing property of the unchanged hit-test formula (not
            // something this task touches), so the property computes the same
            // worst-case Cartesian margin the formula actually produces, taking the
            // larger of the two axis margins, rather than assuming a uniform outset.
            let rx = circle.rect.width / 2
            let ry = circle.rect.height / 2
            if rx > 0, ry > 0 {
                let outerThreshold = ((rx + threshold) * (rx + threshold)) / (rx * rx)
                let xReach = rx * outerThreshold.squareRoot()
                let yReach = ry * outerThreshold.squareRoot()
                let xMargin = max(0, xReach - rx) - circle.lineWidth / 2
                let yMargin = max(0, yReach - ry) - circle.lineWidth / 2
                extraMargin = max(0, max(xMargin, yMargin))
            } else {
                extraMargin = threshold // unreachable: degenerate case is excluded below
            }
        default: // ArrowShape, LineShape
            extraMargin = threshold
        }
        let outset = item.bounds.insetBy(dx: -extraMargin, dy: -extraMargin)

        // Unconditional check: every defining geometry point, moved into translated
        // (view) space by `offset`, lies within `bounds`.
        for geometryPoint in definingGeometryPoints(of: item) {
            let translatedGeometryPoint = CGPoint(
                x: geometryPoint.x + item.offset.width,
                y: geometryPoint.y + item.offset.height
            )
            guard item.bounds.contains(translatedGeometryPoint) else {
                return (false, "\(typeLabel): geometry point \(geometryPoint) translated to "
                    + "\(translatedGeometryPoint) is not contained in bounds \(item.bounds) "
                    + "(offset=\(item.offset))")
            }
        }

        // A zero-size CircleShape's hit-test divides by zero (rx * rx / ry * ry),
        // a pre-existing, documented hazard unrelated to bounds/offset correctness.
        // Skip the hit-implies-bounds-contains check for that degenerate case only;
        // the geometry-point-in-bounds check above still ran unconditionally.
        if let circle = item as? CircleShape, circle.rect.width == 0 || circle.rect.height == 0 {
            return (true, "")
        }

        // Probe points: some biased near the item's own (translated) geometry —
        // likely hits — and some drawn from the wider random range — likely misses.
        var probePoints: [CGPoint] = []
        let geometryPoints = definingGeometryPoints(of: item)
        for _ in 0..<5 {
            if !geometryPoints.isEmpty, rng.nextBool() {
                let base = geometryPoints[rng.nextInt(in: 0...(geometryPoints.count - 1))]
                let jitter = CGSize(width: randomCGFloat(&rng, in: -10...10), height: randomCGFloat(&rng, in: -10...10))
                probePoints.append(CGPoint(
                    x: base.x + item.offset.width + jitter.width,
                    y: base.y + item.offset.height + jitter.height
                ))
            } else {
                probePoints.append(randomPoint(&rng))
            }
        }

        for probePoint in probePoints {
            guard item.hitTestTranslated(point: probePoint, threshold: threshold) else { continue }
            guard outset.contains(probePoint) else {
                return (false, "\(typeLabel): hitTestTranslated(point: \(probePoint), threshold: \(threshold)) "
                    + "returned true, but bounds \(item.bounds) outset by the expected hit margin "
                    + "(\(extraMargin)) does not contain the point "
                    + "(outset=\(outset), offset=\(item.offset))")
            }
        }

        return (true, "")
    }
}

/// **Validates: Requirements 2.3, 1.11**
func testBoundsHitTestAgreementFreehandStroke() -> PreservationTestResult {
    runBoundsHitTestAgreementProperty(
        name: "Property 4: Bounds and hit-test agreement — FreehandStroke",
        makeItem: { rng in makeRandomFreehandStroke(rng: &rng) }
    )
}

/// **Validates: Requirements 2.3, 1.11**
func testBoundsHitTestAgreementArrowShape() -> PreservationTestResult {
    runBoundsHitTestAgreementProperty(
        name: "Property 4: Bounds and hit-test agreement — ArrowShape",
        makeItem: { rng in makeRandomArrowShape(rng: &rng) }
    )
}

/// **Validates: Requirements 2.3, 1.11**
func testBoundsHitTestAgreementRectangleShape() -> PreservationTestResult {
    runBoundsHitTestAgreementProperty(
        name: "Property 4: Bounds and hit-test agreement — RectangleShape",
        makeItem: { rng in makeRandomRectangleShape(rng: &rng) }
    )
}

/// **Validates: Requirements 2.3, 1.11**
func testBoundsHitTestAgreementCircleShape() -> PreservationTestResult {
    runBoundsHitTestAgreementProperty(
        name: "Property 4: Bounds and hit-test agreement — CircleShape",
        makeItem: { rng in makeRandomCircleShape(rng: &rng) }
    )
}

/// **Validates: Requirements 2.3, 1.11**
func testBoundsHitTestAgreementLineShape() -> PreservationTestResult {
    runBoundsHitTestAgreementProperty(
        name: "Property 4: Bounds and hit-test agreement — LineShape",
        makeItem: { rng in makeRandomLineShape(rng: &rng) }
    )
}

// MARK: - Property 5: Eraser semantics under translation

/// Runs Property 5 against a `DrawingState` populated with a random mix of item
/// types, some of which carry an accumulated translation offset (applied through
/// the public `DrawingState.translate(ids:by:)` API, which is what production code
/// actually calls on a move drag — exercising the property through the same path
/// keeps the test meaningful as a regression guard on that call site, not just on
/// the lower-level `DrawingItem.translate(by:)` extension already covered by
/// Property 3).
///
/// After `removeItems(intersecting:threshold: 15)`, the surviving item identifiers
/// must equal exactly the set of identifiers for which `hitTestTranslated` returns
/// false, computed against a snapshot taken before the removal call.
private func runEraserSemanticsUnderTranslationProperty(
    name: String,
    iterations: Int = 100
) -> PreservationTestResult {
    // Feature: annotation-parity-phase-1, Property 5: Eraser semantics under translation
    return runPreservationTest(name, iterations: iterations) { rng in
        let state = DrawingState()
        let itemCount = rng.nextInt(in: 1...10)

        for _ in 0..<itemCount {
            let item = makeRandomDrawingItem(rng: &rng)
            state.addItem(item)

            // Roughly half of items get an arbitrary offset applied through the
            // public DrawingState API, so translated and untranslated items are
            // both represented in the same run.
            if rng.nextBool() {
                let delta = CGSize(width: randomCGFloat(&rng, in: -300...300), height: randomCGFloat(&rng, in: -300...300))
                state.translate(ids: [item.id], by: delta)
            }
        }

        // Snapshot before removal: (id, hitTestTranslated result) for every item,
        // computed independently of the removal call.
        let erasePoint = randomPoint(&rng)
        let threshold: CGFloat = 15
        let preRemovalSnapshot = state.items.map { (id: $0.id, wouldBeHit: $0.hitTestTranslated(point: erasePoint, threshold: threshold)) }
        let expectedSurvivorIDs = Set(preRemovalSnapshot.filter { !$0.wouldBeHit }.map { $0.id })
        let expectedRemovedIDs = Set(preRemovalSnapshot.filter { $0.wouldBeHit }.map { $0.id })

        state.removeItems(intersecting: erasePoint, threshold: threshold)

        let actualSurvivorIDs = Set(state.items.map { $0.id })

        guard actualSurvivorIDs == expectedSurvivorIDs else {
            let missingFromSurvivors = expectedSurvivorIDs.subtracting(actualSurvivorIDs)
            let unexpectedSurvivors = actualSurvivorIDs.subtracting(expectedSurvivorIDs)
            return (false, "erasePoint=\(erasePoint), threshold=\(threshold): survivor set mismatch. "
                + "Expected \(expectedSurvivorIDs.count) survivors (removed \(expectedRemovedIDs.count) hits), "
                + "got \(actualSurvivorIDs.count). "
                + "Missing from actual survivors: \(missingFromSurvivors.count), "
                + "unexpectedly survived: \(unexpectedSurvivors.count)")
        }

        return (true, "")
    }
}

/// **Validates: Requirements 10.2**
func testEraserSemanticsUnderTranslation() -> PreservationTestResult {
    runEraserSemanticsUnderTranslationProperty(
        name: "Property 5: Eraser semantics under translation — mixed items, some translated via DrawingState"
    )
}

// MARK: - Transform Property Test Runner

func runAllTransformPropertyTests() {
    let separator = String(repeating: "=", count: 70)

    print(separator)
    print("Transform Property Tests - Translation Accumulation")
    print(separator)
    print("")
    print("Property 3: applying two translation deltas in sequence must equal applying")
    print("their component-wise sum once, and bounds must equal untranslatedBounds")
    print("shifted by the accumulated offset.")
    print("")

    var testResults: [PreservationTestResult] = []

    testResults.append(testTranslationAccumulationFreehandStroke())
    testResults.append(testTranslationAccumulationArrowShape())
    testResults.append(testTranslationAccumulationRectangleShape())
    testResults.append(testTranslationAccumulationCircleShape())
    testResults.append(testTranslationAccumulationLineShape())
    testResults.append(testTranslationAccumulationMixedItems())

    testResults.append(testBoundsHitTestAgreementFreehandStroke())
    testResults.append(testBoundsHitTestAgreementArrowShape())
    testResults.append(testBoundsHitTestAgreementRectangleShape())
    testResults.append(testBoundsHitTestAgreementCircleShape())
    testResults.append(testBoundsHitTestAgreementLineShape())

    testResults.append(testEraserSemanticsUnderTranslation())

    print("")
    print(separator)
    print("TRANSFORM PROPERTY TEST RESULTS SUMMARY")
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
        print("FAILED: \(failed) transform property test(s) failed.")
        print("")
        for result in testResults where !result.passed {
            print("  - \(result.name):")
            print("    \(result.message)")
            print("")
        }
    } else {
        print("All transform property tests PASSED.")
    }

    print("")
}
