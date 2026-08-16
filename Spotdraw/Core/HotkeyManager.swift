import Cocoa

// MARK: - GlobalShortcut

enum GlobalShortcut {
    case toggleAnnotation   // Ctrl+D
    case toggleCursorHighlight  // Ctrl+S
    case toggleSpotlight    // Ctrl+L

    var keyCode: UInt16 {
        switch self {
        case .toggleAnnotation: return 2       // D
        case .toggleCursorHighlight: return 1  // S
        case .toggleSpotlight: return 37       // L
        }
    }

    var modifiers: NSEvent.ModifierFlags {
        return .control
    }
}

// MARK: - HotkeyManager

class HotkeyManager {

    // MARK: - Properties

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var handlers: [GlobalShortcut: () -> Void] = [:]

    // MARK: - Init

    init() {
        setupMonitors()
    }

    // MARK: - Registration

    func register(shortcut: GlobalShortcut, handler: @escaping () -> Void) {
        handlers[shortcut] = handler
    }

    // MARK: - Monitor Setup

    private func setupMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
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
        removeAllMonitors()
    }
}
