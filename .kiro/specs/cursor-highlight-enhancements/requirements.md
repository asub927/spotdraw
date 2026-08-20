# Requirements Document

## Introduction

Enhance Spotdraw's cursor highlight feature to provide a professional, presentation-quality glow effect around the cursor, expand sizing options for larger displays, and expose quick-access controls in the menu bar. These changes bring the cursor highlight closer to the visual quality of dedicated presenter tools (like Presentify's glowing halo) while keeping settings discoverable and fast to adjust mid-presentation.

## Glossary

- **Cursor_Highlight**: The colored translucent circle rendered around the mouse cursor to draw viewer attention during presentations.
- **Glow_Effect**: A soft radial bloom rendered outside the main highlight circle using CALayer shadow or gaussian blur, creating a luminous halo appearance.
- **Highlight_Window**: The borderless NSWindow (`CursorHighlightWindow`) that hosts the highlight and glow layers, positioned to follow the cursor.
- **Menu_Bar_Controller**: The NSStatusItem-based controller (`MenuBarController`) providing the Spotdraw status menu.
- **Settings_Manager**: The singleton (`SettingsManager`) responsible for persisting user preferences to UserDefaults.
- **Cursor_Highlight_Submenu**: A new NSMenu within the status menu dedicated to cursor highlight quick-access controls.
- **Size_Cycle_Shortcut**: A global keyboard shortcut that cycles the cursor highlight radius through predefined size presets.

## Requirements

### Requirement 1: Glow Effect Rendering

**User Story:** As a presenter, I want the cursor highlight to display a soft glow/bloom radiating outward from the circle, so that the cursor is more visually prominent and attention-grabbing during presentations.

#### Acceptance Criteria

1. WHEN the Cursor_Highlight is active and the Glow_Effect is enabled, THE Highlight_Window SHALL render a radial glow layer outside the main highlight circle using a CALayer shadow with a configurable radius.
2. WHEN the Glow_Effect is enabled, THE Highlight_Window SHALL render the glow using the same base color as the Cursor_Highlight fill color.
3. WHEN the Glow_Effect radius setting is changed, THE Highlight_Window SHALL update the glow radius immediately without requiring a toggle off/on cycle.
4. THE Settings_Manager SHALL expose a `glowEnabled` boolean property defaulting to `true`.
5. THE Settings_Manager SHALL expose a `glowRadius` property with a value range of 5 to 50 points, defaulting to 15 points.
6. IF the Glow_Effect is disabled, THEN THE Highlight_Window SHALL render only the flat highlight circle without any shadow or blur layers.

### Requirement 2: Extended Highlight Size Range

**User Story:** As a presenter using a large or high-resolution display, I want to increase the cursor highlight size beyond the current 100pt maximum, so that the highlight remains clearly visible to my audience.

#### Acceptance Criteria

1. THE Settings_Manager SHALL accept highlight size values in the range of 20 to 200 points.
2. WHEN the highlight size is changed, THE Highlight_Window SHALL resize the highlight circle and glow layer proportionally without clipping.
3. WHEN the highlight size exceeds 100 points, THE Highlight_Window SHALL expand its frame to accommodate the full highlight circle plus the glow radius without visual truncation.
4. THE Settings_Manager SHALL persist the highlight size value across application restarts.

### Requirement 3: Menu Bar Cursor Highlight Submenu

**User Story:** As a presenter, I want to quickly adjust cursor highlight color, size, and glow settings from the menu bar, so that I can make changes without opening the full settings window during a live presentation.

#### Acceptance Criteria

1. WHEN the user opens the Spotdraw status menu, THE Menu_Bar_Controller SHALL display a "Cursor Highlight" submenu item containing quick-access controls.
2. WHEN the Cursor_Highlight_Submenu is opened, THE Menu_Bar_Controller SHALL display color preset items matching the cursor color presets defined in ColorPresets.cursor (Yellow, Red, Blue, Green, White).
3. WHEN a user selects a color preset from the Cursor_Highlight_Submenu, THE Settings_Manager SHALL update the `highlightColor` property and THE Highlight_Window SHALL reflect the new color immediately.
4. WHEN the Cursor_Highlight_Submenu is opened, THE Menu_Bar_Controller SHALL display size preset items with labels "Small (30pt)", "Medium (50pt)", "Large (100pt)", and "Extra Large (150pt)".
5. WHEN a user selects a size preset from the Cursor_Highlight_Submenu, THE Settings_Manager SHALL update the `highlightSize` property and THE Highlight_Window SHALL reflect the new size immediately.
6. WHEN the Cursor_Highlight_Submenu is opened, THE Menu_Bar_Controller SHALL display a "Glow" toggle item reflecting the current glow enabled state.
7. WHEN a user toggles the Glow item in the Cursor_Highlight_Submenu, THE Settings_Manager SHALL update the `glowEnabled` property and THE Highlight_Window SHALL show or hide the glow layer immediately.
8. THE Menu_Bar_Controller SHALL place a checkmark indicator next to the currently active color preset and size preset in the Cursor_Highlight_Submenu.

### Requirement 4: Size Cycle Keyboard Shortcut

**User Story:** As a presenter, I want a keyboard shortcut to cycle through cursor highlight size presets, so that I can adjust size hands-free during a presentation.

#### Acceptance Criteria

1. WHEN the user presses the Size_Cycle_Shortcut (⌃⇧S), THE Cursor_Highlight SHALL cycle to the next size preset in the ordered sequence: Small (30pt), Medium (50pt), Large (100pt), Extra Large (150pt).
2. WHEN the current size is the last preset in the sequence (Extra Large), THE Cursor_Highlight SHALL wrap to the first preset (Small) on the next shortcut activation.
3. WHEN the Size_Cycle_Shortcut is activated, THE Settings_Manager SHALL persist the new size value immediately.
4. WHEN the Size_Cycle_Shortcut is activated while Cursor_Highlight is inactive, THE system SHALL store the new size without visual effect until the next activation of Cursor_Highlight.

### Requirement 5: Settings Persistence for New Properties

**User Story:** As a user, I want all new cursor highlight settings (glow enabled, glow radius) to be saved automatically, so that my preferences are preserved across application restarts.

#### Acceptance Criteria

1. THE Settings_Manager SHALL persist the `glowEnabled` property using UserDefaults with the key "glowEnabled".
2. THE Settings_Manager SHALL persist the `glowRadius` property using UserDefaults with the key "glowRadius".
3. WHEN the application launches for the first time with no stored value for `glowEnabled`, THE Settings_Manager SHALL default to `true`.
4. WHEN the application launches for the first time with no stored value for `glowRadius`, THE Settings_Manager SHALL default to 15 points.
5. WHEN any glow setting is changed via the Cursor_Highlight_Submenu or the Settings window, THE Settings_Manager SHALL write the new value to UserDefaults immediately.

### Requirement 6: Settings Window Integration

**User Story:** As a user, I want the Settings window's Cursor tab to include glow controls, so that I can fine-tune all cursor highlight options in one place.

#### Acceptance Criteria

1. WHEN the user opens the Cursor tab in the Settings window, THE Settings window SHALL display a "Glow Effect" toggle reflecting the current `glowEnabled` state.
2. WHEN the user opens the Cursor tab in the Settings window, THE Settings window SHALL display a "Glow Radius" slider with a range of 5 to 50 points, reflecting the current `glowRadius` value.
3. WHEN the user changes the Glow Effect toggle in the Settings window, THE Settings_Manager SHALL update `glowEnabled` and THE Highlight_Window SHALL reflect the change immediately.
4. WHEN the user changes the Glow Radius slider in the Settings window, THE Settings_Manager SHALL update `glowRadius` and THE Highlight_Window SHALL reflect the change immediately.
5. WHEN the user opens the Cursor tab in the Settings window, THE Settings window SHALL display the highlight size slider with an updated range of 20 to 200 points.
