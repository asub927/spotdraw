# Requirements Document

## Introduction

SpotDraw's annotation controls are currently accessible only through the status-bar dropdown menu. While functional, this requires navigating nested submenus to switch tools or colors during a live annotation session — too slow for presenting. Competing tools like Presentify solve this with a floating toolbar panel that sits at the top of the screen, showing color swatches and tool icons in a single row for instant one-click access.

This spec adds a floating annotation toolbar panel that appears whenever the overlay is active, providing direct access to tools and colors without opening menus.

## Glossary

- **Toolbar_Panel**: A small floating window rendered as a dark, rounded-rectangle bar positioned at the top-center of the primary display. Contains color swatches, a separator, and tool icons in a single horizontal row.
- **Drag_Handle**: A grip area (dot grid) at the leading edge of the Toolbar_Panel that allows the user to reposition it by dragging.
- **Color_Swatch**: A filled circle in the Toolbar_Panel representing one of the five color presets.
- **Tool_Icon**: A symbolic icon in the Toolbar_Panel representing one annotation tool.
- **Active_Indicator**: A visual highlight (e.g. ring, underline, or background tint) applied to the currently selected color swatch or tool icon.

## Requirements

### Requirement 1: Panel Visibility and Lifecycle

**User Story:** As a presenter, I want the toolbar to appear automatically when I start annotating, so I don't have to open a menu first.

#### Acceptance Criteria

1. WHEN the Annotation_Overlay is activated, THE Toolbar_Panel SHALL appear on screen.
2. WHEN the Annotation_Overlay is deactivated, THE Toolbar_Panel SHALL be hidden.
3. THE Toolbar_Panel SHALL float above the annotation overlay windows and all other application windows.
4. THE Toolbar_Panel SHALL NOT capture keyboard focus — the overlay view must remain first responder so keyboard shortcuts continue to work.
5. THE Toolbar_Panel SHALL be visible on the primary display. If the user repositions it, the position SHALL be retained for the current session.
6. WHILE the Annotation_Overlay is in Passthrough_State, THE Toolbar_Panel SHALL remain visible so the user can see which tool and color are active.

### Requirement 2: Panel Layout and Appearance

**User Story:** As a user, I want the toolbar to look clean and unobtrusive, so it doesn't distract from my presentation content.

#### Acceptance Criteria

1. THE Toolbar_Panel SHALL render as a horizontal bar with a dark semi-transparent background and rounded corners.
2. THE Toolbar_Panel SHALL contain, from leading to trailing: a Drag_Handle, the five Color_Swatches (one per color preset), a vertical separator, the tool icons (Pen, Arrow, Rectangle, Circle, Text, Eraser), and a close/dismiss button at the trailing edge.
3. THE Toolbar_Panel SHALL have a fixed height appropriate for comfortable click targets (approximately 36–44 points tall).
4. THE Toolbar_Panel SHALL be horizontally centered at the top of the primary display by default, with a small vertical offset from the top edge so it does not overlap the macOS menu bar.

### Requirement 3: Color Swatches

**User Story:** As a presenter, I want to switch colors with a single click on a colored dot, so I can annotate in different colors without keyboard shortcuts.

#### Acceptance Criteria

1. THE Toolbar_Panel SHALL display five Color_Swatches corresponding to the five color presets: Red, Blue, Green, Yellow, White.
2. EACH Color_Swatch SHALL render as a filled circle in its corresponding color.
3. WHEN the user clicks a Color_Swatch, THE Drawing_State SHALL set the active color to that swatch's color.
4. THE Color_Swatch corresponding to the currently active color SHALL display an Active_Indicator (e.g. a white border ring or scale emphasis) distinguishing it from the others.
5. WHEN the active color changes by any means (keyboard shortcut, menu, or swatch click), THE Toolbar_Panel SHALL update the Active_Indicator to reflect the new active color.

### Requirement 4: Tool Icons

**User Story:** As a presenter, I want to switch tools with a single click on an icon, so I can quickly move between drawing, arrows, shapes, text, and erasing.

#### Acceptance Criteria

1. THE Toolbar_Panel SHALL display one Tool_Icon for each of the following tools: Pen, Arrow, Rectangle, Circle, Text, Eraser.
2. EACH Tool_Icon SHALL render as a recognizable symbolic icon (SF Symbol or custom glyph).
3. WHEN the user clicks a Tool_Icon, THE Drawing_State SHALL set the active tool to that icon's tool.
4. THE Tool_Icon corresponding to the currently active tool SHALL display an Active_Indicator (e.g. background highlight or underline) distinguishing it from the others.
5. WHEN the active tool changes by any means (keyboard shortcut, menu, or icon click), THE Toolbar_Panel SHALL update the Active_Indicator to reflect the new active tool.
6. THE Highlighter, Line, and Select tools MAY be omitted from the panel for compactness. They remain accessible via keyboard shortcut and menu.

### Requirement 5: Drag Handle and Repositioning

**User Story:** As a user, I want to move the toolbar if it covers something important on screen, so it doesn't block my presentation content.

#### Acceptance Criteria

1. THE Toolbar_Panel SHALL include a Drag_Handle at its leading edge rendered as a dot-grid grip pattern.
2. WHEN the user presses and drags the Drag_Handle, THE Toolbar_Panel SHALL follow the cursor, repositioning to the new location.
3. THE Toolbar_Panel position SHALL be constrained to remain fully within the bounds of the primary display.
4. THE repositioned location SHALL persist for the duration of the session (until the app quits or the overlay is deactivated). It does NOT need to persist across app launches.

### Requirement 6: Dismiss Button

**User Story:** As a user, I want to hide the toolbar if I prefer using only keyboard shortcuts, so it doesn't take up screen space.

#### Acceptance Criteria

1. THE Toolbar_Panel SHALL include a dismiss button (×) at its trailing edge.
2. WHEN the user clicks the dismiss button, THE Toolbar_Panel SHALL be hidden for the remainder of the current overlay session.
3. WHEN the Annotation_Overlay is deactivated and reactivated, THE Toolbar_Panel SHALL reappear regardless of whether it was previously dismissed.
4. THE dismiss button SHALL NOT deactivate the overlay — only the panel is hidden; annotation remains active.

### Requirement 7: Non-Interference with Existing Features

**User Story:** As an existing user, I want the toolbar to complement — not replace — my existing workflow of keyboard shortcuts and menu access.

#### Acceptance Criteria

1. ALL existing keyboard shortcuts SHALL continue to function while the Toolbar_Panel is visible.
2. THE status-bar menu SHALL remain fully functional and unchanged.
3. WHEN the user switches tools or colors via keyboard shortcut or menu, THE Toolbar_Panel SHALL update its Active_Indicators to reflect the change.
4. THE Toolbar_Panel SHALL NOT interfere with drawing — clicking on the panel area must NOT leave stray marks on the overlay beneath it.
5. WHILE the Toolbar_Panel is visible, mouse events on the panel SHALL be handled by the panel and SHALL NOT pass through to the overlay view beneath.
