// HotkeyManager.swift
// Global keyboard event monitor for shortcut dispatch via ShortcutStore.
// Installs a CGEvent tap to intercept and consume matching key-down events
// before they reach other applications. Resolves events through ShortcutStore
// rather than hardcoded values.

import Cocoa

// MARK: - HotkeyManager

@MainActor public final class HotkeyManager {

    // MARK: - Properties

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Action handlers keyed by ShortcutAction.
    private var handlers: [ShortcutAction: () -> Void] = [:]

    /// While true, the tap consumes nothing so the Shortcuts settings tab can
    /// capture the raw combination. Requirement 7.16.
    nonisolated(unsafe) public var isRecordingSuppressed: Bool = false

    /// Static reference needed for the C callback (cannot capture context).
    /// Also accessible from ShortcutsSettingsTab for recording suppression.
    nonisolated(unsafe) public static var shared: HotkeyManager?

    // MARK: - Passthrough Modifier Observation

    /// Callback invoked when the passthrough modifier's held state changes.
    /// The Bool parameter is `true` when the modifier transitions to held, `false`
    /// when released. Installed only while the overlay is active (Requirement 8.11).
    public var onPassthroughModifierChange: ((Bool) -> Void)?

    /// The modifier being observed. Updated from SettingsManager when bindings change.
    public var passthroughModifier: PassthroughModifier = .rightOption

    /// Tracks the last-known held state to emit change callbacks only on transitions.
    private var passthroughModifierWasHeld = false

    /// The global flagsChanged monitor, installed while overlay is active.
    private var flagsMonitor: Any?

    // MARK: - Init

    public init() {
        HotkeyManager.shared = self
        setupEventTap()
    }

    // MARK: - Registration

    /// Registers a handler closure to be invoked when the given shortcut action is triggered.
    public func register(action: ShortcutAction, handler: @escaping () -> Void) {
        handlers[action] = handler
    }

    // MARK: - CGEvent Tap Setup

    private func setupEventTap() {
        guard AXIsProcessTrusted() else {
            NSLog("[HotkeyManager] Accessibility permission not granted — skipping CGEvent tap. Global shortcuts will not work.")
            return
        }

        let eventMask = (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: HotkeyManager.eventTapCallback,
            userInfo: nil
        ) else {
            NSLog("[HotkeyManager] Failed to create CGEvent tap. Global shortcuts will not work.")
            return
        }

        eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // MARK: - Event Tap Callback

    private static let eventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
        // Handle tap being disabled by the system.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let shared = HotkeyManager.shared, let tap = shared.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passRetained(event)
        }

        guard let shared = HotkeyManager.shared else {
            return Unmanaged.passRetained(event)
        }

        // While recording is suppressed, pass everything through so the
        // Shortcuts tab can capture the raw combination (Requirement 7.16).
        if shared.isRecordingSuppressed {
            return Unmanaged.passRetained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // Resolve through ShortcutStore (Requirement 6.9)
        guard let action = ShortcutStore.shared.resolveGlobal(keyCode: keyCode, cgFlags: flags) else {
            return Unmanaged.passRetained(event)
        }

        // Only consume if we have a handler registered for this action
        guard let handler = shared.handlers[action] else {
            return Unmanaged.passRetained(event)
        }

        // Match found — dispatch handler on main thread and consume the event (Requirement 6.15).
        DispatchQueue.main.async {
            handler()
        }
        return nil
    }

    // MARK: - Passthrough Monitor Lifecycle

    /// Installs the global flagsChanged monitor for passthrough modifier observation.
    /// Call when the overlay activates. Safe to call multiple times — no-ops if already installed.
    public func installPassthroughMonitor() {
        guard flagsMonitor == nil else { return }
        passthroughModifierWasHeld = false
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }
            let isHeld = self.passthroughModifier.isHeld(in: event.modifierFlags)
            if isHeld != self.passthroughModifierWasHeld {
                self.passthroughModifierWasHeld = isHeld
                self.onPassthroughModifierChange?(isHeld)
            }
        }
    }

    /// Removes the global flagsChanged monitor. Call when the overlay deactivates.
    public func teardownPassthroughMonitor() {
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
        passthroughModifierWasHeld = false
    }

    // MARK: - Cleanup

    /// Disables the CGEvent tap and removes the run loop source.
    public func removeAllMonitors() {
        teardownPassthroughMonitor()

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil

        HotkeyManager.shared = nil
    }

    deinit {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        HotkeyManager.shared = nil
    }
}
