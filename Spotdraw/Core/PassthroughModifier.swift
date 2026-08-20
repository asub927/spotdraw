// PassthroughModifier.swift
// Configurable modifier for entering/leaving passthrough state.
// Discriminates left/right variants using device-dependent bits from
// the raw modifier flags. Fn uses the standard .function flag.

import Cocoa

// MARK: - PassthroughModifier

/// The modifier key that toggles passthrough on the annotation overlay.
/// `.off` disables held-modifier passthrough entirely — only Interactive Mode
/// toggle remains functional.
internal enum PassthroughModifier: Int, CaseIterable, Sendable {
    case off = 0
    case rightOption = 1
    case rightCommand = 2
    case fn = 3

    // MARK: - Display

    var displayName: String {
        switch self {
        case .off: "Off"
        case .rightOption: "Right Option"
        case .rightCommand: "Right Command"
        case .fn: "Fn (Globe)"
        }
    }

    // MARK: - Detection

    /// Returns `true` when the modifier represented by this case is currently
    /// held according to the given event flags.
    ///
    /// Left/right discrimination uses device-dependent bits in the raw value:
    /// - Right Option: `0x40` in the raw flags
    /// - Right Command: `0x10` in the raw flags
    /// - Fn: standard `.function` flag
    func isHeld(in flags: NSEvent.ModifierFlags) -> Bool {
        switch self {
        case .off:
            return false
        case .rightOption:
            // Device-dependent bit 0x40 indicates the right Option key.
            return flags.rawValue & 0x40 != 0
        case .rightCommand:
            // Device-dependent bit 0x10 indicates the right Command key.
            return flags.rawValue & 0x10 != 0
        case .fn:
            return flags.contains(.function)
        }
    }
}
