import Cocoa

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem!
    private var menuBarController: MenuBarController!
    private var overlayController: OverlayWindowController!
    private var cursorManager: CursorManager!
    private var hotkeyManager: HotkeyManager!
    private var settingsManager: SettingsManager!

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        settingsManager = SettingsManager.shared
        setupMenuBar()
        setupOverlay()
        setupCursorManager()
        setupHotkeys()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.removeAllMonitors()
    }

    // MARK: - Setup

    private func setupMenuBar() {
        menuBarController = MenuBarController(
            onToggleAnnotation: { [weak self] in self?.toggleAnnotation() },
            onToggleCursorHighlight: { [weak self] in self?.toggleCursorHighlight() },
            onToggleSpotlight: { [weak self] in self?.toggleSpotlight() },
            onClearAll: { [weak self] in self?.clearAll() },
            onQuit: { NSApp.terminate(nil) }
        )
    }

    private func setupOverlay() {
        overlayController = OverlayWindowController()
    }

    private func setupCursorManager() {
        cursorManager = CursorManager()
    }

    private func setupHotkeys() {
        hotkeyManager = HotkeyManager()
        hotkeyManager.register(shortcut: .toggleAnnotation) { [weak self] in
            self?.toggleAnnotation()
        }
        hotkeyManager.register(shortcut: .toggleCursorHighlight) { [weak self] in
            self?.toggleCursorHighlight()
        }
        hotkeyManager.register(shortcut: .toggleSpotlight) { [weak self] in
            self?.toggleSpotlight()
        }
    }

    // MARK: - Actions

    private func toggleAnnotation() {
        overlayController.toggle()
        menuBarController.updateState(annotating: overlayController.isActive)
    }

    private func toggleCursorHighlight() {
        cursorManager.toggleHighlight()
        menuBarController.updateState(cursorHighlight: cursorManager.isHighlightActive)
    }

    private func toggleSpotlight() {
        cursorManager.toggleSpotlight()
        menuBarController.updateState(spotlight: cursorManager.isSpotlightActive)
    }

    private func clearAll() {
        overlayController.clearAll()
    }
}
