// HotkeyManager.swift
// Global and local keyboard event monitors for shortcut registration and dispatch.
// Defines the GlobalShortcut enum mapping features to key codes and modifier flags,
// and provides the HotkeyManager class that installs NSEvent monitors and routes
// matching key-down events to registered handler closures.

import Cocoa

// MARK: - GlobalShortcut

internal enum GlobalShortcut {
    case toggleAnnotation   // Ctrl+D
    case toggleCursorHighlight  // Ctrl+S
    case toggleSpotlight    // Ctrl+L
    case toggleZoom         // Ctrl+Z

    var keyCode: UInt16 {
        switch self {
        case .toggleAnnotation: 2       // D
        case .toggleCursorHighlight: 1  // S
        case .toggleSpotlight: 37       // L
        case .toggleZoom: 6             // Z
        }
    }

    var modifiers: NSEvent.ModifierFlags { .control }
}

// MARK: - HotkeyManager

@MainActor internal final class HotkeyManager {

    // MARK: - Properties

    private typealias ShortcutHandler = () -> Void
    private typealias EventMonitorToken = Any

    private var globalMonitor: EventMonitorToken?
    private var localMonitor: EventMonitorToken?
    private var handlers: [GlobalShortcut: ShortcutHandler] = [:]

    // MARK: - Init

    init() {
        setupMonitors()
    }

    // MARK: - Registration

    /// Registers a handler closure to be invoked when the given global shortcut is pressed.
    func register(shortcut: GlobalShortcut, handler: @escaping () -> Void) {
        handlers[shortcut] = handler
    }

    // MARK: - Monitor Setup

    private func setupMonitors() {
        // NSEvent monitor callbacks are dispatched on the main thread.
        // The @MainActor annotation on HotkeyManager ensures the compiler
        // verifies this isolation at Swift 6 language mode.
        if AXIsProcessTrusted() {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKeyEvent(event)
            }
        } else {
            NSLog("[HotkeyManager] Accessibility permission not granted — skipping global monitor registration. Global shortcuts will not work outside the app.")
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }
    }

    // MARK: - Event Handling

    private func handleKeyEvent(_ event: NSEvent) {
        for (shortcut, handler) in handlers {
            if event.keyCode == shortcut.keyCode &&
               event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(shortcut.modifiers) {
                handler()
                return
            }
        }
    }

    // MARK: - Cleanup

    /// Removes both global and local event monitors and clears their references.
    func removeAllMonitors() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    deinit {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
