// AppDelegate.swift
// Application lifecycle management, hotkey registration, and feature coordination.
// Wires together the overlay controller, cursor manager, menu bar, and settings
// window. Checks Accessibility permission at launch and registers global hotkeys
// for toggling annotation, cursor highlight, and spotlight modes.

import Cocoa

// MARK: - AppDelegate

internal final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem!
    private var menuBarController: MenuBarController!
    private var overlayController: OverlayWindowController!
    private var cursorManager: CursorManager!
    private var hotkeyManager: HotkeyManager!
    private var settingsManager: SettingsManager!
    private var settingsWindowController: SettingsWindowController!

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check accessibility permission at launch and prompt if not granted
        if !AccessibilityManager.checkPermission() {
            AccessibilityManager.requestPermission()
            showAccessibilityAlert()
        }

        settingsManager = SettingsManager.shared
        settingsWindowController = SettingsWindowController()
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
        menuBarController.onOpenSettings = { [weak self] in
            self?.settingsWindowController.showWindow()
        }
    }

    private func setupOverlay() {
        overlayController = OverlayWindowController()
        overlayController.onDeactivate = { [weak self] in
            self?.toggleAnnotation()
        }
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
        // Guard: only check permission when activating, not when deactivating
        if !overlayController.isActive {
            guard AccessibilityManager.checkPermission() else {
                AccessibilityManager.requestPermission()
                showAccessibilityAlert()
                return
            }
        }

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

    // MARK: - Accessibility

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "SpotDraw needs Accessibility permission to detect global keyboard shortcuts (like Ctrl+D) for activating and deactivating the annotation overlay. Please grant permission in System Settings > Privacy & Security > Accessibility."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
