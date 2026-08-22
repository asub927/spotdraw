import Cocoa
@testable import SpotdrawCore

print("TEST BINARY STARTING")
fflush(stdout)
// Initialize NSApplication to allow window creation in tests
let _ = NSApplication.shared
print("NSAPP INITIALIZED")
fflush(stdout)

print("ABOUT TO RUN PRESERVATION TESTS")
fflush(stdout)
fputs("STDERR: about to run preservation\n", stderr)
// Run preservation property tests first (these should PASS on unfixed code)
runAllPreservationTests()
fputs("STDERR: preservation done\n", stderr)

fputs("STDERR: about to run operation property\n", stderr)
// Run operation-stack property tests (Property 1: operation-stack invertibility)
_ = runAllOperationPropertyTests()
fputs("STDERR: operation done\n", stderr)

fputs("STDERR: about to run transform\n", stderr)
// Run transform property tests (Property 3: Translation accumulation)
runAllTransformPropertyTests()
fputs("STDERR: transform done\n", stderr)

fputs("STDERR: about to run text property\n", stderr)
// Run text property tests (Property 6: Fade removal covers every item type;
// Property 7: Text commit accepts exactly the non-empty strings)
MainActor.assumeIsolated {
    runAllTextPropertyTests()
}
fputs("STDERR: text done\n", stderr)

// Run selection property tests (Properties 10-15: Marquee, click, shift-click,
// staleness, move clamping, move undo threshold)
let selectionPropertyResults = runAllSelectionPropertyTests()
if selectionPropertyResults.contains(where: { !$0.passed }) {
    exit(1)
}

// Run ShapeGesture tests (overlay-gesture-extraction spec, Requirements 1.2–1.5)
let shapeGestureResults = runAllShapeGestureTests()
if shapeGestureResults.contains(where: { !$0.passed }) {
    exit(1)
}

// Run SelectInteraction tests (overlay-gesture-extraction spec, Requirements 2.3–2.5, 4.3)
let selectInteractionResults = runAllSelectInteractionTests()
if selectInteractionResults.contains(where: { !$0.passed }) {
    exit(1)
}

// Run ToolbarLayout tests (toolbar-panel-split spec, Requirements 2.2, 2.4, 3.2)
let toolbarLayoutResults = runAllToolbarLayoutTests()
if toolbarLayoutResults.contains(where: { !$0.passed }) {
    exit(1)
}

// Run zoom unit tests
let zoomUnitResults = MainActor.assumeIsolated {
    runAllZoomUnitTests()
}
if zoomUnitResults.contains(where: { !$0.passed }) {
    exit(1)
}

// Run zoom property tests (Properties 23-25: Settings clamping, zoom stepping,
// global mouse monitor lifetime)
let zoomPropertyResults = MainActor.assumeIsolated {
    runAllZoomPropertyTests()
}
if zoomPropertyResults.contains(where: { !$0.passed }) {
    exit(1)
}

// Run shortcut unit tests
let shortcutUnitResults = MainActor.assumeIsolated {
    runAllShortcutUnitTests()
}
if shortcutUnitResults.contains(where: { !$0.passed }) {
    exit(1)
}

// Run shortcut property tests (Properties 16-20)
let shortcutPropertyResults = runAllShortcutPropertyTests()
if shortcutPropertyResults.contains(where: { !$0.passed }) {
    exit(1)
}

// Run passthrough property tests (Properties 21, 22, 26)
let passthroughPropertyResults = MainActor.assumeIsolated {
    runAllPassthroughPropertyTests()
}
if passthroughPropertyResults.contains(where: { !$0.passed }) {
    exit(1)
}

// Run focused hosted OverlayView text interaction regressions (RED phase only).
let textInteractionRegressionResults = MainActor.assumeIsolated {
    runAllTextInteractionRegressionTests()
}
if textInteractionRegressionResults.contains(where: { !$0.passed }) {
    // Keep the RED phase observable to command-line callers. Without this guard,
    // the legacy exploration runner below exits 0 after printing its own results.
    exit(1)
}

// Run focused Tool submenu regression coverage.
let menuRegressionResult = MainActor.assumeIsolated {
    testToolMenuContainsTextAndDispatchesSelection()
}
if !menuRegressionResult.passed {
    exit(1)
}

// Run bug condition exploration tests (these are expected to FAIL on unfixed code)
// Note: runAllTests() calls exit() internally based on results
MainActor.assumeIsolated {
    runAllTests()
}
