import Cocoa

// Initialize NSApplication to allow window creation in tests
let _ = NSApplication.shared

// Run preservation property tests first (these should PASS on unfixed code)
runAllPreservationTests()

// Run operation-stack property tests (Property 1: operation-stack invertibility)
_ = runAllOperationPropertyTests()

// Run transform property tests (Property 3: Translation accumulation)
runAllTransformPropertyTests()

// Run text property tests (Property 6: Fade removal covers every item type;
// Property 7: Text commit accepts exactly the non-empty strings)
MainActor.assumeIsolated {
    runAllTextPropertyTests()
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
