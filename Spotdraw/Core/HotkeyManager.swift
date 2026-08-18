// HotkeyManager.swift
// Global and local keyboard event monitors for shortcut registration and dispatch.
// Defines the GlobalShortcut enum mapping features to key codes and modifier flags,
// and provides the HotkeyManager class that installs a CGEvent tap to intercept
// and consume matching key-down events before they reach other applications.

import Cocoa

// MARK: - GlobalShortcut

internal enum GlobalShortcut {
    case toggleAnnotation       // Ctrl+D
    case toggleCursorHighlight  // Ctrl+S
    case toggleSpotlight        // Ctrl+L
    case toggleZoom             // Ctrl+Z
    case cycleCursorSize        // Ctrl+Shift+S

    var keyCode: UInt16 {
        switch self {
        case .toggleAnnotation: 2       // D
        case .toggleCursorHighlight: 1  // S
        case .toggleSpotlight: 37       // L
        case .toggleZoom: 6             // Z
        case .cycleCursorSize: 1        // S
        }
    }

    var modifiers: NSEvent.ModifierFlags {
        switch self {
        case .cycleCursorSize: [.control, .shift]
        default: .control
        }
    }

    /// CGEventFlags equivalent of the NSEvent modifier flags.
    var cgEventFlags: CGEventFlags {
        switch self {
        case .cycleCursorSize: [.maskControl, .maskShift]
        default: .maskControl
        }
    }
}

// MARK: - HotkeyManager

@MainActor internal final class HotkeyManager {

    // MARK: - Properties

    private typealias ShortcutHandler = () -> Void
    private typealias EventMonitorToken = Any

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var localMonitor: EventMonitorToken?
    private var handlers: [GlobalShortcut: ShortcutHandler] = [:]

    /// Static reference needed for the C callback (cannot capture context).
    private nonisolated(unsafe) static var shared: HotkeyManager?

    // MARK: - Init

    init() {
        HotkeyManager.shared = self
        setupEventTap()
        setupLocalMonitor()
    }

    // MARK: - Registration

    /// Registers a handler closure to be invoked when the given global shortcut is pressed.
    func register(shortcut: GlobalShortcut, handler: @escaping () -> Void) {
        handlers[shortcut] = handler
    }

    // MARK: - CGEvent Tap Setup

    private func setupEventTap() {
        guard AXIsProcessTrusted() else {
            NSLog("[HotkeyManager] Accessibility permission not granted — skipping CGEvent tap. Global shortcuts will not work.")
            return
        }

        // Create a CGEvent tap that intercepts keyDown events at the session level.
        // Using .defaultTap allows us to modify or consume events (return nil).
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

        // Add the tap to the main run loop so events are processed on the main thread.
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

        // Enable the tap.
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // MARK: - Event Tap Callback

    /// C-compatible callback for the CGEvent tap.
    /// Returns nil to consume the event (preventing other apps from receiving it),
    /// or returns the event unchanged to pass it through.
    private static let eventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
        // Handle tap being disabled by the system (e.g., if the callback is too slow).
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let shared = HotkeyManager.shared, let tap = shared.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        guard let shared = HotkeyManager.shared else {
            return Unmanaged.passRetained(event)
        }

        // Check if this event matches any registered shortcut.
        // Extract only the modifier flags we care about (control, shift, option, command)
        let relevantFlags: CGEventFlags = [.maskControl, .maskShift, .maskAlternate, .maskCommand]
        let eventModifiers = flags.intersection(relevantFlags)

        for (shortcut, handler) in shared.handlers {
            if keyCode == shortcut.keyCode && eventModifiers == shortcut.cgEventFlags {
                // Match found — dispatch handler on main thread and consume the event.
                DispatchQueue.main.async {
                    handler()
                }
                return nil
            }
        }

        // No match — pass event through to other apps unchanged.
        return Unmanaged.passRetained(event)
    }

    // MARK: - Local Monitor

    /// Keeps a local NSEvent monitor for when SpotDraw itself has focus
    /// (e.g., the overlay is active). This ensures shortcuts work regardless
    /// of whether the CGEvent tap processes them first.
    private func setupLocalMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleLocalKeyEvent(event)
            return event
        }
    }

    private func handleLocalKeyEvent(_ event: NSEvent) {
        let relevantModifiers: NSEvent.ModifierFlags = [.control, .shift, .option, .command]
        let eventMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).intersection(relevantModifiers)

        for (shortcut, handler) in handlers {
            if event.keyCode == shortcut.keyCode && eventMods == shortcut.modifiers {
                handler()
                return
            }
        }
    }

    // MARK: - Cleanup

    /// Disables the CGEvent tap, removes the run loop source, and removes the local monitor.
    func removeAllMonitors() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil

        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }

        HotkeyManager.shared = nil
    }

    deinit {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
        HotkeyManager.shared = nil
    }
}
