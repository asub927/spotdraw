// AppDelegate.swift
// Application lifecycle management, hotkey registration, and feature coordination.
// Wires together the overlay controller, cursor manager, menu bar, and settings
// window. Checks Accessibility permission at launch and registers global hotkeys
// for toggling annotation, cursor highlight, and spotlight modes.

import Cocoa

// MARK: - AppDelegate

@MainActor internal final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem!
    private var menuBarController: MenuBarController!
    private var overlayController: OverlayWindowController!
    private var cursorManager: CursorManager!
    private var hotkeyManager: HotkeyManager!
    private var settingsManager: SettingsManager!
    private var settingsWindowController: SettingsWindowController!
    private var toolbarPanel = ToolbarPanelController()
    private let sizePresets: [CGFloat] = [30, 50, 100, 150]

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
        cursorManager.shutdown()
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
        menuBarController.onSelectTool = { [weak self] tool in
            self?.overlayController.setTool(tool)
        }
        menuBarController.onSelectColor = { [weak self] color in
            self?.overlayController.setColor(color)
        }
        menuBarController.onCursorSettingsChanged = { [weak self] in
            guard let self, self.cursorManager.isHighlightActive else { return }
            self.cursorManager.updateHighlightAppearance()
        }
        menuBarController.onToggleZoom = { [weak self] in
            self?.toggleZoom()
        }
        menuBarController.onToggleInteractiveMode = { [weak self] in
            self?.toggleInteractiveMode()
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

        // Load persisted shortcut bindings
        ShortcutStore.shared.loadFromDefaults()

        // Configure passthrough modifier from persisted settings
        hotkeyManager.passthroughModifier = SettingsManager.shared.passthroughModifier
        hotkeyManager.onPassthroughModifierChange = { [weak self] held in
            self?.overlayController.setPassthroughModifierHeld(held)
        }

        // Apply persisted Interactive Mode state to controller
        overlayController.interactiveModeEnabled = SettingsManager.shared.interactiveModeEnabled

        // Register handlers for all global ShortcutActions
        hotkeyManager.register(action: .toggleAnnotation) { [weak self] in
            self?.toggleAnnotation()
        }
        hotkeyManager.register(action: .toggleCursorHighlight) { [weak self] in
            self?.toggleCursorHighlight()
        }
        hotkeyManager.register(action: .toggleSpotlight) { [weak self] in
            self?.toggleSpotlight()
        }
        hotkeyManager.register(action: .toggleZoom) { [weak self] in
            self?.toggleZoom()
        }
        hotkeyManager.register(action: .cycleCursorSize) { [weak self] in
            self?.cycleCursorSize()
        }
        hotkeyManager.register(action: .zoomIn) { [weak self] in
            self?.cursorManager.zoomIn()
        }
        hotkeyManager.register(action: .zoomOut) { [weak self] in
            self?.cursorManager.zoomOut()
        }
        hotkeyManager.register(action: .toggleInteractiveMode) { [weak self] in
            self?.toggleInteractiveMode()
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

        // Install/teardown passthrough modifier monitor with overlay lifecycle (Requirement 8.11)
        if overlayController.isActive {
            hotkeyManager.passthroughModifier = SettingsManager.shared.passthroughModifier
            hotkeyManager.installPassthroughMonitor()
        } else {
            hotkeyManager.teardownPassthroughMonitor()
        }

        menuBarController.updateState(annotating: overlayController.isActive)
        updateToolbarPanel()
    }

    private func toggleCursorHighlight() {
        cursorManager.toggleHighlight()
        menuBarController.updateState(cursorHighlight: cursorManager.isHighlightActive)
        updateToolbarPanel()
    }

    private func toggleSpotlight() {
        cursorManager.toggleSpotlight()
        menuBarController.updateState(spotlight: cursorManager.isSpotlightActive)
        updateToolbarPanel()
    }

    private func toggleZoom() {
        cursorManager.toggleZoom()
        menuBarController.updateState(zoom: cursorManager.isZoomActive)
        updateToolbarPanel()
    }

    private func clearAll() {
        overlayController.clearAll()
    }

    private func cycleCursorSize() {
        let current = settingsManager.highlightSize
        let nextSize: CGFloat

        if let currentIndex = sizePresets.firstIndex(of: current) {
            // Exact preset match — advance to next
            nextSize = sizePresets[(currentIndex + 1) % sizePresets.count]
        } else {
            // Not an exact preset — snap to the smallest preset greater than current
            nextSize = sizePresets.first(where: { $0 > current }) ?? sizePresets[0]
        }

        settingsManager.highlightSize = nextSize
        if cursorManager.isHighlightActive {
            cursorManager.updateHighlightAppearance()
        }
    }

    private func toggleInteractiveMode() {
        let settings = SettingsManager.shared
        settings.interactiveModeEnabled.toggle()
        let enabled = settings.interactiveModeEnabled
        overlayController.interactiveModeEnabled = enabled
        menuBarController.updateState(interactiveMode: enabled)
    }

    // MARK: - Toolbar Panel

    private func updateToolbarPanel() {
        let features = FeatureState(
            annotationActive: overlayController.isActive,
            highlightActive: cursorManager.isHighlightActive,
            spotlightActive: cursorManager.isSpotlightActive,
            zoomActive: cursorManager.isZoomActive
        )
        toolbarPanel.update(
            features: features,
            drawingState: overlayController.isActive ? overlayController.drawingState : nil,
            cursorManager: cursorManager
        )
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
