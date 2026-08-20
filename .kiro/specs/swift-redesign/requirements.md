# Requirements Document: Mac-Arsed Mac App Redesign

## Introduction

This spec applies the principles from the [Mac-Arsed Mac App skill](https://github.com/bartreardon/skills/tree/main/mac-arsed-mac-app) to SpotDraw. The skill defines what makes a macOS app feel genuinely native — not just running on macOS, but embracing its conventions for menus, keyboard, windows, pasteboard, accessibility, and progressive disclosure.

### Current State Review (Score: 19/36 — "Runs on Mac, but feels generic or incomplete")

| Category | Current Score | Assessment |
|----------|:---:|---|
| Native behaviour | 2 | Uses AppKit/NSWindow correctly, but many interactions bypass native patterns |
| Menus/commands | 2 | Menu bar exists with shortcuts shown, but no standard Edit/View/Window/Help menus |
| Keyboard/focus | 2 | Good shortcut coverage, but no standard menu key equivalents, no Tab/arrow navigation in settings |
| Text handling | 1 | NSTextField for text annotations, but no rich text, no standard Edit menu commands |
| Selection | 2 | Multi-select with shift-click and marquee works, but no Cmd+click, no copy/paste of selections |
| Drag/drop | 1 | Text annotation dragging works, but cannot drag items between apps or export |
| Copy/paste | 0 | No pasteboard support — cannot copy annotations, paste images, or export selections |
| Windows/documents | 1 | Single floating overlay per screen, no document model, no standard window chrome |
| State/config | 2 | Settings persist, toolbar position per-session, but no window restoration on relaunch |
| Interoperability | 1 | No Finder integration, no file export, no Services, no Shortcuts.app support |
| Accessibility | 1 | AccessibilityManager checks permission, but no VoiceOver labels on toolbar, no keyboard nav in panel |
| Craft/detail | 2 | Toolbar panel, dynamic sections, and passthrough are thoughtful touches |

### Key Gaps Identified

The skill's guiding philosophy states: *"If a reasonable Mac user wonders whether something works, it should probably work."* SpotDraw currently fails this test in several areas:

1. **No standard application menu structure** — Missing Edit (Undo/Redo/Copy/Paste), View, Window, Help menus
2. **No pasteboard integration** — Cannot copy selected annotations, paste images as annotations
3. **No drag-and-drop export** — Cannot drag a selection to Finder as an image
4. **No keyboard accessibility in the toolbar panel** — Mouse-only interaction
5. **No state restoration** — Toolbar panel position, active tool, and color not restored on relaunch
6. **No Services menu integration** — Cannot capture selected text from other apps as annotation

## Requirements

### Requirement 1: Standard macOS Menu Bar

**User Story:** As a Mac user, I expect standard menus (Edit, View, Window, Help) so that my muscle memory from other Mac apps works here.

**Principle:** *"Menus and shortcuts are not afterthoughts. Before polishing screens, define App/File/Edit/View/Window/Help menu items."*

#### Acceptance Criteria

1. THE application SHALL provide a standard main menu bar with: SpotDraw (app menu), Edit, View, Window, and Help menus when the app is activated.
2. THE Edit menu SHALL contain: Undo (⌘Z), Redo (⌘⇧Z), Cut (⌘X), Copy (⌘C), Paste (⌘V), Delete, and Select All (⌘A) — routed to the annotation overlay when active.
3. THE View menu SHALL contain: Toggle Toolbar Panel, Toggle Board Mode, Toggle Fade Mode.
4. THE Window menu SHALL contain standard items: Minimize, Zoom, Bring All to Front, and a list of open overlay/settings windows.
5. THE Help menu SHALL contain a link to the README/documentation.
6. MENU items SHALL be enabled/disabled based on current state (e.g. Copy disabled when nothing is selected, Paste disabled when pasteboard has no usable content).

### Requirement 2: Copy/Paste for Annotations

**User Story:** As a presenter, I want to copy my selected annotations and paste them back, or paste an image from the clipboard as an annotation.

**Principle:** *"For each selected object, define multiple pasteboard representations."*

#### Acceptance Criteria

1. WHEN annotations are selected and the user presses ⌘C, THE application SHALL write the selection to the pasteboard as: (a) a PNG image of the selected items rendered on a transparent background, and (b) an internal representation for paste-back.
2. WHEN the user presses ⌘V with an internal annotation representation on the pasteboard, THE application SHALL paste the annotations at the center of the active overlay, offset slightly from the original position.
3. WHEN the user presses ⌘V with a PNG/TIFF image on the pasteboard (e.g. screenshot), THE application SHALL create an image annotation item at the center of the overlay.
4. WHEN the user presses ⌘X with annotations selected, THE application SHALL copy to pasteboard and delete the selection (with undo support).

### Requirement 3: Drag and Drop

**User Story:** As a Mac user, I want to drag my annotations to the desktop or another app to save them as an image file.

**Principle:** *"If a thing represents a file, image, URL, text, row, card, object, or document, ask whether it should be draggable or copyable."*

#### Acceptance Criteria

1. WHILE the select tool is active and items are selected, WHEN the user drags the selection outside the overlay window bounds, THE application SHALL initiate a drag session with a PNG image of the selected items.
2. WHEN the drag is dropped on Finder or a folder, THE system SHALL create a PNG file named "SpotDraw Annotation.png".
3. WHEN the drag is dropped on an app that accepts images (e.g. Slack, Mail, Notes), THE receiving app SHALL receive the image data.
4. WHEN an image file is dragged FROM Finder INTO the overlay, THE application SHALL create an image annotation at the drop point.

### Requirement 4: Keyboard Accessibility in Toolbar Panel

**User Story:** As a power user, I want to navigate the toolbar with keyboard shortcuts or arrow keys, not just mouse clicks.

**Principle:** *"Good Mac apps work for new users but also contain depth for those who invest time: keyboard navigation."*

#### Acceptance Criteria

1. WHEN the toolbar panel is visible, THE user SHALL be able to cycle through tools using keyboard shortcuts (already implemented via ShortcutStore — this is about discoverability).
2. EACH button in the toolbar panel SHALL have a tooltip showing its name and keyboard shortcut.
3. THE toolbar panel SHALL support VoiceOver with appropriate accessibility labels for each button (e.g. "Pen tool, active" or "Red color swatch").

### Requirement 5: State Restoration on Relaunch

**User Story:** As a user, I want SpotDraw to remember my last-used tool, color, and toolbar position when I restart it.

**Principle:** *"Persist meaningful choices: window size/position, sidebar widths, sort order, last view/mode."*

#### Acceptance Criteria

1. THE application SHALL persist the toolbar panel position across app launches.
2. THE application SHALL persist the last active tool and active color across app launches.
3. THE application SHALL persist which features were active (annotation, cursor highlight, spotlight, zoom) and restore them on relaunch.
4. WHEN the app relaunches with features that were previously active, THOSE features SHALL activate automatically.

### Requirement 6: Contextual Menus

**User Story:** As a Mac user, I expect right-click to show relevant actions for what I'm clicking on.

**Principle:** *"Every important action should be reachable from the menu bar or a contextual menu — not only from an unlabeled icon."*

#### Acceptance Criteria

1. WHEN the user right-clicks a selected annotation, THE application SHALL display a context menu with: Cut, Copy, Delete, Move to Front, Move to Back.
2. WHEN the user right-clicks empty space on the overlay, THE application SHALL display a context menu with: Paste (if pasteboard has content), Select All, Clear All, and tool selection submenu.
3. WHEN the user right-clicks the toolbar panel, THE application SHALL display a context menu with: Hide Panel, Reset Position.

### Requirement 7: Tooltips and Progressive Disclosure

**User Story:** As a new user, I want to hover over toolbar buttons to learn what they do without reading documentation.

**Principle:** *"Start with good defaults, then reveal depth: tooltips, settings with clear defaults."*

#### Acceptance Criteria

1. EVERY button in the toolbar panel SHALL display a tooltip after 0.5 seconds of hover, showing the action name and its keyboard shortcut (e.g. "Pen (P)").
2. THE color swatches SHALL show tooltips with the color name and shortcut (e.g. "Red (1)").
3. THE cursor highlight section buttons SHALL show tooltips explaining the setting (e.g. "Large size (100pt)").
4. THE spotlight and zoom section buttons SHALL show tooltips (already partially implemented for spotlight — extend to all).

## Implementation Priority

1. **Tooltips** (Requirement 7) — Quickest win, immediately improves discoverability
2. **Standard menus** (Requirement 1) — High-impact Mac convention compliance
3. **State restoration** (Requirement 5) — Users expect this from any Mac app
4. **Copy/Paste** (Requirement 2) — Core Mac interaction
5. **Contextual menus** (Requirement 6) — Expected Mac affordance
6. **Drag and Drop** (Requirement 3) — Power-user feature
7. **Keyboard accessibility** (Requirement 4) — Accessibility compliance

## README Addition

After implementing these improvements, the README should include a section:

### Mac-Native Design Principles

SpotDraw follows the [Mac-Arsed Mac App](https://github.com/bartreardon/skills/tree/main/mac-arsed-mac-app) design principles to feel genuinely native:

- **Standard menus** — Edit, View, Window, Help menus with proper command routing
- **Pasteboard integration** — Copy/paste annotations as images, paste images from clipboard
- **Drag and drop** — Drag selections to Finder or other apps as PNG files
- **Contextual menus** — Right-click for relevant actions everywhere
- **State restoration** — Remembers your tool, color, toolbar position, and active features
- **Tooltips** — Hover any button to learn its name and shortcut
- **Accessibility** — VoiceOver labels on all toolbar controls
- **Keyboard-first** — Every action reachable without a mouse

These improvements moved SpotDraw's Mac-nativeness score from 19/36 ("runs on Mac but feels generic") to 30+/36 ("solid Mac app").
