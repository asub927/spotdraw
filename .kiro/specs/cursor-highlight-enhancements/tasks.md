# Implementation Plan: Cursor Highlight Enhancements

## Overview

Extend Spotdraw's cursor highlight feature with a configurable glow/bloom effect, expanded size range (20–200pt), a menu bar submenu for quick mid-presentation adjustments, a keyboard shortcut for cycling sizes, and settings window integration for the new glow controls. Implementation uses Swift and builds on the existing `CursorHighlightWindow`, `SettingsManager`, `MenuBarController`, and `HotkeyManager` components.

## Tasks

- [ ] 1. Settings persistence — Add glow properties and expand highlight size range
  - [ ] 1.1 Add `glowEnabled` and `glowRadius` properties to SettingsManager
    - Add `Keys.glowEnabled` and `Keys.glowRadius` string constants
    - Add computed properties `glowEnabled: Bool` (default `true`) and `glowRadius: CGFloat` (range 5–50, default 15.0)
    - Add clamping logic in the `glowRadius` getter to enforce [5, 50] range
    - Register defaults for `glowEnabled` (`true`) and `glowRadius` (`15.0`) in `registerDefaults()`
    - Update `highlightSize` getter to clamp to [20, 200] instead of [20, 100]
    - File: `Spotdraw/Core/SettingsManager.swift`
    - _Requirements: 1.4, 1.5, 2.1, 5.1, 5.2, 5.3, 5.4_

  - [ ]* 1.2 Write property test for settings persistence round-trip and clamping
    - **Property 5: Settings persistence round-trip and clamping**
    - Generate random booleans for `glowEnabled`, verify round-trip
    - Generate random CGFloat values (both in-range and out-of-range) for `glowRadius`, verify clamping to [5, 50]
    - Generate random CGFloat values for `highlightSize`, verify clamping to [20, 200]
    - File: `SpotdrawTests/SettingsManagerPropertyTests.swift`
    - **Validates: Requirements 1.5, 2.1, 2.4, 5.1, 5.2, 5.5**

- [ ] 2. Cursor highlight window glow rendering and dynamic sizing
  - [ ] 2.1 Implement `updateAppearance()` method on CursorHighlightWindow
    - Add public `updateAppearance()` method that re-reads all settings from SettingsManager
    - Compute `totalSize = (highlightSize + (glowEnabled ? glowRadius : 0)) * 2`
    - Resize the window frame centered on the current position
    - Update `highlightLayer.path` to an ellipse of diameter `highlightSize * 2` centered in the window
    - Update fill/stroke colors from settings
    - When `glowEnabled` is true: set `shadowColor`, `shadowRadius`, `shadowOpacity = 0.8`, `shadowOffset = .zero`
    - When `glowEnabled` is false: set `shadowOpacity = 0`
    - File: `Spotdraw/Cursor/CursorHighlightWindow.swift`
    - _Requirements: 1.1, 1.2, 1.3, 1.6, 2.2, 2.3_

  - [ ] 2.2 Update `setupWindow()` to use dynamic sizing and initialize glow
    - Modify initial window frame calculation to use `(highlightSize + glowRadius) * 2` when glow is enabled
    - Configure shadow properties at layer creation time
    - Ensure the highlight circle is centered within the larger window frame
    - File: `Spotdraw/Cursor/CursorHighlightWindow.swift`
    - _Requirements: 1.1, 2.2, 2.3_

  - [ ]* 2.3 Write property test for window frame sizing
    - **Property 1: Window frame accommodates highlight plus glow**
    - Generate random `highlightSize` in [20, 200] and `glowRadius` in [5, 50]
    - Verify frame equals `(highlightSize + glowRadius) * 2` when glow enabled
    - Verify frame equals `highlightSize * 2` when glow disabled
    - File: `SpotdrawTests/CursorHighlightPropertyTests.swift`
    - **Validates: Requirements 1.1, 2.2, 2.3**

  - [ ]* 2.4 Write property test for glow disabled producing zero shadow
    - **Property 2: Glow disabled produces zero shadow**
    - Generate random `glowRadius` values in [5, 50] with `glowEnabled = false`
    - Verify `shadowOpacity` is 0 after `updateAppearance()`
    - File: `SpotdrawTests/CursorHighlightPropertyTests.swift`
    - **Validates: Requirements 1.6**

  - [ ]* 2.5 Write property test for glow color matching highlight color
    - **Property 3: Glow color matches highlight color**
    - Generate random `NSColor` values with `glowEnabled = true`
    - Verify `shadowColor` equals `highlightColor.cgColor` after `updateAppearance()`
    - File: `SpotdrawTests/CursorHighlightPropertyTests.swift`
    - **Validates: Requirements 1.2, 3.3**

- [ ] 3. CursorManager appearance forwarding
  - [ ] 3.1 Add `updateHighlightAppearance()` method to CursorManager
    - Add a public method `updateHighlightAppearance()` that calls `highlightWindow?.updateAppearance()`
    - This provides a clean entry point for menu, hotkey, and settings callbacks
    - File: `Spotdraw/Cursor/CursorManager.swift`
    - _Requirements: 1.3, 3.3, 3.5, 3.7_

- [ ] 4. Menu bar cursor highlight submenu
  - [ ] 4.1 Build the cursor highlight submenu in MenuBarController
    - Add a "Cursor Highlight" `NSMenuItem` with a submenu to the status menu
    - Add a "Color" section header and color preset items (Yellow, Red, Blue, Green, White) from `ColorPresets.cursor`
    - Add a separator and "Size" section header with size preset items: Small (30pt), Medium (50pt), Large (100pt), Extra Large (150pt)
    - Add a separator and "Glow" toggle item reflecting `SettingsManager.shared.glowEnabled`
    - Store references to color items, size items, and glow item for checkmark management
    - Place the submenu between the existing "Toggle Cursor Highlight" item and the next separator
    - File: `Spotdraw/MenuBar/MenuBarController.swift`
    - _Requirements: 3.1, 3.2, 3.4, 3.6, 3.8_

  - [ ] 4.2 Implement submenu action handlers and checkmark state
    - Add action methods for color selection: update `SettingsManager.highlightColor`, update checkmarks, invoke `onCursorSettingsChanged?()`
    - Add action methods for size selection: update `SettingsManager.highlightSize`, update checkmarks, invoke `onCursorSettingsChanged?()`
    - Add action method for glow toggle: toggle `SettingsManager.glowEnabled`, update item state, invoke `onCursorSettingsChanged?()`
    - Ensure exactly one checkmark in each preset group at all times
    - Add `var onCursorSettingsChanged: (() -> Void)?` callback property
    - File: `Spotdraw/MenuBar/MenuBarController.swift`
    - _Requirements: 3.3, 3.5, 3.7, 3.8, 5.5_

  - [ ]* 4.3 Write property test for submenu exclusive checkmarks
    - **Property 6: Submenu checkmarks reflect exclusive selection**
    - Generate random selections within color and size preset groups
    - Verify exactly one item in each group has state `.on` and all others have `.off`
    - File: `SpotdrawTests/MenuBarPropertyTests.swift`
    - **Validates: Requirements 3.8**

- [ ] 5. Wire menu callbacks through AppDelegate
  - [ ] 5.1 Connect `onCursorSettingsChanged` in AppDelegate
    - In AppDelegate's setup, assign `menuBarController.onCursorSettingsChanged` to call `cursorManager.updateHighlightAppearance()`
    - Ensure the callback only updates the window if the highlight is currently active
    - File: `Spotdraw/App/AppDelegate.swift`
    - _Requirements: 3.3, 3.5, 3.7_

- [ ] 6. Checkpoint — Verify glow and menu bar functionality
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 7. Size cycle keyboard shortcut
  - [ ] 7.1 Add `cycleCursorSize` case to GlobalShortcut enum in HotkeyManager
    - Add `.cycleCursorSize` case with keyCode `1` (S key)
    - Set modifiers to `[.control, .shift]` and cgEventFlags to `[.maskControl, .maskShift]`
    - Register the shortcut in the event tap handler
    - File: `Spotdraw/Core/HotkeyManager.swift`
    - _Requirements: 4.1_

  - [ ] 7.2 Implement size cycling logic in AppDelegate
    - Add `private let sizePresets: [CGFloat] = [30, 50, 100, 150]`
    - Add `private func cycleCursorSize()` that:
      - Finds the current size in presets; if exact match, advances index by 1 (mod 4)
      - If current size is not a preset, snaps to the smallest preset greater than current (wraps to index 0 if none)
      - Updates `settingsManager.highlightSize`
      - Calls `cursorManager.updateHighlightAppearance()` only if highlight is active
    - Wire the shortcut callback from HotkeyManager to `cycleCursorSize()`
    - File: `Spotdraw/App/AppDelegate.swift`
    - _Requirements: 4.1, 4.2, 4.3, 4.4_

  - [ ]* 7.3 Write property test for size cycle wrap
    - **Property 4: Size cycle wraps correctly**
    - Generate random starting indices 0..3, verify advancement to `(i+1) % 4`
    - Generate random non-preset sizes in [20, 200], verify snapping to next greater preset (wrapping)
    - File: `SpotdrawTests/SizeCyclePropertyTests.swift`
    - **Validates: Requirements 4.1, 4.2, 4.3**

- [ ] 8. Settings window integration
  - [ ] 8.1 Add glow controls to the Cursor settings tab
    - Add a "Glow Effect" toggle bound to `SettingsManager.shared.glowEnabled`
    - Add a "Glow Radius" slider with range 5–50, step 1, bound to `SettingsManager.shared.glowRadius`
    - Update the existing highlight size slider range from `20...100` to `20...200`
    - Trigger `cursorManager.updateHighlightAppearance()` on value changes (via a callback or notification)
    - File: `Spotdraw/Settings/SettingsWindowController.swift`
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5_

- [ ] 9. Final checkpoint — Build, run all tests, verify visually
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties from the design document
- Unit tests validate specific examples and edge cases
- All property tests use swift-testing with custom lightweight generator helpers as described in the design
- The glow is implemented via `CALayer.shadow*` properties — no custom gaussian blur shaders needed

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2", "2.1", "2.2", "3.1", "7.1", "8.1"] },
    { "id": 2, "tasks": ["2.3", "2.4", "2.5", "4.1", "5.1", "7.2"] },
    { "id": 3, "tasks": ["4.2", "7.3"] },
    { "id": 4, "tasks": ["4.3"] }
  ]
}
```
