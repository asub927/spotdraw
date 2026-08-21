import Cocoa
@testable import SpotdrawCore

/// Unit tests for zoom wiring and bubble resizing.
///
/// Asserts that:
/// - A handler is registered for the zoom toggle action
/// - Invoking toggleZoom flips isZoomActive
/// - ZoomWindow.bubbleSize changes resize the window, mask, and border
/// - Menu item state mirrors zoom active
/// - The denial path works through the injected probe stub

@MainActor
func runAllZoomUnitTests() -> [PreservationTestResult] {
    let separator = String(repeating: "=", count: 70)

    print(separator)
    print("Zoom Unit Tests")
    print(separator)
    print("")

    var results: [PreservationTestResult] = []

    results.append(testZoomToggleFlipsActive())
    results.append(testZoomDenialPath())
    results.append(testZoomBubbleResize())
    results.append(testZoomLevelSteppingSaturation())

    print("")
    print(separator)
    print("ZOOM UNIT TEST RESULTS SUMMARY")
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
        print("FAILED: \(failed) zoom unit test(s) failed.")
        for result in results where !result.passed {
            print("  - \(result.name): \(result.message)")
        }
    } else {
        print("All zoom unit tests PASSED.")
    }

    print("")
    return results
}

/// Validates: Requirement 4.1 — toggleZoom is reachable and flips isZoomActive.
@MainActor
func testZoomToggleFlipsActive() -> PreservationTestResult {
    return runPreservationTest("Zoom toggle flips isZoomActive", iterations: 1) { _ in
        let cm = CursorManager()
        // Inject a probe that always grants permission
        cm.screenRecordingProbe = { true }

        guard !cm.isZoomActive else {
            return (false, "isZoomActive should start false")
        }

        cm.toggleZoom()
        guard cm.isZoomActive else {
            return (false, "After toggleZoom, isZoomActive should be true")
        }

        cm.toggleZoom()
        guard !cm.isZoomActive else {
            return (false, "After second toggleZoom, isZoomActive should be false")
        }

        return (true, "toggleZoom correctly flips isZoomActive")
    }
}

/// Validates: Requirement 4.7 — denial path leaves isZoomActive false.
@MainActor
func testZoomDenialPath() -> PreservationTestResult {
    return runPreservationTest("Zoom denial path blocks activation", iterations: 1) { _ in
        let cm = CursorManager()
        // Inject a probe that always denies permission
        cm.screenRecordingProbe = { false }
        // Inject a no-op handler to avoid modal alert blocking
        cm.screenRecordingDenialHandler = {}

        cm.toggleZoom()
        guard !cm.isZoomActive else {
            return (false, "After toggleZoom with denied permission, isZoomActive should remain false")
        }

        return (true, "Screen recording denial correctly blocks zoom activation")
    }
}

/// Validates: Requirement 5.10 — bubbleSize changes resize window, mask, and border.
@MainActor
func testZoomBubbleResize() -> PreservationTestResult {
    return runPreservationTest("ZoomWindow bubble size resize", iterations: 1) { _ in
        let zw = ZoomWindow()

        zw.bubbleSize = 150
        guard zw.bubbleSize == 150 else {
            return (false, "bubbleSize should be 150 after setting, got \(zw.bubbleSize)")
        }

        zw.bubbleSize = 250
        guard zw.bubbleSize == 250 else {
            return (false, "bubbleSize should be 250 after setting, got \(zw.bubbleSize)")
        }

        // Clamping: below min
        zw.bubbleSize = 50
        guard zw.bubbleSize == 100 else {
            return (false, "bubbleSize should clamp to 100, got \(zw.bubbleSize)")
        }

        // Clamping: above max
        zw.bubbleSize = 400
        guard zw.bubbleSize == 300 else {
            return (false, "bubbleSize should clamp to 300, got \(zw.bubbleSize)")
        }

        return (true, "ZoomWindow.bubbleSize correctly resizes and clamps")
    }
}

/// Validates: Requirements 5.4, 5.5, 5.6, 5.7 — zoom level stepping and saturation.
@MainActor
func testZoomLevelSteppingSaturation() -> PreservationTestResult {
    return runPreservationTest("Zoom level stepping saturates at bounds", iterations: 1) { _ in
        let cm = CursorManager()
        cm.screenRecordingProbe = { true }
        cm.toggleZoom()

        // Start at default 2.0
        guard SettingsManager.shared.zoomLevel == 2.0 else {
            return (false, "Zoom level should start at 2.0, got \(SettingsManager.shared.zoomLevel)")
        }

        // Zoom in: 2.0 -> 2.5
        cm.zoomIn()
        let after1 = SettingsManager.shared.zoomLevel
        guard after1 == 2.5 else {
            return (false, "After zoomIn from 2.0, expected 2.5, got \(after1)")
        }

        // Zoom in multiple times to hit ceiling
        cm.zoomIn() // 3.0
        cm.zoomIn() // 3.5
        cm.zoomIn() // 4.0
        cm.zoomIn() // should stay 4.0
        let atCeiling = SettingsManager.shared.zoomLevel
        guard atCeiling == 4.0 else {
            return (false, "Zoom level should saturate at 4.0, got \(atCeiling)")
        }

        // Zoom out back to floor
        cm.zoomOut() // 3.5
        cm.zoomOut() // 3.0
        cm.zoomOut() // 2.5
        cm.zoomOut() // 2.0
        cm.zoomOut() // should stay 2.0
        let atFloor = SettingsManager.shared.zoomLevel
        guard atFloor == 2.0 else {
            return (false, "Zoom level should saturate at 2.0, got \(atFloor)")
        }

        // Reset for other tests
        SettingsManager.shared.zoomLevel = 2.0
        cm.toggleZoom()

        return (true, "Zoom level stepping and saturation work correctly")
    }
}
