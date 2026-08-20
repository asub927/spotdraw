import Cocoa

/// Regression coverage for the callback-based Tool submenu.
///
/// **Validates: Requirements 1.1, 4.5**
///
/// This exercises the real NSStatusItem menu built by MenuBarController rather than
/// duplicating the tools list in the test. The private status item is accessed through
/// the same minimal reflection seam used by existing tests for private window state.
@MainActor
func testToolMenuContainsTextAndDispatchesSelection() -> PreservationTestResult {
    return runPreservationTest(
        "Regression: Tool menu exposes Text and dispatches .text",
        iterations: 1
    ) { _ in
        var selectedTool: ToolType?
        let controller = MenuBarController(
            onToggleAnnotation: {},
            onToggleCursorHighlight: {},
            onToggleSpotlight: {},
            onClearAll: {},
            onQuit: {}
        )
        controller.onSelectTool = { selectedTool = $0 }

        let statusItem = Mirror(reflecting: controller).children
            .first { $0.label == "statusItem" }?.value as? NSStatusItem
        guard let menu = statusItem?.menu,
              let toolMenu = menu.items.first(where: { $0.title == "Tool" })?.submenu else {
            return (false, "Could not inspect the MenuBarController Tool submenu")
        }

        guard let textItem = toolMenu.items.first(where: { $0.title.hasPrefix("Text") }) else {
            return (false, "Tool submenu does not contain a Text item")
        }
        guard let action = textItem.action, let target = textItem.target else {
            return (false, "Text menu item has no invokable target/action")
        }

        NSApp.sendAction(action, to: target, from: textItem)
        guard selectedTool == .text else {
            return (false, "Selecting Text dispatched \(String(describing: selectedTool)) instead of .text")
        }
        return (true, "Text menu item dispatched .text through onSelectTool")
    }
}
