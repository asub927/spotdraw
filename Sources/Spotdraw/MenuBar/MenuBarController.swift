// MenuBarController.swift
// NSStatusItem menu bar interface for feature toggling and tool/color selection.
// Builds the status-bar menu with items for annotation, cursor highlight, spotlight,
// tool and color submenus, clear-all, settings, and quit. Updates the status-bar icon
// to reflect whether any feature is currently active. Menu item titles are driven
// from ShortcutStore bindings and rebuilt on ShortcutStore.didChangeNotification.

import Cocoa
import SpotdrawCore

// MARK: - MenuBarController

@MainActor internal final class MenuBarController {

    // MARK: - Properties

    private var statusItem: NSStatusItem
    private let onToggleAnnotation: () -> Void
    private let onToggleCursorHighlight: () -> Void
    private let onToggleSpotlight: () -> Void
    private let onClearAll: () -> Void
    private let onQuit: () -> Void
    var onOpenSettings: (() -> Void)?
    var onSelectTool: ((ToolType) -> Void)?
    var onSelectColor: ((NSColor) -> Void)?
    var onCursorSettingsChanged: (() -> Void)?
    var onToggleZoom: (() -> Void)?
    var onToggleInteractiveMode: (() -> Void)?

    private var annotationMenuItem: NSMenuItem!
    private var cursorMenuItem: NSMenuItem!
    private var spotlightMenuItem: NSMenuItem!
    private var zoomMenuItem: NSMenuItem!
    private var interactiveModeMenuItem: NSMenuItem!

    private var shortcutObserver: Any?

    private var cursorHighlightColorItems: [NSMenuItem] = []
    private var cursorHighlightSizeItems: [NSMenuItem] = []
    private var cursorHighlightShapeItems: [NSMenuItem] = []
    private var cursorGlowItem: NSMenuItem!

    private var toolMenuItems: [(NSMenuItem, ShortcutAction)] = []
    private var colorMenuItems: [(NSMenuItem, ShortcutAction)] = []
    private var clearAllMenuItem: NSMenuItem!

    // MARK: - Init

    init(
        onToggleAnnotation: @escaping () -> Void,
        onToggleCursorHighlight: @escaping () -> Void,
        onToggleSpotlight: @escaping () -> Void,
        onClearAll: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onToggleAnnotation = onToggleAnnotation
        self.onToggleCursorHighlight = onToggleCursorHighlight
        self.onToggleSpotlight = onToggleSpotlight
        self.onClearAll = onClearAll
        self.onQuit = onQuit

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setupStatusItem()
        setupMenu()

        // Rebuild menu titles when shortcut bindings change (Requirement 6.11)
        shortcutObserver = NotificationCenter.default.addObserver(
            forName: ShortcutStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshShortcutTitles()
        }
    }

    // MARK: - Setup

    private func setupStatusItem() {
        guard let button = statusItem.button else { return }
        let icon = NSImage(systemSymbolName: "pencil.tip.crop.circle", accessibilityDescription: "Spotdraw")
        icon?.size = NSSize(width: 18, height: 18)
        icon?.isTemplate = true
        button.image = icon
    }

    private func setupMenu() {
        let menu = NSMenu()

        annotationMenuItem = NSMenuItem(title: menuTitle(for: .toggleAnnotation), action: #selector(toggleAnnotationAction), keyEquivalent: "")
        annotationMenuItem.target = self
        menu.addItem(annotationMenuItem)

        cursorMenuItem = NSMenuItem(title: menuTitle(for: .toggleCursorHighlight), action: #selector(toggleCursorAction), keyEquivalent: "")
        cursorMenuItem.target = self
        menu.addItem(cursorMenuItem)

        spotlightMenuItem = NSMenuItem(title: menuTitle(for: .toggleSpotlight), action: #selector(toggleSpotlightAction), keyEquivalent: "")
        spotlightMenuItem.target = self
        menu.addItem(spotlightMenuItem)

        zoomMenuItem = NSMenuItem(title: menuTitle(for: .toggleZoom), action: #selector(toggleZoomAction), keyEquivalent: "")
        zoomMenuItem.target = self
        menu.addItem(zoomMenuItem)

        interactiveModeMenuItem = NSMenuItem(title: menuTitle(for: .toggleInteractiveMode), action: #selector(toggleInteractiveModeAction), keyEquivalent: "")
        interactiveModeMenuItem.target = self
        menu.addItem(interactiveModeMenuItem)

        // Cursor Highlight settings submenu
        let cursorSubmenu = NSMenu()

        // Color section header
        let colorHeader = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        colorHeader.isEnabled = false
        cursorSubmenu.addItem(colorHeader)

        let cursorColors = ColorPresets.cursor
        for (index, preset) in cursorColors.enumerated() {
            let item = NSMenuItem(title: preset.name, action: #selector(cursorHighlightColorAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = index == 0 ? .on : .off
            cursorSubmenu.addItem(item)
            cursorHighlightColorItems.append(item)
        }

        cursorSubmenu.addItem(NSMenuItem.separator())

        // Size section header
        let sizeHeader = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        sizeHeader.isEnabled = false
        cursorSubmenu.addItem(sizeHeader)

        let sizePresets: [(String, CGFloat)] = [
            ("Small (30pt)", 30),
            ("Medium (50pt)", 50),
            ("Large (100pt)", 100),
            ("Extra Large (150pt)", 150)
        ]
        let currentSize = SettingsManager.shared.highlightSize
        for (index, (label, size)) in sizePresets.enumerated() {
            let item = NSMenuItem(title: label, action: #selector(cursorHighlightSizeAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.representedObject = size as NSNumber
            item.state = (currentSize == size) ? .on : .off
            cursorSubmenu.addItem(item)
            cursorHighlightSizeItems.append(item)
        }

        cursorSubmenu.addItem(NSMenuItem.separator())

        // Glow toggle
        let glowItem = NSMenuItem(title: "Glow", action: #selector(cursorGlowToggleAction), keyEquivalent: "")
        glowItem.target = self
        glowItem.state = SettingsManager.shared.glowEnabled ? .on : .off
        cursorSubmenu.addItem(glowItem)
        cursorGlowItem = glowItem

        cursorSubmenu.addItem(NSMenuItem.separator())

        // Shape section header
        let shapeHeader = NSMenuItem(title: "Shape", action: nil, keyEquivalent: "")
        shapeHeader.isEnabled = false
        cursorSubmenu.addItem(shapeHeader)

        let currentShape = SettingsManager.shared.highlightShape
        for shape in HighlightShape.allCases {
            let item = NSMenuItem(title: shape.displayName, action: #selector(cursorHighlightShapeAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = shape.rawValue
            item.state = (shape == currentShape) ? .on : .off
            cursorSubmenu.addItem(item)
            cursorHighlightShapeItems.append(item)
        }

        let cursorSettingsItem = NSMenuItem(title: "Cursor Highlight", action: nil, keyEquivalent: "")
        cursorSettingsItem.submenu = cursorSubmenu
        menu.addItem(cursorSettingsItem)

        menu.addItem(NSMenuItem.separator())

        // Tool selection submenu
        let toolSubmenu = NSMenu()
        let tools: [(String, ToolType, ShortcutAction)] = [
            ("Pen", .pen, .toolPen),
            ("Arrow", .arrow, .toolArrow),
            ("Rectangle", .rectangle, .toolRectangle),
            ("Circle", .circle, .toolCircle),
            ("Line", .line, .toolLine),
            ("Highlighter", .highlighter, .toolHighlighter),
            ("Eraser", .eraser, .toolEraser),
            ("Text", .text, .toolText),
            ("Select", .select, .toolSelect)
        ]
        for (title, _, action) in tools {
            let item = NSMenuItem(title: menuTitle(for: action), action: #selector(selectToolAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = title
            toolSubmenu.addItem(item)
            toolMenuItems.append((item, action))
        }
        let toolMenuItem = NSMenuItem(title: "Tool", action: nil, keyEquivalent: "")
        toolMenuItem.submenu = toolSubmenu
        menu.addItem(toolMenuItem)

        // Color selection submenu
        let colorSubmenu = NSMenu()
        let colors: [(String, NSColor, ShortcutAction)] = [
            ("Red", .systemRed, .colorRed),
            ("Blue", .systemBlue, .colorBlue),
            ("Green", .systemGreen, .colorGreen),
            ("Yellow", .systemYellow, .colorYellow),
            ("White", .white, .colorWhite)
        ]
        for (title, _, action) in colors {
            let item = NSMenuItem(title: menuTitle(for: action), action: #selector(selectColorAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = title
            colorSubmenu.addItem(item)
            colorMenuItems.append((item, action))
        }
        let colorMenuItem = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        colorMenuItem.submenu = colorSubmenu
        menu.addItem(colorMenuItem)

        menu.addItem(NSMenuItem.separator())

        clearAllMenuItem = NSMenuItem(title: menuTitle(for: .clearAll), action: #selector(clearAllAction), keyEquivalent: "")
        clearAllMenuItem.target = self
        menu.addItem(clearAllMenuItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Spotdraw", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - State Updates

    func updateState(annotating: Bool? = nil, cursorHighlight: Bool? = nil, spotlight: Bool? = nil, zoom: Bool? = nil, interactiveMode: Bool? = nil) {
        if let annotating {
            annotationMenuItem.state = annotating ? .on : .off
        }
        if let cursorHighlight {
            cursorMenuItem.state = cursorHighlight ? .on : .off
        }
        if let spotlight {
            spotlightMenuItem.state = spotlight ? .on : .off
        }
        if let zoom {
            zoomMenuItem?.state = zoom ? .on : .off
        }
        if let interactiveMode {
            interactiveModeMenuItem?.state = interactiveMode ? .on : .off
        }

        // Update icon based on any active state
        let anyActive = (annotationMenuItem.state == .on) ||
                        (cursorMenuItem.state == .on) ||
                        (spotlightMenuItem.state == .on) ||
                        (zoomMenuItem?.state == .on)

        if let button = statusItem.button {
            let symbolName = anyActive ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle"
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Spotdraw")
            button.image?.size = NSSize(width: 18, height: 18)
        }
    }

    // MARK: - Actions

    @objc private func toggleAnnotationAction() {
        onToggleAnnotation()
    }

    @objc private func toggleCursorAction() {
        onToggleCursorHighlight()
    }

    @objc private func toggleSpotlightAction() {
        onToggleSpotlight()
    }

    @objc private func toggleZoomAction() {
        onToggleZoom?()
    }

    @objc private func toggleInteractiveModeAction() {
        onToggleInteractiveMode?()
    }

    @objc private func clearAllAction() {
        onClearAll()
    }

    @objc private func openSettingsAction() {
        onOpenSettings?()
    }

    @objc private func selectToolAction(_ sender: NSMenuItem) {
        guard let toolName = sender.representedObject as? String else { return }
        let toolMap: [String: ToolType] = [
            "Pen": .pen,
            "Arrow": .arrow,
            "Rectangle": .rectangle,
            "Circle": .circle,
            "Line": .line,
            "Highlighter": .highlighter,
            "Eraser": .eraser,
            "Text": .text
        ]
        if let tool = toolMap[toolName] {
            onSelectTool?(tool)
        }
    }

    @objc private func selectColorAction(_ sender: NSMenuItem) {
        guard let colorName = sender.representedObject as? String else { return }
        let colorMap: [String: NSColor] = [
            "Red": .systemRed,
            "Blue": .systemBlue,
            "Green": .systemGreen,
            "Yellow": .systemYellow,
            "White": .white
        ]
        if let color = colorMap[colorName] {
            SettingsManager.shared.strokeColor = color
            onSelectColor?(color)
        }
    }

    @objc private func quitAction() {
        onQuit()
    }

    // MARK: - Cursor Highlight Submenu Actions

    @objc private func cursorHighlightColorAction(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index < ColorPresets.cursor.count else { return }
        SettingsManager.shared.highlightColor = ColorPresets.cursor[index].color
        cursorHighlightColorItems.forEach { $0.state = .off }
        sender.state = .on
        onCursorSettingsChanged?()
    }

    @objc private func cursorHighlightSizeAction(_ sender: NSMenuItem) {
        guard let size = sender.representedObject as? NSNumber else { return }
        SettingsManager.shared.highlightSize = CGFloat(size.floatValue)
        cursorHighlightSizeItems.forEach { $0.state = .off }
        sender.state = .on
        onCursorSettingsChanged?()
    }

    @objc private func cursorGlowToggleAction() {
        SettingsManager.shared.glowEnabled.toggle()
        cursorGlowItem.state = SettingsManager.shared.glowEnabled ? .on : .off
        onCursorSettingsChanged?()
    }

    @objc private func cursorHighlightShapeAction(_ sender: NSMenuItem) {
        guard let shape = HighlightShape(rawValue: sender.tag) else { return }
        SettingsManager.shared.highlightShape = shape
        cursorHighlightShapeItems.forEach { $0.state = .off }
        sender.state = .on
        onCursorSettingsChanged?()
    }

    // MARK: - Shortcut Title Helpers

    /// Builds a menu item title from the action display name and its current binding.
    private func menuTitle(for action: ShortcutAction) -> String {
        if let binding = ShortcutStore.shared.binding(for: action) {
            return "\(action.displayName) (\(binding.displayString))"
        }
        return action.displayName
    }

    /// Refreshes all menu item titles that display shortcut bindings.
    private func refreshShortcutTitles() {
        annotationMenuItem?.title = menuTitle(for: .toggleAnnotation)
        cursorMenuItem?.title = menuTitle(for: .toggleCursorHighlight)
        spotlightMenuItem?.title = menuTitle(for: .toggleSpotlight)
        zoomMenuItem?.title = menuTitle(for: .toggleZoom)
        interactiveModeMenuItem?.title = menuTitle(for: .toggleInteractiveMode)

        for (item, action) in toolMenuItems {
            item.title = menuTitle(for: action)
        }
        for (item, action) in colorMenuItems {
            item.title = menuTitle(for: action)
        }
        clearAllMenuItem?.title = menuTitle(for: .clearAll)
    }

    // MARK: - Cleanup

    deinit {
        if let observer = shortcutObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

