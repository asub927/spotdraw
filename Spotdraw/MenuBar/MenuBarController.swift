import Cocoa

// MARK: - MenuBarController

class MenuBarController {

    // MARK: - Properties

    private var statusItem: NSStatusItem
    private let onToggleAnnotation: () -> Void
    private let onToggleCursorHighlight: () -> Void
    private let onToggleSpotlight: () -> Void
    private let onClearAll: () -> Void
    private let onQuit: () -> Void

    private var annotationMenuItem: NSMenuItem!
    private var cursorMenuItem: NSMenuItem!
    private var spotlightMenuItem: NSMenuItem!

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

        menu.addItem(NSMenuItem.separator())

        let clearItem = NSMenuItem(title: "Clear All", action: #selector(clearAllAction), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)

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

    @objc private func quitAction() {
        onQuit()
    }
}
