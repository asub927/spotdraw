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
        setupMainMenu()
        setupMenuBar()
        setupOverlay()
        setupCursorManager()
        setupHotkeys()
        restoreState()
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveState()
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

    // MARK: - State Restoration (Requirement 5)

    private func saveState() {
        let settings = SettingsManager.shared

        // Save active tool
        settings.lastActiveTool = toolTypeName(overlayController.drawingState.activeTool)

        // Save active color
        settings.lastActiveColor = overlayController.drawingState.activeColor

        // Save feature states
        settings.wasAnnotationActive = overlayController.isActive
        settings.wasHighlightActive = cursorManager.isHighlightActive
        settings.wasSpotlightActive = cursorManager.isSpotlightActive
        settings.wasZoomActive = cursorManager.isZoomActive

        // Save toolbar panel position
        toolbarPanel.savePosition()
    }

    private func restoreState() {
        let settings = SettingsManager.shared

        // Restore active tool and color
        overlayController.drawingState.activeTool = toolTypeFromName(settings.lastActiveTool)
        overlayController.drawingState.activeColor = settings.lastActiveColor

        // Restore previously active features
        if settings.wasAnnotationActive {
            toggleAnnotation()
        }
        if settings.wasHighlightActive {
            toggleCursorHighlight()
        }
        if settings.wasSpotlightActive {
            toggleSpotlight()
        }
        if settings.wasZoomActive {
            toggleZoom()
        }
    }

    private func toolTypeName(_ tool: ToolType) -> String {
        switch tool {
        case .pen: return "pen"
        case .arrow: return "arrow"
        case .rectangle: return "rectangle"
        case .circle: return "circle"
        case .line: return "line"
        case .highlighter: return "highlighter"
        case .eraser: return "eraser"
        case .text: return "text"
        case .select: return "select"
        }
    }

    private func toolTypeFromName(_ name: String) -> ToolType {
        switch name {
        case "pen": return .pen
        case "arrow": return .arrow
        case "rectangle": return .rectangle
        case "circle": return .circle
        case "line": return .line
        case "highlighter": return .highlighter
        case "eraser": return .eraser
        case "text": return .text
        case "select": return .select
        default: return .pen
        }
    }

    // MARK: - Main Menu (Requirement 1)

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Spotdraw", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide Spotdraw", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthersItem = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Spotdraw", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        let undoItem = editMenu.addItem(withTitle: "Undo", action: #selector(undoAction), keyEquivalent: "z")
        undoItem.target = self
        let redoItem = editMenu.addItem(withTitle: "Redo", action: #selector(redoAction), keyEquivalent: "Z")
        redoItem.target = self
        editMenu.addItem(NSMenuItem.separator())
        let cutItem = editMenu.addItem(withTitle: "Cut", action: #selector(cutAction), keyEquivalent: "x")
        cutItem.target = self
        let copyItem = editMenu.addItem(withTitle: "Copy", action: #selector(copyAction), keyEquivalent: "c")
        copyItem.target = self
        let pasteItem = editMenu.addItem(withTitle: "Paste", action: #selector(pasteAction), keyEquivalent: "v")
        pasteItem.target = self
        let deleteItem = editMenu.addItem(withTitle: "Delete", action: #selector(deleteAction), keyEquivalent: "\u{08}")
        deleteItem.target = self
        deleteItem.keyEquivalentModifierMask = []
        editMenu.addItem(NSMenuItem.separator())
        let selectAllItem = editMenu.addItem(withTitle: "Select All", action: #selector(selectAllAction), keyEquivalent: "a")
        selectAllItem.target = self
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let toolbarItem = viewMenu.addItem(withTitle: "Toggle Toolbar Panel", action: #selector(toggleToolbarPanel), keyEquivalent: "")
        toolbarItem.target = self
        let boardItem = viewMenu.addItem(withTitle: "Toggle Board Mode", action: #selector(toggleBoardAction), keyEquivalent: "")
        boardItem.target = self
        let fadeItem = viewMenu.addItem(withTitle: "Toggle Fade Mode", action: #selector(toggleFadeAction), keyEquivalent: "")
        fadeItem.target = self
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        // Help menu
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        let helpItem = helpMenu.addItem(withTitle: "Spotdraw Help", action: #selector(openHelp), keyEquivalent: "?")
        helpItem.target = self
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Menu Actions (Requirement 1)

    @objc private func openSettings() {
        settingsWindowController.showWindow()
    }

    @objc private func undoAction() {
        guard overlayController.isActive else { return }
        overlayController.drawingState.undo()
        refreshOverlayViews()
    }

    @objc private func redoAction() {
        guard overlayController.isActive else { return }
        overlayController.drawingState.redo()
        refreshOverlayViews()
    }

    @objc private func cutAction() {
        guard overlayController.isActive else { return }
        copySelectionToPasteboard()
        overlayController.drawingState.removeSelected()
        refreshOverlayViews()
    }

    @objc private func copyAction() {
        guard overlayController.isActive else { return }
        copySelectionToPasteboard()
    }

    @objc private func pasteAction() {
        // Paste support: placeholder for full implementation
    }

    @objc private func deleteAction() {
        guard overlayController.isActive else { return }
        overlayController.drawingState.removeSelected()
        refreshOverlayViews()
    }

    @objc private func selectAllAction() {
        guard overlayController.isActive else { return }
        overlayController.drawingState.selectAll()
        refreshOverlayViews()
    }

    @objc private func toggleToolbarPanel() {
        toolbarPanel.toggleVisibility()
    }

    @objc private func toggleBoardAction() {
        guard overlayController.isActive else { return }
        overlayController.toggleBoard()
    }

    @objc private func toggleFadeAction() {
        guard overlayController.isActive else { return }
        overlayController.toggleFadeMode()
    }

    @objc private func openHelp() {
        if let url = URL(string: "https://github.com/AaranVinaique/Spotdraw") {
            NSWorkspace.shared.open(url)
        }
    }

    private func refreshOverlayViews() {
        // Force redraw of all overlay windows by clearing/re-rendering
        overlayController.refreshViews()
    }

    // MARK: - Copy/Paste Support (Requirement 2)

    /// Renders selected annotations as a PNG image and writes to the system pasteboard.
    private func copySelectionToPasteboard() {
        let state = overlayController.drawingState
        guard !state.selection.isEmpty else { return }

        let selectedItems = state.items.filter { state.selection.contains($0.id) }
        guard !selectedItems.isEmpty else { return }

        // Compute bounding box of selected items
        var unionRect = CGRect.null
        for item in selectedItems {
            let itemBounds = item.bounds
            unionRect = unionRect.union(itemBounds)
        }
        guard !unionRect.isNull, unionRect.width > 0, unionRect.height > 0 else { return }

        // Add padding
        let padding: CGFloat = 4
        let renderRect = unionRect.insetBy(dx: -padding, dy: -padding)

        // Create bitmap context
        let width = Int(ceil(renderRect.width))
        let height = Int(ceil(renderRect.height))
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return }

        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmapRep)
        NSGraphicsContext.current = context
        guard let cgContext = context?.cgContext else {
            NSGraphicsContext.restoreGraphicsState()
            return
        }

        // Translate so items render at correct position within the bitmap
        cgContext.translateBy(x: -renderRect.origin.x, y: -renderRect.origin.y)

        for item in selectedItems {
            item.render(in: cgContext)
        }

        NSGraphicsContext.restoreGraphicsState()

        // Write to pasteboard
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
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
