// ShortcutPropertyTests.swift
// Property-based tests for the customizable shortcut system.
// Properties 16–20 as defined in the design document.

import Cocoa
@testable import SpotdrawCore

// MARK: - Test Result

struct ShortcutPropertyResult {
    let name: String
    let passed: Bool
    let message: String
}

// MARK: - Runner

func runAllShortcutPropertyTests() -> [ShortcutPropertyResult] {
    var results: [ShortcutPropertyResult] = []

    results.append(testProperty16_BindingPersistenceRoundTrips())
    results.append(testProperty17_ScopeUniquenessAndConflictDetection())
    results.append(testProperty18_AssignmentAndResolutionRoundTrip())
    results.append(testProperty19_CorruptDataYieldsDefaults())
    results.append(testProperty20_ResetRestoresDefaultsAndIsIdempotent())

    let passCount = results.filter(\.passed).count
    let failCount = results.count - passCount
    print("ShortcutPropertyTests: \(passCount)/\(results.count) passed, \(failCount) failed")
    for result in results where !result.passed {
        print("  FAILED: \(result.name) — \(result.message)")
    }

    return results
}

// MARK: - Generators

/// Generates a random key code in a realistic range.
private func randomKeyCode(_ rng: inout SimplePRNG) -> UInt16 {
    UInt16(rng.nextInt(in: 0...127))
}

/// Generates a random modifier set (subset of control, shift, option, command).
private func randomModifiers(_ rng: inout SimplePRNG) -> NSEvent.ModifierFlags {
    var flags: NSEvent.ModifierFlags = []
    if rng.nextBool() { flags.insert(.control) }
    if rng.nextBool() { flags.insert(.shift) }
    if rng.nextBool() { flags.insert(.option) }
    if rng.nextBool() { flags.insert(.command) }
    return flags
}

/// Generates a random KeyBinding.
private func randomBinding(_ rng: inout SimplePRNG) -> KeyBinding {
    KeyBinding(keyCode: randomKeyCode(&rng), modifiers: randomModifiers(&rng))
}

/// Picks a random ShortcutAction.
private func randomAction(_ rng: inout SimplePRNG) -> ShortcutAction {
    let all = ShortcutAction.allCases
    let index = rng.nextInt(in: 0...(all.count - 1))
    return all[index]
}

// MARK: - Property 16: Binding persistence round-trips

// Feature: annotation-parity-phase-1, Property 16: Binding persistence round-trips
/// For any complete assignment of bindings to actions, including actions carrying a
/// cleared marker and actions left at their defaults, persisting the store and
/// reloading it from UserDefaults yields a store that returns an equal binding —
/// or equal absence of binding — for every action.
/// **Validates: Requirements 6.5, 6.6, 6.8**
private func testProperty16_BindingPersistenceRoundTrips() -> ShortcutPropertyResult {
    let iterations = 100
    for i in 0..<iterations {
        var rng = SimplePRNG(seed: UInt64(i) + 16000)
        ShortcutStore.shared._resetForTesting()

        // Apply random operations: assign, clear, or leave at default
        for action in ShortcutAction.allCases {
            let choice = rng.nextInt(in: 0...2)
            switch choice {
            case 0:
                // Assign a random binding
                let binding = randomBinding(&rng)
                ShortcutStore.shared.assign(binding, to: action)
            case 1:
                // Clear
                ShortcutStore.shared.clear(action)
            default:
                // Leave at default
                break
            }
        }

        // Snapshot bindings before persist
        var expected: [ShortcutAction: KeyBinding?] = [:]
        for action in ShortcutAction.allCases {
            expected[action] = ShortcutStore.shared.binding(for: action)
        }

        // Persist — this writes to UserDefaults
        // The persist is called internally by assign/clear, but let's simulate
        // a reload by reading the data and loading it
        let data = UserDefaults.standard.data(forKey: "shortcutBindings")
        ShortcutStore.shared._resetForTesting()
        ShortcutStore.shared._loadFromData(data)

        // Verify round-trip
        for action in ShortcutAction.allCases {
            let actual = ShortcutStore.shared.binding(for: action)
            let exp = expected[action] ?? nil
            if actual != exp {
                ShortcutStore.shared._resetForTesting()
                return ShortcutPropertyResult(
                    name: "Property 16: Binding persistence round-trips",
                    passed: false,
                    message: "Iteration \(i): action \(action) expected \(String(describing: exp)) got \(String(describing: actual))"
                )
            }
        }
    }
    ShortcutStore.shared._resetForTesting()
    return ShortcutPropertyResult(name: "Property 16: Binding persistence round-trips", passed: true, message: "")
}

// MARK: - Property 17: Bindings are unique within a scope and conflict detection is exact

// Feature: annotation-parity-phase-1, Property 17: Bindings are unique within a scope and conflict detection is exact
/// For any sequence of assign, clear, reset, and confirmed-replacement operations,
/// no two actions in the same dispatch scope hold equal bindings; and for any candidate
/// binding and action, conflictingAction(for:excluding:) returns a non-nil result
/// precisely when some other action in the same scope holds that binding.
/// **Validates: Requirements 4.2, 7.8, 7.9**
private func testProperty17_ScopeUniquenessAndConflictDetection() -> ShortcutPropertyResult {
    let iterations = 100
    for i in 0..<iterations {
        var rng = SimplePRNG(seed: UInt64(i) + 17000)
        ShortcutStore.shared._resetForTesting()

        // Apply a random sequence of operations
        let opCount = rng.nextInt(in: 5...24)
        for _ in 0..<opCount {
            let op = rng.nextInt(in: 0...3)
            let action = randomAction(&rng)
            switch op {
            case 0:
                ShortcutStore.shared.assign(randomBinding(&rng), to: action)
            case 1:
                ShortcutStore.shared.clear(action)
            case 2:
                ShortcutStore.shared.reset(action)
            default:
                // Confirmed replacement: assign to one, clear the conflict
                let binding = randomBinding(&rng)
                if let conflict = ShortcutStore.shared.conflictingAction(for: binding, excluding: action) {
                    ShortcutStore.shared.clear(conflict)
                }
                ShortcutStore.shared.assign(binding, to: action)
            }
        }

        // Verify uniqueness within each scope
        var globalBindings: [KeyBinding: ShortcutAction] = [:]
        var overlayBindings: [KeyBinding: ShortcutAction] = [:]

        for action in ShortcutAction.allCases {
            guard let binding = ShortcutStore.shared.binding(for: action) else { continue }
            switch action.scope {
            case .global:
                if let existing = globalBindings[binding] {
                    ShortcutStore.shared._resetForTesting()
                    return ShortcutPropertyResult(
                        name: "Property 17: Scope uniqueness and conflict detection",
                        passed: false,
                        message: "Iteration \(i): duplicate global binding \(binding.displayString) for \(action) and \(existing)"
                    )
                }
                globalBindings[binding] = action
            case .overlay:
                if let existing = overlayBindings[binding] {
                    ShortcutStore.shared._resetForTesting()
                    return ShortcutPropertyResult(
                        name: "Property 17: Scope uniqueness and conflict detection",
                        passed: false,
                        message: "Iteration \(i): duplicate overlay binding \(binding.displayString) for \(action) and \(existing)"
                    )
                }
                overlayBindings[binding] = action
            }
        }

        // Verify conflict detection for a random sample of bindings
        for _ in 0..<10 {
            let testBinding = randomBinding(&rng)
            let excludedAction = randomAction(&rng)
            let conflict = ShortcutStore.shared.conflictingAction(for: testBinding, excluding: excludedAction)

            // Manually check: is there another action in the same scope with this binding?
            let scope = excludedAction.scope
            var expectedConflict: ShortcutAction? = nil
            for action in ShortcutAction.allCases where action != excludedAction && action.scope == scope {
                if ShortcutStore.shared.binding(for: action) == testBinding {
                    expectedConflict = action
                    break
                }
            }

            if conflict != expectedConflict {
                ShortcutStore.shared._resetForTesting()
                return ShortcutPropertyResult(
                    name: "Property 17: Scope uniqueness and conflict detection",
                    passed: false,
                    message: "Iteration \(i): conflictingAction for \(testBinding.displayString) excluding \(excludedAction) returned \(String(describing: conflict)) expected \(String(describing: expectedConflict))"
                )
            }
        }
    }
    ShortcutStore.shared._resetForTesting()
    return ShortcutPropertyResult(name: "Property 17: Scope uniqueness and conflict detection", passed: true, message: "")
}

// MARK: - Property 18: Assignment and resolution round-trip

// Feature: annotation-parity-phase-1, Property 18: Assignment and resolution round-trip, and cleared actions are unresolvable
/// For any action and binding valid for that action's scope, assigning then resolving
/// returns the action; after reassigning, the previous binding no longer resolves;
/// after clearing, binding(for:) returns nil and resolve does not return it.
/// **Validates: Requirements 6.9, 6.10, 6.11, 6.13, 7.7, 7.12, 7.16**
private func testProperty18_AssignmentAndResolutionRoundTrip() -> ShortcutPropertyResult {
    let iterations = 100
    for i in 0..<iterations {
        var rng = SimplePRNG(seed: UInt64(i) + 18000)
        ShortcutStore.shared._resetForTesting()

        let action = randomAction(&rng)
        var binding = randomBinding(&rng)

        // Ensure global actions have at least one modifier
        if action.scope == .global && binding.modifierRawValue == 0 {
            binding = KeyBinding(keyCode: binding.keyCode, modifiers: .control)
        }

        // Clear any conflicting actions to ensure clean assignment
        if let conflict = ShortcutStore.shared.conflictingAction(for: binding, excluding: action) {
            ShortcutStore.shared.clear(conflict)
        }

        // Assign and verify resolution
        ShortcutStore.shared.assign(binding, to: action)
        let resolved = ShortcutStore.shared.resolve(keyCode: binding.keyCode, modifiers: binding.modifiers, scope: action.scope)
        if resolved != action {
            ShortcutStore.shared._resetForTesting()
            return ShortcutPropertyResult(
                name: "Property 18: Assignment and resolution round-trip",
                passed: false,
                message: "Iteration \(i): after assign, resolve returned \(String(describing: resolved)) not \(action)"
            )
        }

        // Reassign to a different binding
        var newBinding = randomBinding(&rng)
        if action.scope == .global && newBinding.modifierRawValue == 0 {
            newBinding = KeyBinding(keyCode: newBinding.keyCode, modifiers: .control)
        }
        if let conflict = ShortcutStore.shared.conflictingAction(for: newBinding, excluding: action) {
            ShortcutStore.shared.clear(conflict)
        }
        ShortcutStore.shared.assign(newBinding, to: action)

        // Old binding should no longer resolve to this action
        let oldResolved = ShortcutStore.shared.resolve(keyCode: binding.keyCode, modifiers: binding.modifiers, scope: action.scope)
        if oldResolved == action {
            ShortcutStore.shared._resetForTesting()
            return ShortcutPropertyResult(
                name: "Property 18: Assignment and resolution round-trip",
                passed: false,
                message: "Iteration \(i): old binding still resolves to \(action) after reassign"
            )
        }

        // Clear and verify unresolvable
        ShortcutStore.shared.clear(action)
        let afterClear = ShortcutStore.shared.binding(for: action)
        if afterClear != nil {
            ShortcutStore.shared._resetForTesting()
            return ShortcutPropertyResult(
                name: "Property 18: Assignment and resolution round-trip",
                passed: false,
                message: "Iteration \(i): after clear, binding is \(String(describing: afterClear)) not nil"
            )
        }
        let clearedResolved = ShortcutStore.shared.resolve(keyCode: newBinding.keyCode, modifiers: newBinding.modifiers, scope: action.scope)
        if clearedResolved == action {
            ShortcutStore.shared._resetForTesting()
            return ShortcutPropertyResult(
                name: "Property 18: Assignment and resolution round-trip",
                passed: false,
                message: "Iteration \(i): after clear, new binding still resolves to \(action)"
            )
        }
    }
    ShortcutStore.shared._resetForTesting()
    return ShortcutPropertyResult(name: "Property 18: Assignment and resolution round-trip", passed: true, message: "")
}

// MARK: - Property 19: Corrupt persisted data yields defaults without trapping

// Feature: annotation-parity-phase-1, Property 19: Corrupt persisted data yields defaults without trapping
/// For any byte sequence written to the shortcut-bindings persistence key,
/// loading the store completes without trapping and returns each action's default binding.
/// **Validates: Requirements 6.12**
private func testProperty19_CorruptDataYieldsDefaults() -> ShortcutPropertyResult {
    let iterations = 100
    for i in 0..<iterations {
        var rng = SimplePRNG(seed: UInt64(i) + 19000)

        // Generate random garbage data
        let length = rng.nextInt(in: 1...256)
        var bytes = [UInt8](repeating: 0, count: length)
        for j in 0..<length {
            bytes[j] = UInt8(rng.nextInt(in: 0...255))
        }
        let data = Data(bytes)

        // Load corrupt data — must not trap
        ShortcutStore.shared._loadFromData(data)

        // Every action should return its default binding
        for action in ShortcutAction.allCases {
            let binding = ShortcutStore.shared.binding(for: action)
            if binding != action.defaultBinding {
                ShortcutStore.shared._resetForTesting()
                return ShortcutPropertyResult(
                    name: "Property 19: Corrupt persisted data yields defaults",
                    passed: false,
                    message: "Iteration \(i): action \(action) returned \(String(describing: binding)) not default after corrupt data"
                )
            }
        }
    }

    // Also test nil data
    ShortcutStore.shared._loadFromData(nil)
    for action in ShortcutAction.allCases {
        let binding = ShortcutStore.shared.binding(for: action)
        if binding != action.defaultBinding {
            ShortcutStore.shared._resetForTesting()
            return ShortcutPropertyResult(
                name: "Property 19: Corrupt persisted data yields defaults",
                passed: false,
                message: "action \(action) returned non-default after nil data"
            )
        }
    }

    ShortcutStore.shared._resetForTesting()
    return ShortcutPropertyResult(name: "Property 19: Corrupt persisted data yields defaults", passed: true, message: "")
}

// MARK: - Property 20: Reset restores defaults and is idempotent

// Feature: annotation-parity-phase-1, Property 20: Reset restores defaults and is idempotent
/// For any sequence of assign and clear operations, resetting all actions yields, for
/// every action, exactly that action's default binding; and applying reset-all a second
/// time changes nothing.
/// **Validates: Requirements 7.13, 7.14**
private func testProperty20_ResetRestoresDefaultsAndIsIdempotent() -> ShortcutPropertyResult {
    let iterations = 100
    for i in 0..<iterations {
        var rng = SimplePRNG(seed: UInt64(i) + 20000)
        ShortcutStore.shared._resetForTesting()

        // Apply random mutations
        let opCount = rng.nextInt(in: 5...34)
        for _ in 0..<opCount {
            let action = randomAction(&rng)
            if rng.nextBool() {
                ShortcutStore.shared.assign(randomBinding(&rng), to: action)
            } else {
                ShortcutStore.shared.clear(action)
            }
        }

        // Reset all
        ShortcutStore.shared.resetAll()

        // Verify all defaults restored
        for action in ShortcutAction.allCases {
            let binding = ShortcutStore.shared.binding(for: action)
            if binding != action.defaultBinding {
                ShortcutStore.shared._resetForTesting()
                return ShortcutPropertyResult(
                    name: "Property 20: Reset restores defaults and is idempotent",
                    passed: false,
                    message: "Iteration \(i): action \(action) returned \(String(describing: binding)) not default after resetAll"
                )
            }
        }

        // Apply resetAll again — must be idempotent
        ShortcutStore.shared.resetAll()
        for action in ShortcutAction.allCases {
            let binding = ShortcutStore.shared.binding(for: action)
            if binding != action.defaultBinding {
                ShortcutStore.shared._resetForTesting()
                return ShortcutPropertyResult(
                    name: "Property 20: Reset restores defaults and is idempotent",
                    passed: false,
                    message: "Iteration \(i): action \(action) not idempotent after second resetAll"
                )
            }
        }
    }
    ShortcutStore.shared._resetForTesting()
    return ShortcutPropertyResult(name: "Property 20: Reset restores defaults and is idempotent", passed: true, message: "")
}
