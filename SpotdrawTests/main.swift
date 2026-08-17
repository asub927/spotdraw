import Cocoa

// Initialize NSApplication to allow window creation in tests
let _ = NSApplication.shared

// Run preservation property tests first (these should PASS on unfixed code)
runAllPreservationTests()

// Run bug condition exploration tests (these are expected to FAIL on unfixed code)
// Note: runAllTests() calls exit() internally based on results
MainActor.assumeIsolated {
    runAllTests()
}
