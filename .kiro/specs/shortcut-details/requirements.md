# Requirements Document

## Introduction

SpotDraw's menu bar status-item menu displays shortcut hints for the five global toggle items (Toggle Annotation, Toggle Cursor Highlight, Toggle Spotlight, Toggle Zoom, Toggle Interactive Mode) but omits them from every Tool submenu item, every Color submenu item, and the Clear All item. Users cannot discover the keyboard shortcuts for tools (P, A, R, O, L, H, E, T, S), colors (1, 2, 3, 4, 5), or clear-all (⌘⌫) without consulting documentation or the Settings → Shortcuts tab.

This spec adds shortcut key indicators to every menu item that has a corresponding `ShortcutAction` binding.

## Requirements

### Requirement 1: Tool Submenu Items Display Shortcuts

**User Story:** As a user, I want to see the keyboard shortcut next to each tool name in the Tool submenu, so that I can learn and remember shortcuts without opening Settings.

#### Acceptance Criteria

1. EACH item in the Tool submenu (Pen, Arrow, Rectangle, Circle, Line, Highlighter, Eraser, Text, Select) SHALL display the currently assigned shortcut binding in parentheses after the tool name.
2. THE displayed shortcut SHALL match the binding returned by `ShortcutStore.shared.binding(for:)` for the corresponding tool action (e.g. `toolPen`, `toolArrow`, etc.).
3. IF a tool action has been cleared (no binding assigned), THE menu item SHALL display only the tool name without parentheses.
4. WHEN a shortcut binding changes through the Shortcuts settings tab, THE Tool submenu items SHALL reflect the new binding the next time the menu is opened.

### Requirement 2: Color Submenu Items Display Shortcuts

**User Story:** As a user, I want to see the keyboard shortcut next to each color name in the Color submenu, so that I can quickly switch colors without trial and error.

#### Acceptance Criteria

1. EACH item in the Color submenu (Red, Blue, Green, Yellow, White) SHALL display the currently assigned shortcut binding in parentheses after the color name.
2. THE displayed shortcut SHALL match the binding returned by `ShortcutStore.shared.binding(for:)` for the corresponding color action (e.g. `colorRed`, `colorBlue`, etc.).
3. IF a color action has been cleared (no binding assigned), THE menu item SHALL display only the color name without parentheses.
4. WHEN a shortcut binding changes through the Shortcuts settings tab, THE Color submenu items SHALL reflect the new binding the next time the menu is opened.

### Requirement 3: Clear All Menu Item Displays Shortcut

**User Story:** As a user, I want to see the Clear All shortcut in the menu, so that I know how to quickly clear annotations without navigating the menu.

#### Acceptance Criteria

1. THE Clear All menu item SHALL display the currently assigned shortcut binding in parentheses after "Clear All".
2. THE displayed shortcut SHALL match the binding returned by `ShortcutStore.shared.binding(for: .clearAll)`.
3. IF the clearAll action has been cleared, THE menu item SHALL display only "Clear All" without parentheses.

### Requirement 4: Consistent Format

**User Story:** As a user, I want all shortcut indicators to look the same across the entire menu, so the interface feels cohesive.

#### Acceptance Criteria

1. ALL menu items that display a shortcut SHALL use the same format: `"<Name> (<binding>)"`, matching the existing format used by the global toggle items.
2. THE binding display string SHALL use the standard macOS modifier symbols (⌃ for Control, ⌥ for Option, ⇧ for Shift, ⌘ for Command) followed by the key name, as produced by `KeyBinding.displayString`.

### Requirement 5: Dynamic Rebuild on Binding Changes

**User Story:** As a user, I want the menu to stay up-to-date after I change shortcuts in Settings, without restarting the app.

#### Acceptance Criteria

1. WHEN `ShortcutStore.didChangeNotification` is posted, THE MenuBarController SHALL rebuild all menu item titles (tools, colors, clear-all) with the current bindings.
2. THE rebuild SHALL NOT disrupt menu item state (checkmarks for active features) or submenu structure.
