// MenuBarController.swift
// NSStatusItem menu bar interface for feature toggling and tool/color selection.
// Builds the status-bar menu with items for annotation, cursor highlight, spotlight,
// tool and color submenus, clear-all, settings, and quit. Updates the status-bar icon
// to reflect whether any feature is currently active.

import Cocoa

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

    private var annotationMenuItem: NSMenuItem!
    private var cursorMenuItem: NSMenuItem!
    private var spotlightMenuItem: NSMenuItem!

    private var cursorHighlightColorItems: [NSMenuItem] = []
    private var cursorHighlightSizeItems: [NSMenuItem] = []
    private var cursorHighlightShapeItems: [NSMenuItem] = []
    private var cursorGlowItem: NSMenuItem!

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
    }

    // MARK: - Setup

    private func setupStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "pencil.tip.crop.circle", accessibilityDescription: "Spotdraw")
        button.image?.size = NSSize(width: 18, height: 18)
    }

    private func setupMenu() {
        let menu = NSMenu()

        annotationMenuItem = NSMenuItem(title: "Toggle Annotation (⌃D)", action: #selector(toggleAnnotationAction), keyEquivalent: "")
        annotationMenuItem.target = self
        menu.addItem(annotationMenuItem)

        cursorMenuItem = NSMenuItem(title: "Toggle Cursor Highlight (⌃S)", action: #selector(toggleCursorAction), keyEquivalent: "")
        cursorMenuItem.target = self
        menu.addItem(cursorMenuItem)

        spotlightMenuItem = NSMenuItem(title: "Toggle Spotlight (⌃L)", action: #selector(toggleSpotlightAction), keyEquivalent: "")
        spotlightMenuItem.target = self
        menu.addItem(spotlightMenuItem)

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
        let tools: [(String, ToolType)] = [
            ("Pen", .pen),
            ("Arrow", .arrow),
            ("Rectangle", .rectangle),
            ("Circle", .circle),
            ("Line", .line),
            ("Highlighter", .highlighter),
            ("Eraser", .eraser)
        ]
        for (title, _) in tools {
            let item = NSMenuItem(title: title, action: #selector(selectToolAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = title
            toolSubmenu.addItem(item)
        }
        let toolMenuItem = NSMenuItem(title: "Tool", action: nil, keyEquivalent: "")
        toolMenuItem.submenu = toolSubmenu
        menu.addItem(toolMenuItem)

        // Color selection submenu
        let colorSubmenu = NSMenu()
        let colors: [(String, NSColor)] = [
            ("Red", .systemRed),
            ("Blue", .systemBlue),
            ("Green", .systemGreen),
            ("Yellow", .systemYellow),
            ("White", .white)
        ]
        for (title, _) in colors {
            let item = NSMenuItem(title: title, action: #selector(selectColorAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = title
            colorSubmenu.addItem(item)
        }
        let colorMenuItem = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        colorMenuItem.submenu = colorSubmenu
        menu.addItem(colorMenuItem)

        menu.addItem(NSMenuItem.separator())

        let clearItem = NSMenuItem(title: "Clear All", action: #selector(clearAllAction), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)

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

    func updateState(annotating: Bool? = nil, cursorHighlight: Bool? = nil, spotlight: Bool? = nil) {
        if let annotating {
            annotationMenuItem.state = annotating ? .on : .off
        }
        if let cursorHighlight {
            cursorMenuItem.state = cursorHighlight ? .on : .off
        }
        if let spotlight {
            spotlightMenuItem.state = spotlight ? .on : .off
        }

        // Update icon based on any active state
        let anyActive = (annotationMenuItem.state == .on) ||
                        (cursorMenuItem.state == .on) ||
                        (spotlightMenuItem.state == .on)

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
            "Eraser": .eraser
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
}

