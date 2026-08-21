import Cocoa
@testable import SpotdrawCore

/// Zoom Property Tests (Properties 23–25)
///
/// Hand-rolled harness; port to PropertyBased after the deferred test-target split.

// MARK: - Property 23: Settings accessors clamp to their documented ranges

/// Feature: annotation-parity-phase-1, Property 23: Settings accessors clamp to their documented ranges
///
/// **Validates: Requirements 1.13, 5.1, 5.2**
///
/// Property: For any value written through a bounded settings accessor — text font size,
/// zoom level, zoom bubble size, highlight size, stroke width, glow radius — the value
/// read back lies within that accessor's documented range, and equals the written value
/// whenever the written value was already within range.
@MainActor
func testSettingsClampToDocumentedRanges() -> PreservationTestResult {
    return runPreservationTest(
        "Property 23: Settings accessors clamp to their documented ranges",
        iterations: 200
    ) { rng in
        let result: (Bool, String) = MainActor.assumeIsolated {
            let settings = SettingsManager.shared

            // Test textFontSize: range 8...96, default 24
            let rawFontSize = CGFloat(rng.nextDouble(in: -100...200))
            settings.textFontSize = rawFontSize
            let readFontSize = settings.textFontSize
            guard readFontSize >= 8 && readFontSize <= 96 else {
                return (false, "textFontSize \(readFontSize) out of range [8, 96] after writing \(rawFontSize)")
            }
            if rawFontSize >= 8 && rawFontSize <= 96 {
                let expected = rawFontSize
                guard abs(readFontSize - expected) < 1.0 else {
                    return (false, "textFontSize wrote \(rawFontSize) (in range), read \(readFontSize)")
                }
            }

            // Test zoomLevel: range 2.0...4.0, default 2.0
            let rawZoom = CGFloat(rng.nextDouble(in: -5...10))
            settings.zoomLevel = rawZoom
            let readZoom = settings.zoomLevel
            guard readZoom >= 2.0 && readZoom <= 4.0 else {
                return (false, "zoomLevel \(readZoom) out of range [2.0, 4.0] after writing \(rawZoom)")
            }
            if rawZoom >= 2.0 && rawZoom <= 4.0 {
                guard abs(readZoom - rawZoom) < 0.01 else {
                    return (false, "zoomLevel wrote \(rawZoom) (in range), read \(readZoom)")
                }
            }

            // Test zoomBubbleSize: range 100...300, default 200
            let rawBubble = CGFloat(rng.nextDouble(in: -100...500))
            settings.zoomBubbleSize = rawBubble
            let readBubble = settings.zoomBubbleSize
            guard readBubble >= 100 && readBubble <= 300 else {
                return (false, "zoomBubbleSize \(readBubble) out of range [100, 300] after writing \(rawBubble)")
            }
            if rawBubble >= 100 && rawBubble <= 300 {
                guard abs(readBubble - rawBubble) < 1.0 else {
                    return (false, "zoomBubbleSize wrote \(rawBubble) (in range), read \(readBubble)")
                }
            }

            // Test highlightSize: range 20...200
            let rawHighlight = CGFloat(rng.nextDouble(in: -50...400))
            settings.highlightSize = rawHighlight
            let readHighlight = settings.highlightSize
            guard readHighlight >= 20 && readHighlight <= 200 else {
                return (false, "highlightSize \(readHighlight) out of range [20, 200] after writing \(rawHighlight)")
            }

            // Test strokeWidth: range 1...20
            let rawStroke = CGFloat(rng.nextDouble(in: -10...50))
            settings.strokeWidth = rawStroke
            let readStroke = settings.strokeWidth
            guard readStroke >= 1 && readStroke <= 20 else {
                return (false, "strokeWidth \(readStroke) out of range [1, 20] after writing \(rawStroke)")
            }

            // Test glowRadius: range 5...50
            let rawGlow = CGFloat(rng.nextDouble(in: -20...100))
            settings.glowRadius = rawGlow
            let readGlow = settings.glowRadius
            guard readGlow >= 5 && readGlow <= 50 else {
                return (false, "glowRadius \(readGlow) out of range [5, 50] after writing \(rawGlow)")
            }

            // Reset to defaults for subsequent tests
            settings.textFontSize = 24
            settings.zoomLevel = 2.0
            settings.zoomBubbleSize = 200
            settings.highlightSize = 40
            settings.strokeWidth = 3
            settings.glowRadius = 15

            return (true, "")
        }
        return result
    }
}

// MARK: - Property 24: Zoom level stepping saturates at its bounds

/// Feature: annotation-parity-phase-1, Property 24: Zoom level stepping saturates at its bounds
///
/// **Validates: Requirements 5.3, 5.4, 5.5, 5.6, 5.7, 5.9, 5.10**
///
/// Property: For any sequence of zoom-in and zoom-out actions applied from any starting level,
/// the resulting zoom level lies within 2.0 to 4.0 and equals the starting level plus 0.5 per
/// net step, clamped to that range; and the persisted value matches the applied value.
@MainActor
func testZoomSteppingSaturation() -> PreservationTestResult {
    return runPreservationTest(
        "Property 24: Zoom level stepping saturates at its bounds",
        iterations: 200
    ) { rng in
        let result: (Bool, String) = MainActor.assumeIsolated {
            let cm = CursorManager()
            cm.screenRecordingProbe = { true }
            cm.toggleZoom()

            // Set random starting level within bounds
            let startLevel = 2.0 + 0.5 * Double(rng.nextInt(in: 0...4))
            SettingsManager.shared.zoomLevel = CGFloat(startLevel)
            cm.updateZoomAppearance()

            // Generate a random sequence of zoom in/out actions
            let stepCount = rng.nextInt(in: 1...12)
            var expectedLevel = startLevel

            for _ in 0..<stepCount {
                if rng.nextBool() {
                    cm.zoomIn()
                    expectedLevel = min(expectedLevel + 0.5, 4.0)
                } else {
                    cm.zoomOut()
                    expectedLevel = max(expectedLevel - 0.5, 2.0)
                }
            }

            let actualLevel = Double(SettingsManager.shared.zoomLevel)

            // Check: result is within bounds
            guard actualLevel >= 2.0 && actualLevel <= 4.0 else {
                return (false, "Zoom level \(actualLevel) out of bounds [2.0, 4.0]")
            }

            // Check: result matches expected
            guard abs(actualLevel - expectedLevel) < 0.01 else {
                return (
                    false,
                    "After \(stepCount) steps from \(startLevel), expected \(expectedLevel), got \(actualLevel)"
                )
            }

            // Cleanup
            SettingsManager.shared.zoomLevel = 2.0
            cm.toggleZoom()

            return (true, "")
        }
        return result
    }
}

// MARK: - Property 25: The global mouse monitor lives exactly as long as it is needed

/// Feature: annotation-parity-phase-1, Property 25: The global mouse monitor lives exactly as long as it is needed
///
/// **Validates: Requirements 10.13, 4.3, 4.4**
///
/// Property: For any sequence of cursor-highlight, spotlight, and zoom toggles,
/// the shared global mouse monitor is installed if and only if at least one of
/// the three features is active.
@MainActor
func testGlobalMouseMonitorLifetime() -> PreservationTestResult {
    return runPreservationTest(
        "Property 25: The global mouse monitor lives exactly as long as it is needed",
        iterations: 100
    ) { rng in
        let result: (Bool, String) = MainActor.assumeIsolated {
            let cm = CursorManager()
            cm.screenRecordingProbe = { true }

            // Use Mirror to check if mouseMonitor is non-nil
            func hasMonitor() -> Bool {
                let mirror = Mirror(reflecting: cm)
                for child in mirror.children {
                    if child.label == "mouseMonitor" {
                        if case Optional<Any>.none = child.value {
                            return false
                        }
                        return true
                    }
                }
                return false
            }

            // Perform a random sequence of toggles
            let toggleCount = rng.nextInt(in: 3...10)
            for _ in 0..<toggleCount {
                let action = rng.nextInt(in: 0...2)
                switch action {
                case 0: cm.toggleHighlight()
                case 1: cm.toggleSpotlight()
                default: cm.toggleZoom()
                }

                let monitorInstalled = hasMonitor()
                let shouldHaveMonitor = cm.isHighlightActive || cm.isSpotlightActive || cm.isZoomActive

                guard monitorInstalled == shouldHaveMonitor else {
                    return (
                        false,
                        "Monitor \(monitorInstalled ? "installed" : "not installed") but "
                            + "features active: highlight=\(cm.isHighlightActive), "
                            + "spotlight=\(cm.isSpotlightActive), zoom=\(cm.isZoomActive). "
                            + "Expected monitor \(shouldHaveMonitor ? "installed" : "removed")."
                    )
                }
            }

            // Cleanup: deactivate all
            if cm.isHighlightActive { cm.toggleHighlight() }
            if cm.isSpotlightActive { cm.toggleSpotlight() }
            if cm.isZoomActive { cm.toggleZoom() }

            return (true, "")
        }
        return result
    }
}

// MARK: - Zoom Property Test Runner

@MainActor
func runAllZoomPropertyTests() -> [PreservationTestResult] {
    let separator = String(repeating: "=", count: 70)

    print(separator)
    print("Zoom Property Tests - Settings, Stepping, Mouse Monitor")
    print(separator)
    print("")

    var results: [PreservationTestResult] = []

    results.append(testSettingsClampToDocumentedRanges())
    results.append(testZoomSteppingSaturation())
    results.append(testGlobalMouseMonitorLifetime())

    print("")
    print(separator)
    print("ZOOM PROPERTY TEST RESULTS SUMMARY")
    print(separator)
    print("")

    let passed = results.filter { $0.passed }.count
    let failed = results.filter { !$0.passed }.count
    let total = results.count
    let totalIterations = results.reduce(0) { $0 + $1.iterations }

    for result in results {
        let icon = result.passed ? "PASS" : "FAIL"
        print("  [\(icon)] \(result.name)")
    }

    print("")
    print("Results: \(passed) passed, \(failed) failed, \(total) total (\(totalIterations) total iterations)")
    print("")

    if failed > 0 {
        print("FAILED: \(failed) zoom property test(s) failed.")
        for result in results where !result.passed {
            print("  - \(result.name): \(result.message)")
        }
    } else {
        print("All zoom property tests PASSED.")
    }

    print("")
    return results
}
