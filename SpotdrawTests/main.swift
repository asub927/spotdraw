import Cocoa

// Initialize NSApplication to allow window creation in tests
let _ = NSApplication.shared

// Run preservation property tests first (these should PASS on unfixed code)
runAllPreservationTests()

// Run operation-stack property tests (Property 1: operation-stack invertibility)
_ = runAllOperationPropertyTests()

// Run transform property tests (Property 3: Translation accumulation)
runAllTransformPropertyTests()

// Run bug condition exploration tests (these are expected to FAIL on unfixed code)
// Note: runAllTests() calls exit() internally based on results
MainActor.assumeIsolated {
    runAllTests()
}
