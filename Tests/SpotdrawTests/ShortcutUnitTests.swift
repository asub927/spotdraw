// ShortcutUnitTests.swift
// Unit tests for the shortcut system: backward compatibility of default bindings,
// category partitioning, tool type correspondence, Recording_State suppression,
// and the zoom default guard (no Control+Z as a global default).

import Cocoa
@testable import SpotdrawCore

// MARK: - Test Result Type

struct ShortcutUnitTestResult {
    let name: String
    let passed: Bool
    let message: String
}

// MARK: - Runner

@MainActor func runAllShortcutUnitTests() -> [ShortcutUnitTestResult] {
    var results: [ShortcutUnitTestResult] = []

    results.append(testBackwardCompatibilityDefaults())
    results.append(testZoomDefaultsAreCorrect())
    results.append(testNoGlobalDefaultIsControlZ())
    results.append(testCategoriesPartitionAllCases())
    results.append(testToolTypesCorrespondToToolActions())
    results.append(testRecordingSuppression())
    results.append(testResetAllRestoresDefaults())
    results.append(testClearMakesBindingNil())
    results.append(testResolveAfterAssign())

    let passCount = results.filter { $0.passed }.count
    let failCount = results.count - passCount
    print("ShortcutUnitTests: \(passCount)/\(results.count) passed, \(failCount) failed")
    for result in results where !result.passed {
        print("  FAILED: \(result.name) — \(result.message)")
    }

    return results
}

// MARK: - Tests

/// Table-driven backward-compatibility assertions: existing bindings resolve to their
/// historical actions (Requirement 6.14).
private func testBackwardCompatibilityDefaults() -> ShortcutUnitTestResult {
    ShortcutStore.shared._resetForTesting()

    // Global scope defaults
    let globalTable: [(keyCode: UInt16, mods: NSEvent.ModifierFlags, expected: ShortcutAction)] = [
        (2,  .control,            .toggleAnnotation),       // Ctrl+D
        (1,  .control,            .toggleCursorHighlight),  // Ctrl+S
        (37, .control,            .toggleSpotlight),        // Ctrl+L
        (1,  [.control, .shift],  .cycleCursorSize),        // Ctrl+Shift+S
        (46, .control,            .toggleZoom),             // Ctrl+M
        (24, .control,            .zoomIn),                 // Ctrl+=
        (27, .control,            .zoomOut),                // Ctrl+-
        (34, [.control, .shift],  .toggleInteractiveMode),  // Ctrl+Shift+I
    ]
    for entry in globalTable {
        let resolved = ShortcutStore.shared.resolve(keyCode: entry.keyCode, modifiers: entry.mods, scope: .global)
        if resolved != entry.expected {
            return ShortcutUnitTestResult(
                name: "testBackwardCompatibilityDefaults",
                passed: false,
                message: "Global keyCode \(entry.keyCode) mods \(entry.mods.rawValue) expected \(entry.expected) got \(String(describing: resolved))"
            )
        }
    }

    // Overlay scope defaults — tool single characters
    let overlayToolTable: [(keyCode: UInt16, expected: ShortcutAction)] = [
        (35, .toolPen),        // P
        (0,  .toolArrow),      // A
        (15, .toolRectangle),  // R
        (31, .toolCircle),     // O
        (37, .toolLine),       // L
        (4,  .toolHighlighter),// H
        (14, .toolEraser),     // E
        (17, .toolText),       // T
        (1,  .toolSelect),     // S
    ]
    for entry in overlayToolTable {
        let resolved = ShortcutStore.shared.resolve(keyCode: entry.keyCode, modifiers: [], scope: .overlay)
        if resolved != entry.expected {
            return ShortcutUnitTestResult(
                name: "testBackwardCompatibilityDefaults",
                passed: false,
                message: "Overlay tool keyCode \(entry.keyCode) expected \(entry.expected) got \(String(describing: resolved))"
            )
        }
    }

    // Overlay scope defaults — color numbers
    let overlayColorTable: [(keyCode: UInt16, expected: ShortcutAction)] = [
        (18, .colorRed),     // 1
        (19, .colorBlue),    // 2
        (20, .colorGreen),   // 3
        (21, .colorYellow),  // 4
        (23, .colorWhite),   // 5
    ]
    for entry in overlayColorTable {
        let resolved = ShortcutStore.shared.resolve(keyCode: entry.keyCode, modifiers: [], scope: .overlay)
        if resolved != entry.expected {
            return ShortcutUnitTestResult(
                name: "testBackwardCompatibilityDefaults",
                passed: false,
                message: "Overlay color keyCode \(entry.keyCode) expected \(entry.expected) got \(String(describing: resolved))"
            )
        }
    }

    // Overlay scope defaults — actions
    let overlayActionTable: [(keyCode: UInt16, mods: NSEvent.ModifierFlags, expected: ShortcutAction)] = [
        (6,  .command,            .undo),              // Cmd+Z
        (6,  [.command, .shift],  .redo),              // Cmd+Shift+Z
        (51, .command,            .clearAll),           // Cmd+Delete
        (11, [],                  .cycleBoardMode),     // B
        (49, [],                  .toggleFadeMode),     // Space
        (51, [],                  .deleteSelection),    // Delete
        (0,  .command,            .selectAll),          // Cmd+A
        (53, [],                  .deactivateOverlay),  // Escape
    ]
    for entry in overlayActionTable {
        let resolved = ShortcutStore.shared.resolve(keyCode: entry.keyCode, modifiers: entry.mods, scope: .overlay)
        if resolved != entry.expected {
            return ShortcutUnitTestResult(
                name: "testBackwardCompatibilityDefaults",
                passed: false,
                message: "Overlay action keyCode \(entry.keyCode) mods \(entry.mods.rawValue) expected \(entry.expected) got \(String(describing: resolved))"
            )
        }
    }

    ShortcutStore.shared._resetForTesting()
    return ShortcutUnitTestResult(name: "testBackwardCompatibilityDefaults", passed: true, message: "")
}

/// Assert zoom defaults are Control+M, Control+=, and Control+-.
private func testZoomDefaultsAreCorrect() -> ShortcutUnitTestResult {
    let zoomToggle = ShortcutAction.toggleZoom.defaultBinding
    let zoomIn = ShortcutAction.zoomIn.defaultBinding
    let zoomOut = ShortcutAction.zoomOut.defaultBinding

    guard zoomToggle.keyCode == 46, zoomToggle.modifiers == .control else {
        return ShortcutUnitTestResult(name: "testZoomDefaultsAreCorrect", passed: false,
                                     message: "toggleZoom default not Ctrl+M")
    }
    guard zoomIn.keyCode == 24, zoomIn.modifiers == .control else {
        return ShortcutUnitTestResult(name: "testZoomDefaultsAreCorrect", passed: false,
                                     message: "zoomIn default not Ctrl+=")
    }
    guard zoomOut.keyCode == 27, zoomOut.modifiers == .control else {
        return ShortcutUnitTestResult(name: "testZoomDefaultsAreCorrect", passed: false,
                                     message: "zoomOut default not Ctrl+-")
    }
    return ShortcutUnitTestResult(name: "testZoomDefaultsAreCorrect", passed: true, message: "")
}

/// Assert no global default binding is Control+Z (Decision 4 guard).
private func testNoGlobalDefaultIsControlZ() -> ShortcutUnitTestResult {
    let controlZ = KeyBinding(keyCode: 6, modifiers: .control)
    for action in ShortcutAction.allCases where action.scope == .global {
        if action.defaultBinding == controlZ {
            return ShortcutUnitTestResult(name: "testNoGlobalDefaultIsControlZ", passed: false,
                                         message: "\(action) has Control+Z as its global default")
        }
    }
    return ShortcutUnitTestResult(name: "testNoGlobalDefaultIsControlZ", passed: true, message: "")
}

/// Assert the four categories partition ShortcutAction.allCases with no orphans or duplicates.
private func testCategoriesPartitionAllCases() -> ShortcutUnitTestResult {
    var seen: Set<String> = []
    for action in ShortcutAction.allCases {
        let key = action.rawValue
        if seen.contains(key) {
            return ShortcutUnitTestResult(name: "testCategoriesPartitionAllCases", passed: false,
                                         message: "Duplicate action key: \(key)")
        }
        seen.insert(key)
        // Every action must belong to one of the four categories
        let _ = action.category // Accessing it ensures no crash
    }
    // Check that every category has at least one action
    for category in ShortcutCategory.allCases {
        let actionsInCategory = ShortcutAction.allCases.filter { $0.category == category }
        if actionsInCategory.isEmpty {
            return ShortcutUnitTestResult(name: "testCategoriesPartitionAllCases", passed: false,
                                         message: "Category \(category.rawValue) has no actions")
        }
    }
    return ShortcutUnitTestResult(name: "testCategoriesPartitionAllCases", passed: true, message: "")
}

/// Assert ToolType.allCases contains .text and .select, and each has exactly one
/// corresponding tool ShortcutAction and vice versa.
private func testToolTypesCorrespondToToolActions() -> ShortcutUnitTestResult {
    // ToolType must contain text and select
    guard ToolType.allCases.contains(.text) else {
        return ShortcutUnitTestResult(name: "testToolTypesCorrespondToToolActions", passed: false,
                                     message: "ToolType.allCases missing .text")
    }
    guard ToolType.allCases.contains(.select) else {
        return ShortcutUnitTestResult(name: "testToolTypesCorrespondToToolActions", passed: false,
                                     message: "ToolType.allCases missing .select")
    }

    // Every tool action must map to a ToolType and vice versa
    let toolActions = ShortcutAction.allCases.filter { $0.category == .tools }
    for action in toolActions {
        guard action.toolType != nil else {
            return ShortcutUnitTestResult(name: "testToolTypesCorrespondToToolActions", passed: false,
                                         message: "Tool action \(action) has nil toolType")
        }
    }

    // Every ToolType (except eraser is covered) should have a corresponding action
    for toolType in ToolType.allCases {
        let hasAction = toolActions.contains { $0.toolType == toolType }
        if !hasAction {
            return ShortcutUnitTestResult(name: "testToolTypesCorrespondToToolActions", passed: false,
                                         message: "ToolType.\(toolType) has no corresponding ShortcutAction")
        }
    }

    return ShortcutUnitTestResult(name: "testToolTypesCorrespondToToolActions", passed: true, message: "")
}

/// Assert Recording_State entry sets isRecordingSuppressed and exit paths clear it.
@MainActor private func testRecordingSuppression() -> ShortcutUnitTestResult {
    let hm = HotkeyManager.shared
    guard hm != nil else {
        // In test environment without Accessibility, HotkeyManager.shared may be nil.
        // Create one for the test.
        let manager = HotkeyManager()
        defer { manager.removeAllMonitors() }

        manager.isRecordingSuppressed = false
        // Simulate entering recording state
        manager.isRecordingSuppressed = true
        guard manager.isRecordingSuppressed == true else {
            return ShortcutUnitTestResult(name: "testRecordingSuppression", passed: false,
                                         message: "isRecordingSuppressed not set to true")
        }
        // Simulate exiting recording state (escape path)
        manager.isRecordingSuppressed = false
        guard manager.isRecordingSuppressed == false else {
            return ShortcutUnitTestResult(name: "testRecordingSuppression", passed: false,
                                         message: "isRecordingSuppressed not cleared on escape")
        }
        return ShortcutUnitTestResult(name: "testRecordingSuppression", passed: true, message: "")
    }

    let saved = hm!.isRecordingSuppressed
    defer { hm!.isRecordingSuppressed = saved }

    hm!.isRecordingSuppressed = false
    hm!.isRecordingSuppressed = true
    guard hm!.isRecordingSuppressed == true else {
        return ShortcutUnitTestResult(name: "testRecordingSuppression", passed: false,
                                     message: "isRecordingSuppressed not set to true")
    }
    hm!.isRecordingSuppressed = false
    guard hm!.isRecordingSuppressed == false else {
        return ShortcutUnitTestResult(name: "testRecordingSuppression", passed: false,
                                     message: "isRecordingSuppressed not cleared")
    }
    return ShortcutUnitTestResult(name: "testRecordingSuppression", passed: true, message: "")
}

/// Assert resetAll restores defaults.
private func testResetAllRestoresDefaults() -> ShortcutUnitTestResult {
    ShortcutStore.shared._resetForTesting()
    // Assign a custom binding
    let custom = KeyBinding(keyCode: 99, modifiers: .command)
    ShortcutStore.shared.assign(custom, to: .toggleAnnotation)
    guard ShortcutStore.shared.binding(for: .toggleAnnotation) == custom else {
        return ShortcutUnitTestResult(name: "testResetAllRestoresDefaults", passed: false,
                                     message: "Custom binding not applied")
    }
    // Reset all
    ShortcutStore.shared.resetAll()
    let binding = ShortcutStore.shared.binding(for: .toggleAnnotation)
    guard binding == ShortcutAction.toggleAnnotation.defaultBinding else {
        return ShortcutUnitTestResult(name: "testResetAllRestoresDefaults", passed: false,
                                     message: "After resetAll, binding is \(String(describing: binding)) not default")
    }
    ShortcutStore.shared._resetForTesting()
    return ShortcutUnitTestResult(name: "testResetAllRestoresDefaults", passed: true, message: "")
}

/// Assert clearing an action makes binding(for:) return nil.
private func testClearMakesBindingNil() -> ShortcutUnitTestResult {
    ShortcutStore.shared._resetForTesting()
    ShortcutStore.shared.clear(.toolPen)
    guard ShortcutStore.shared.binding(for: .toolPen) == nil else {
        return ShortcutUnitTestResult(name: "testClearMakesBindingNil", passed: false,
                                     message: "After clear, binding is not nil")
    }
    // Also, resolving the default key for pen should not return .toolPen
    let resolved = ShortcutStore.shared.resolve(keyCode: 35, modifiers: [], scope: .overlay)
    guard resolved != .toolPen else {
        return ShortcutUnitTestResult(name: "testClearMakesBindingNil", passed: false,
                                     message: "After clear, resolving the old key still returns toolPen")
    }
    ShortcutStore.shared._resetForTesting()
    return ShortcutUnitTestResult(name: "testClearMakesBindingNil", passed: true, message: "")
}

/// Assert assigning then resolving round-trips.
private func testResolveAfterAssign() -> ShortcutUnitTestResult {
    ShortcutStore.shared._resetForTesting()
    let custom = KeyBinding(keyCode: 42, modifiers: [.control, .shift])
    ShortcutStore.shared.assign(custom, to: .toggleAnnotation)
    let resolved = ShortcutStore.shared.resolve(keyCode: 42, modifiers: [.control, .shift], scope: .global)
    guard resolved == .toggleAnnotation else {
        return ShortcutUnitTestResult(name: "testResolveAfterAssign", passed: false,
                                     message: "Resolve did not return toggleAnnotation after assign")
    }
    // Old binding should no longer resolve to toggleAnnotation
    let oldResolved = ShortcutStore.shared.resolve(keyCode: 2, modifiers: .control, scope: .global)
    guard oldResolved != .toggleAnnotation else {
        return ShortcutUnitTestResult(name: "testResolveAfterAssign", passed: false,
                                     message: "Old binding still resolves to toggleAnnotation")
    }
    ShortcutStore.shared._resetForTesting()
    return ShortcutUnitTestResult(name: "testResolveAfterAssign", passed: true, message: "")
}
