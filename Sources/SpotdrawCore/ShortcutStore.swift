// ShortcutStore.swift
// Defines the customizable keyboard shortcut system: ShortcutScope, ShortcutCategory,
// KeyBinding, ShortcutAction, and the ShortcutStore that owns the mapping from action
// to binding, including defaults, persistence, conflict detection, and resolution.

import Cocoa

// MARK: - ShortcutScope

public enum ShortcutScope: Sendable {
    /// Global shortcuts intercepted by the CGEvent tap regardless of which app is key.
    case global
    /// Overlay shortcuts dispatched only while the annotation overlay is active and key.
    case overlay
}

// MARK: - ShortcutCategory

public enum ShortcutCategory: String, CaseIterable, Sendable {
    case global = "Global"
    case tools = "Annotation Tools"
    case colors = "Colors"
    case actions = "Actions"
}

// MARK: - KeyBinding

/// A key code paired with a set of modifier flags.
public struct KeyBinding: Codable, Hashable, Sendable {
    public let keyCode: UInt16
    /// Raw value of the device-independent NSEvent.ModifierFlags subset.
    public let modifierRawValue: UInt

    public init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) {
        self.keyCode = keyCode
        self.modifierRawValue = modifiers.intersection(.deviceIndependentFlagsMask).rawValue
    }

    public init(keyCode: UInt16, modifierRawValue: UInt) {
        self.keyCode = keyCode
        self.modifierRawValue = modifierRawValue
    }

    public var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierRawValue)
    }

    /// CGEventFlags equivalent for use in the CGEvent tap callback.
    public var cgEventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        return flags
    }

    /// Human-readable rendering of the binding, e.g. "⌃⇧S" or "Delete".
    public var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }

        let keyName = Self.keyCodeName(keyCode, modifiers: modifiers)
        parts.append(keyName)
        return parts.joined()
    }

    /// Returns a human-readable name for the given key code.
    private static func keyCodeName(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "Return"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "Tab"
        case 49: return "Space"
        case 50: return "`"
        case 51: return "Delete"
        case 53: return "Escape"
        case 55: return "⌘"
        case 56: return "⇧"
        case 57: return "⇪"
        case 58: return "⌥"
        case 59: return "⌃"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 105: return "F13"
        case 107: return "F14"
        case 109: return "F10"
        case 111: return "F12"
        case 113: return "F15"
        case 118: return "F4"
        case 119: return "End"
        case 120: return "F2"
        case 121: return "PageDown"
        case 122: return "F1"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "Key\(keyCode)"
        }
    }
}

// MARK: - ShortcutAction

/// Every bindable action in the application, grouped into categories.
/// The String raw value is the persistence key so future additions cannot invalidate stored bindings.
public enum ShortcutAction: String, CaseIterable, Sendable {
    // Global — Requirement 6.1
    case toggleAnnotation = "toggleAnnotation"
    case toggleCursorHighlight = "toggleCursorHighlight"
    case toggleSpotlight = "toggleSpotlight"
    case toggleZoom = "toggleZoom"
    case cycleCursorSize = "cycleCursorSize"
    case zoomIn = "zoomIn"
    case zoomOut = "zoomOut"
    case toggleInteractiveMode = "toggleInteractiveMode"

    // Tools — Requirement 6.2
    case toolPen = "toolPen"
    case toolArrow = "toolArrow"
    case toolRectangle = "toolRectangle"
    case toolCircle = "toolCircle"
    case toolLine = "toolLine"
    case toolHighlighter = "toolHighlighter"
    case toolEraser = "toolEraser"
    case toolText = "toolText"
    case toolSelect = "toolSelect"

    // Colors — Requirement 6.3
    case colorRed = "colorRed"
    case colorBlue = "colorBlue"
    case colorGreen = "colorGreen"
    case colorYellow = "colorYellow"
    case colorWhite = "colorWhite"

    // Overlay actions — Requirement 6.4
    case undo = "undo"
    case redo = "redo"
    case clearAll = "clearAll"
    case cycleBoardMode = "cycleBoardMode"
    case toggleFadeMode = "toggleFadeMode"
    case deleteSelection = "deleteSelection"
    case selectAll = "selectAll"
    case deactivateOverlay = "deactivateOverlay"

    // MARK: - Derived Properties

    public var scope: ShortcutScope {
        category == .global ? .global : .overlay
    }

    public var category: ShortcutCategory {
        switch self {
        case .toggleAnnotation, .toggleCursorHighlight, .toggleSpotlight,
             .toggleZoom, .cycleCursorSize, .zoomIn, .zoomOut, .toggleInteractiveMode:
            return .global
        case .toolPen, .toolArrow, .toolRectangle, .toolCircle, .toolLine,
             .toolHighlighter, .toolEraser, .toolText, .toolSelect:
            return .tools
        case .colorRed, .colorBlue, .colorGreen, .colorYellow, .colorWhite:
            return .colors
        case .undo, .redo, .clearAll, .cycleBoardMode, .toggleFadeMode,
             .deleteSelection, .selectAll, .deactivateOverlay:
            return .actions
        }
    }

    public var displayName: String {
        switch self {
        case .toggleAnnotation: return "Toggle Annotation"
        case .toggleCursorHighlight: return "Toggle Cursor Highlight"
        case .toggleSpotlight: return "Toggle Spotlight"
        case .toggleZoom: return "Toggle Zoom"
        case .cycleCursorSize: return "Cycle Cursor Size"
        case .zoomIn: return "Zoom In"
        case .zoomOut: return "Zoom Out"
        case .toggleInteractiveMode: return "Toggle Interactive Mode"
        case .toolPen: return "Pen"
        case .toolArrow: return "Arrow"
        case .toolRectangle: return "Rectangle"
        case .toolCircle: return "Circle"
        case .toolLine: return "Line"
        case .toolHighlighter: return "Highlighter"
        case .toolEraser: return "Eraser"
        case .toolText: return "Text"
        case .toolSelect: return "Select"
        case .colorRed: return "Red"
        case .colorBlue: return "Blue"
        case .colorGreen: return "Green"
        case .colorYellow: return "Yellow"
        case .colorWhite: return "White"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .clearAll: return "Clear All"
        case .cycleBoardMode: return "Cycle Board Mode"
        case .toggleFadeMode: return "Toggle Fade Mode"
        case .deleteSelection: return "Delete Selection"
        case .selectAll: return "Select All"
        case .deactivateOverlay: return "Deactivate Overlay"
        }
    }

    /// The default key binding for backward compatibility.
    /// Requirement 6.14: preserves Control+D, Control+S, Control+L, Control+Shift+S,
    /// and the existing single-character tool, color, board, and fade bindings.
    public var defaultBinding: KeyBinding {
        switch self {
        // Global shortcuts
        case .toggleAnnotation:      return KeyBinding(keyCode: 2, modifiers: .control)         // Ctrl+D
        case .toggleCursorHighlight: return KeyBinding(keyCode: 1, modifiers: .control)         // Ctrl+S
        case .toggleSpotlight:       return KeyBinding(keyCode: 37, modifiers: .control)        // Ctrl+L
        case .toggleZoom:            return KeyBinding(keyCode: 46, modifiers: .control)        // Ctrl+M
        case .cycleCursorSize:       return KeyBinding(keyCode: 1, modifiers: [.control, .shift]) // Ctrl+Shift+S
        case .zoomIn:                return KeyBinding(keyCode: 24, modifiers: .control)        // Ctrl+=
        case .zoomOut:               return KeyBinding(keyCode: 27, modifiers: .control)        // Ctrl+-
        case .toggleInteractiveMode: return KeyBinding(keyCode: 34, modifiers: [.control, .shift]) // Ctrl+Shift+I

        // Tool shortcuts (single character, overlay scope)
        case .toolPen:         return KeyBinding(keyCode: 35)  // P
        case .toolArrow:       return KeyBinding(keyCode: 0)   // A
        case .toolRectangle:   return KeyBinding(keyCode: 15)  // R
        case .toolCircle:      return KeyBinding(keyCode: 31)  // O
        case .toolLine:        return KeyBinding(keyCode: 37)  // L
        case .toolHighlighter: return KeyBinding(keyCode: 4)   // H
        case .toolEraser:      return KeyBinding(keyCode: 14)  // E
        case .toolText:        return KeyBinding(keyCode: 17)  // T
        case .toolSelect:      return KeyBinding(keyCode: 1)   // S

        // Color shortcuts (single character, overlay scope)
        case .colorRed:    return KeyBinding(keyCode: 18)  // 1
        case .colorBlue:   return KeyBinding(keyCode: 19)  // 2
        case .colorGreen:  return KeyBinding(keyCode: 20)  // 3
        case .colorYellow: return KeyBinding(keyCode: 21)  // 4
        case .colorWhite:  return KeyBinding(keyCode: 23)  // 5

        // Overlay action shortcuts
        case .undo:              return KeyBinding(keyCode: 6, modifiers: .command)             // Cmd+Z
        case .redo:              return KeyBinding(keyCode: 6, modifiers: [.command, .shift])   // Cmd+Shift+Z
        case .clearAll:          return KeyBinding(keyCode: 51, modifiers: .command)            // Cmd+Delete
        case .cycleBoardMode:    return KeyBinding(keyCode: 11)                                 // B
        case .toggleFadeMode:    return KeyBinding(keyCode: 49)                                 // Space
        case .deleteSelection:   return KeyBinding(keyCode: 51)                                 // Delete
        case .selectAll:         return KeyBinding(keyCode: 0, modifiers: .command)             // Cmd+A
        case .deactivateOverlay: return KeyBinding(keyCode: 53)                                 // Escape
        }
    }

    /// Maps a tool action to its ToolType. Returns nil for non-tool actions.
    public var toolType: ToolType? {
        switch self {
        case .toolPen: return .pen
        case .toolArrow: return .arrow
        case .toolRectangle: return .rectangle
        case .toolCircle: return .circle
        case .toolLine: return .line
        case .toolHighlighter: return .highlighter
        case .toolEraser: return .eraser
        case .toolText: return .text
        case .toolSelect: return .select
        default: return nil
        }
    }

    /// Maps a color action to its NSColor. Returns nil for non-color actions.
    public var color: NSColor? {
        switch self {
        case .colorRed: return .systemRed
        case .colorBlue: return .systemBlue
        case .colorGreen: return .systemGreen
        case .colorYellow: return .systemYellow
        case .colorWhite: return .white
        default: return nil
        }
    }
}

// MARK: - StoredBinding

/// Sentinel distinguishing "absent, use default" from "explicitly cleared by the user".
private struct StoredBinding: Codable {
    /// True when the user explicitly cleared this action.
    var cleared: Bool
    /// The assigned binding. Nil when `cleared` is true.
    var binding: KeyBinding?
}

// MARK: - ShortcutStore

/// Owns the mapping from ShortcutAction to KeyBinding, including defaults, persistence,
/// conflict detection, and resolution.
public final class ShortcutStore: @unchecked Sendable {

    // MARK: - Singleton

    public static let shared = ShortcutStore()

    /// Posted on every mutation so UI observers can refresh.
    public static let didChangeNotification = Notification.Name("ShortcutStoreDidChange")

    // MARK: - Storage

    /// Persisted overrides. Actions absent from this dictionary resolve to their defaults.
    private var overrides: [String: StoredBinding] = [:]

    /// Per-scope reverse index rebuilt on each mutation for O(1) resolution.
    private var globalIndex: [KeyBinding: ShortcutAction] = [:]
    private var overlayIndex: [KeyBinding: ShortcutAction] = [:]
    private var indicesBuilt = false

    private let persistenceKey = "shortcutBindings"

    // MARK: - Init

    private init() {}

    /// Ensures indices are built at least once (lazy initialization from defaults).
    private func ensureIndicesBuilt() {
        guard !indicesBuilt else { return }
        rebuildIndices()
    }

    /// Call once at app launch to load persisted bindings.
    public func loadFromDefaults() {
        if let data = UserDefaults.standard.data(forKey: persistenceKey) {
            do {
                let decoded = try JSONDecoder().decode([String: StoredBinding].self, from: data)
                // Validate: only keep entries whose key matches a known action
                overrides = decoded.filter { key, _ in
                    ShortcutAction(rawValue: key) != nil
                }
            } catch {
                NSLog("[ShortcutStore] Failed to decode persisted bindings: \(error). Falling back to defaults.")
                overrides = [:]
            }
        }
        rebuildIndices()
    }

    // MARK: - Query

    /// Returns the assigned binding for the action, or nil when cleared.
    public func binding(for action: ShortcutAction) -> KeyBinding? {
        ensureIndicesBuilt()
        return effectiveBinding(for: action)
    }

    /// Reverse lookup within a dispatch scope.
    public func resolve(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, scope: ShortcutScope) -> ShortcutAction? {
        ensureIndicesBuilt()
        let binding = KeyBinding(keyCode: keyCode, modifiers: modifiers)
        switch scope {
        case .global: return globalIndex[binding]
        case .overlay: return overlayIndex[binding]
        }
    }

    /// Reverse lookup using CGEventFlags for the event tap callback.
    public func resolveGlobal(keyCode: UInt16, cgFlags: CGEventFlags) -> ShortcutAction? {
        ensureIndicesBuilt()
        // Convert CGEventFlags to a KeyBinding for lookup
        let relevantFlags: CGEventFlags = [.maskControl, .maskShift, .maskAlternate, .maskCommand]
        let masked = cgFlags.intersection(relevantFlags)

        var nsFlags: NSEvent.ModifierFlags = []
        if masked.contains(.maskControl) { nsFlags.insert(.control) }
        if masked.contains(.maskShift) { nsFlags.insert(.shift) }
        if masked.contains(.maskAlternate) { nsFlags.insert(.option) }
        if masked.contains(.maskCommand) { nsFlags.insert(.command) }

        let binding = KeyBinding(keyCode: keyCode, modifiers: nsFlags)
        return globalIndex[binding]
    }

    /// Returns the action already holding this binding in the same scope, if any.
    public func conflictingAction(for binding: KeyBinding, excluding action: ShortcutAction) -> ShortcutAction? {
        let index = action.scope == .global ? globalIndex : overlayIndex
        if let existing = index[binding], existing != action {
            return existing
        }
        return nil
    }

    // MARK: - Mutation

    /// Assigns a binding to an action, enforcing within-scope uniqueness, and persists.
    /// If another action in the same scope already holds this binding, that action is
    /// cleared automatically (Requirement 4.2).
    public func assign(_ binding: KeyBinding, to action: ShortcutAction) {
        // Enforce uniqueness: clear any other action in the same scope holding this binding.
        for other in ShortcutAction.allCases where other != action && other.scope == action.scope {
            if effectiveBinding(for: other) == binding {
                overrides[other.rawValue] = StoredBinding(cleared: true, binding: nil)
            }
        }
        overrides[action.rawValue] = StoredBinding(cleared: false, binding: binding)
        persist()
        rebuildIndices()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    /// Clears the binding for an action (sets the cleared marker) and persists.
    public func clear(_ action: ShortcutAction) {
        overrides[action.rawValue] = StoredBinding(cleared: true, binding: nil)
        persist()
        rebuildIndices()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    /// Restores a single action to its default binding and persists.
    /// If the default binding conflicts with another action in the same scope, that
    /// other action is cleared (Requirement 4.2).
    public func reset(_ action: ShortcutAction) {
        overrides.removeValue(forKey: action.rawValue)
        // The default binding may now conflict with another action's current binding.
        let defaultBinding = action.defaultBinding
        for other in ShortcutAction.allCases where other != action && other.scope == action.scope {
            if effectiveBinding(for: other) == defaultBinding {
                overrides[other.rawValue] = StoredBinding(cleared: true, binding: nil)
            }
        }
        persist()
        rebuildIndices()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    /// Restores all actions to their default bindings and persists.
    public func resetAll() {
        overrides.removeAll()
        persist()
        rebuildIndices()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    // MARK: - Persistence

    private func persist() {
        do {
            let data = try JSONEncoder().encode(overrides)
            UserDefaults.standard.set(data, forKey: persistenceKey)
        } catch {
            NSLog("[ShortcutStore] Failed to encode bindings: \(error)")
        }
    }

    /// Rebuilds per-scope reverse indices from the current binding set.
    private func rebuildIndices() {
        globalIndex = [:]
        overlayIndex = [:]
        indicesBuilt = true  // Set before iterating to avoid recursive ensureIndicesBuilt

        for action in ShortcutAction.allCases {
            guard let binding = effectiveBinding(for: action) else { continue }
            switch action.scope {
            case .global:
                globalIndex[binding] = action
            case .overlay:
                overlayIndex[binding] = action
            }
        }
    }

    /// Returns the effective binding without triggering ensureIndicesBuilt (used during rebuild).
    private func effectiveBinding(for action: ShortcutAction) -> KeyBinding? {
        if let stored = overrides[action.rawValue] {
            if stored.cleared { return nil }
            return stored.binding ?? action.defaultBinding
        }
        return action.defaultBinding
    }

    // MARK: - Testing Support

    /// Resets overrides without persisting. Used only in tests.
    public func _resetForTesting() {
        overrides.removeAll()
        indicesBuilt = false
        rebuildIndices()
    }

    /// Loads from arbitrary data for testing corrupt persistence.
    public func _loadFromData(_ data: Data?) {
        if let data = data {
            do {
                let decoded = try JSONDecoder().decode([String: StoredBinding].self, from: data)
                overrides = decoded.filter { key, _ in
                    ShortcutAction(rawValue: key) != nil
                }
            } catch {
                NSLog("[ShortcutStore] Failed to decode persisted bindings: \(error). Falling back to defaults.")
                overrides = [:]
            }
        } else {
            overrides = [:]
        }
        rebuildIndices()
    }
}
