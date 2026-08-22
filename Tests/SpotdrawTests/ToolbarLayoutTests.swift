import Cocoa
@testable import SpotdrawCore

/// Tests for ToolbarLayout (Requirements 2.2, 2.4, 3.2).
///
/// ToolbarLayout is the pure width/section logic extracted from
/// UnifiedToolbarContentView.computedWidth. These tests prove the arithmetic was
/// ported verbatim (parity oracle over all 16 feature combinations) and pin the
/// layout invariants.

func runAllToolbarLayoutTests() -> [PreservationTestResult] {
    let separator = String(repeating: "=", count: 70)
    print(separator)
    print("ToolbarLayout Tests")
    print(separator)
    print("")

    var results: [PreservationTestResult] = []
    results.append(testWidthParityAcrossAllCombinations())
    results.append(testWidthMonotonicInFeatures())
    results.append(testChromeFloorWhenAllInactive())
    results.append(testVisibleSectionMembershipAndOrder())

    print("")
    print(separator)
    print("TOOLBARLAYOUT TEST RESULTS SUMMARY")
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
        print("FAILED: \(failed) ToolbarLayout test(s) failed.")
        for result in results where !result.passed {
            print("  - \(result.name): \(result.message)")
        }
    } else {
        print("All ToolbarLayout tests PASSED.")
    }
    print("")
    return results
}

/// Enumerates all 16 FeatureState combinations.
private func allFeatureStates() -> [FeatureState] {
    var states: [FeatureState] = []
    for a in [false, true] {
        for h in [false, true] {
            for s in [false, true] {
                for z in [false, true] {
                    states.append(FeatureState(annotationActive: a, highlightActive: h, spotlightActive: s, zoomActive: z))
                }
            }
        }
    }
    return states
}

/// The ORIGINAL inline arithmetic, copied verbatim from the pre-refactor
/// UnifiedToolbarContentView.computedWidth. Serves as the parity oracle: if
/// ToolbarLayout drifts from this, the toolbar width changed.
private func referenceComputedWidth(_ features: FeatureState) -> CGFloat {
    let hPadding: CGFloat = 16
    let itemSpacing: CGFloat = 10

    var width: CGFloat = hPadding
    width += 24
    width += itemSpacing * 2

    var sectionCount = 0

    if features.annotationActive {
        let swatchesW = CGFloat(5) * 30 + CGFloat(4) * itemSpacing
        let separatorW: CGFloat = 1 + itemSpacing * 2
        let toolsW = CGFloat(6) * 36 + CGFloat(5) * itemSpacing
        width += swatchesW + separatorW + toolsW
        sectionCount += 1
    }
    if features.highlightActive {
        if sectionCount > 0 { width += itemSpacing + 1 + itemSpacing }
        width += 50 + itemSpacing
        width += CGFloat(5) * 24 + CGFloat(4) * 6
        width += itemSpacing
        width += CGFloat(4) * 30 + CGFloat(3) * 6
        width += itemSpacing
        width += CGFloat(4) * 30 + CGFloat(3) * 6
        width += itemSpacing
        width += 20
        sectionCount += 1
    }
    if features.spotlightActive {
        if sectionCount > 0 { width += itemSpacing + 1 + itemSpacing }
        width += 52 + itemSpacing
        width += CGFloat(3) * 30 + CGFloat(2) * 6
        width += itemSpacing
        width += CGFloat(3) * 30 + CGFloat(2) * 6
        sectionCount += 1
    }
    if features.zoomActive {
        if sectionCount > 0 { width += itemSpacing + 1 + itemSpacing }
        width += 34 + itemSpacing
        width += 30 + 6 + 40 + 6 + 30
        width += itemSpacing
        width += CGFloat(3) * 30 + CGFloat(2) * 6
        sectionCount += 1
    }

    width += itemSpacing
    width += 26
    width += hPadding
    return width
}

/// **Validates: Requirement 2.2** — width matches the original arithmetic exactly.
func testWidthParityAcrossAllCombinations() -> PreservationTestResult {
    return runPreservationTest("Property: totalWidth == original computedWidth (all 16)", iterations: 1) { _ in
        for state in allFeatureStates() {
            let got = ToolbarLayout(features: state).totalWidth
            let expected = referenceComputedWidth(state)
            guard abs(got - expected) < 0.0001 else {
                return (false, "state \(state): got \(got), expected \(expected)")
            }
        }
        return (true, "")
    }
}

/// **Validates: Requirement 3.2** — turning any feature on never decreases width.
func testWidthMonotonicInFeatures() -> PreservationTestResult {
    return runPreservationTest("Property: totalWidth non-decreasing as features activate", iterations: 1) { _ in
        for state in allFeatureStates() {
            let base = ToolbarLayout(features: state).totalWidth
            // Turn on each currently-off feature; width must not shrink.
            var variants: [FeatureState] = []
            if !state.annotationActive { var s = state; s.annotationActive = true; variants.append(s) }
            if !state.highlightActive { var s = state; s.highlightActive = true; variants.append(s) }
            if !state.spotlightActive { var s = state; s.spotlightActive = true; variants.append(s) }
            if !state.zoomActive { var s = state; s.zoomActive = true; variants.append(s) }
            for v in variants {
                let w = ToolbarLayout(features: v).totalWidth
                guard w >= base - 0.0001 else {
                    return (false, "activating a feature shrank width: \(state) (\(base)) -> \(v) (\(w))")
                }
            }
        }
        return (true, "")
    }
}

/// **Validates: Requirement 3.2** — all-inactive yields the chrome-only floor,
/// and it is the minimum across all states.
func testChromeFloorWhenAllInactive() -> PreservationTestResult {
    return runPreservationTest("Property: all-inactive width is the minimum (chrome only)", iterations: 1) { _ in
        let empty = FeatureState(annotationActive: false, highlightActive: false, spotlightActive: false, zoomActive: false)
        let floor = ToolbarLayout(features: empty).totalWidth
        // chrome = hPadding + dragHandle + 2*itemSpacing + itemSpacing + dismiss + hPadding
        let expectedFloor: CGFloat = 16 + 24 + 10 * 2 + 10 + 26 + 16
        guard abs(floor - expectedFloor) < 0.0001 else {
            return (false, "floor \(floor) != expected \(expectedFloor)")
        }
        for state in allFeatureStates() {
            guard ToolbarLayout(features: state).totalWidth >= floor - 0.0001 else {
                return (false, "state \(state) narrower than the all-inactive floor")
            }
        }
        return (true, "")
    }
}

/// **Validates: Requirement 2.4** — visibleSections contains a section iff its
/// flag is set, in the fixed order annotation → highlight → spotlight → zoom.
func testVisibleSectionMembershipAndOrder() -> PreservationTestResult {
    return runPreservationTest("Property: visibleSections membership & order", iterations: 1) { _ in
        let order: [ToolbarSection] = [.annotation, .highlight, .spotlight, .zoom]
        for state in allFeatureStates() {
            let sections = ToolbarLayout(features: state).visibleSections

            guard sections.contains(.annotation) == state.annotationActive else { return (false, "annotation membership wrong for \(state)") }
            guard sections.contains(.highlight) == state.highlightActive else { return (false, "highlight membership wrong for \(state)") }
            guard sections.contains(.spotlight) == state.spotlightActive else { return (false, "spotlight membership wrong for \(state)") }
            guard sections.contains(.zoom) == state.zoomActive else { return (false, "zoom membership wrong for \(state)") }

            // Order preserved: filtering `order` by membership must equal sections.
            let expectedOrder = order.filter { sections.contains($0) }
            guard sections == expectedOrder else {
                return (false, "order wrong for \(state): \(sections) != \(expectedOrder)")
            }
        }
        return (true, "")
    }
}
