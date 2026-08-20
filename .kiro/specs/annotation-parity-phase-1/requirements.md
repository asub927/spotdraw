# Requirements Document

## Introduction

SpotDraw is a macOS menu bar screen-annotation utility. A competitive analysis against Presentify and epilande/Annotate identified five table-stakes capability gaps. This spec closes all five:

1. **Text annotation** — SpotDraw has no way to place text on screen.
2. **Select / move / delete** — the only removal paths today are the proximity eraser and Clear All; individual items cannot be selected, repositioned, or deleted.
3. **Zoom activation** — `Spotdraw/Zoom/ZoomWindow.swift` is fully implemented but unreachable: `GlobalShortcut.toggleZoom` is registered nowhere and `CursorManager.toggleZoom()` is never called.
4. **Customizable shortcuts** — every binding is hardcoded in `GlobalShortcut`, `ToolType.keyCharacter`, `ColorShortcut.keyCharacter`, and `OverlayView.keyDown(with:)`.
5. **Fn-key passthrough and Interactive Mode** — while the overlay is active it captures all mouse input, so the application beneath cannot be clicked or scrolled.

The final requirement group protects existing behavior (drawing tools, undo/redo, fade, board mode, cursor highlight, spotlight) from regression.

## Glossary

- **SpotDraw**: The complete macOS application, including menu bar item, overlay windows, and settings window.
- **Annotation_Overlay**: The set of full-screen transparent windows managed by `OverlayWindowController`, one per display.
- **Overlay_View**: The `OverlayView` instance that handles mouse and keyboard input and renders drawing content for one display.
- **Overlay_Window_Controller**: The `OverlayWindowController` instance that owns the Annotation_Overlay windows and their mouse-event acceptance state.
- **Drawing_State**: The `DrawingState` instance shared across all Overlay_View instances; owns the item list, undo stack, redo stack, and active tool, color, and line width.
- **Drawing_Item**: Any type conforming to the `DrawingItem` protocol (`FreehandStroke`, `ArrowShape`, `RectangleShape`, `CircleShape`, `LineShape`, and the new `Text_Annotation`).
- **Text_Annotation**: A new Drawing_Item that renders a string at an anchor point using a color and font size.
- **Text_Editor_Field**: The inline editable text control displayed on the Overlay_View while a Text_Annotation is being composed or edited.
- **Editing_State**: The condition in which a Text_Editor_Field is present and accepting keystrokes.
- **Selection_Manager**: The component that owns the set of currently selected Drawing_Item identifiers and derives the selection bounding box.
- **Selection**: The set of Drawing_Item instances currently held by the Selection_Manager.
- **Selection_Bounding_Box**: The smallest rectangle containing the bounding rectangles of all items in the Selection.
- **Marquee**: The rectangle defined by a press-and-drag gesture that begins on empty overlay space while the select tool is active.
- **Zoom_Window**: The `ZoomWindow` instance that renders the magnification bubble.
- **Cursor_Manager**: The `CursorManager` instance that owns the cursor highlight, spotlight, and Zoom_Window lifecycles and the shared global mouse monitor.
- **Hotkey_Manager**: The `HotkeyManager` instance that owns the CGEvent tap and the local `NSEvent` monitor for global shortcut dispatch.
- **Shortcut_Store**: A new component that owns the mapping from shortcut action identifier to key binding, including defaults, persistence, and conflict lookup.
- **Shortcut_Action**: One named, bindable behavior (for example "Toggle Annotation", "Select Pen Tool", "Undo").
- **Key_Binding**: A key code paired with a set of modifier flags.
- **Recording_State**: The condition in which the Shortcuts tab is capturing the next key press to assign it to a Shortcut_Action.
- **Settings_Manager**: The `SettingsManager` singleton that persists preferences in `UserDefaults`.
- **Settings_Window**: The window presented by `SettingsWindowController`, hosting the SwiftUI `SettingsView` tab set.
- **Menu_Bar_Controller**: The `MenuBarController` instance that owns the `NSStatusItem` menu.
- **Passthrough_State**: The condition in which the Annotation_Overlay windows ignore mouse events so the application beneath receives them.
- **Interactive_Mode**: An opt-in mode in which the Annotation_Overlay is in Passthrough_State by default and captures mouse input only while the Fn modifier is held.
- **Fn_Modifier**: The macOS function modifier reported as `NSEvent.ModifierFlags.function`.
- **Mode_Indicator**: The on-screen badge that reports whether the Annotation_Overlay is currently capturing or passing through mouse input.

## Requirements

### Requirement 1: Text Annotation Tool

**User Story:** As a presenter, I want to place text labels on the screen, so that I can name and explain the things I am pointing at.

#### Acceptance Criteria

1. THE Drawing_State SHALL expose a text tool as a `ToolType` case that can be set as the active tool.
2. WHEN the Overlay_View receives the Key_Binding assigned to the text tool, THE Drawing_State SHALL set the active tool to the text tool.
3. WHILE the text tool is the active tool, WHEN the user presses the primary mouse button at a point on the Overlay_View that lies outside every existing Text_Annotation, THE Overlay_View SHALL enter Editing_State with an empty Text_Editor_Field anchored at that point.
4. WHILE the Overlay_View is in Editing_State, WHEN the user types a character, THE Overlay_View SHALL append that character to the Text_Editor_Field contents and render the contents in the active color of the Drawing_State at the font size stored by the Settings_Manager.
5. WHILE the Overlay_View is in Editing_State, WHEN the user presses Return, THE Overlay_View SHALL commit the Text_Editor_Field contents as a Text_Annotation, add the Text_Annotation to the Drawing_State items, and leave Editing_State.
6. WHILE the Overlay_View is in Editing_State, WHEN the user presses Escape, THE Overlay_View SHALL commit the Text_Editor_Field contents as a Text_Annotation, leave Editing_State, and keep the Annotation_Overlay active.
7. IF the Text_Editor_Field contains zero characters or contains only whitespace characters at the moment Editing_State ends, THEN THE Overlay_View SHALL leave Editing_State and leave the Drawing_State items unchanged.
8. WHILE the text tool is the active tool, WHEN the user double-clicks within the bounding rectangle of an existing Text_Annotation, THE Overlay_View SHALL enter Editing_State with a Text_Editor_Field containing that Text_Annotation's current string, anchored at that Text_Annotation's anchor point.
9. WHEN the Overlay_View commits an edit of an existing Text_Annotation, THE Drawing_State SHALL replace the previous Text_Annotation with the edited Text_Annotation at the same position in the item list and record one undoable operation.
10. WHILE the text tool is the active tool, WHEN the user drags from a point inside the bounding rectangle of an existing Text_Annotation, THE Overlay_View SHALL move that Text_Annotation's anchor point by the drag delta and record one undoable operation when the drag ends.
11. THE Text_Annotation SHALL conform to the `DrawingItem` protocol, including rendering into a `CGContext`, hit testing against a point and threshold, and exposing a mutable opacity for fade processing.
12. THE Text_Annotation SHALL report a bounding rectangle that contains all rendered glyphs of its string.
13. THE Settings_Manager SHALL persist a default text font size in the range 8 points to 96 points, with an initial value of 24 points.
14. THE Settings_Window SHALL provide a control in the Annotation tab that sets the persisted default text font size.
15. WHEN the Overlay_View commits a Text_Annotation, THE Text_Annotation SHALL retain the color and font size that were in effect at the time Editing_State was entered.

### Requirement 2: Select Tool — Selection

**User Story:** As a user, I want to select specific annotations, so that I can act on individual items instead of erasing by proximity or clearing everything.

#### Acceptance Criteria

1. THE Drawing_State SHALL expose a select tool as a `ToolType` case that can be set as the active tool.
2. WHEN the Overlay_View receives the Key_Binding assigned to the select tool, THE Drawing_State SHALL set the active tool to the select tool.
3. THE `DrawingItem` protocol SHALL expose a bounding rectangle for every conforming type.
4. WHILE the select tool is the active tool, WHEN the user clicks a point for which at least one Drawing_Item returns true from `hitTest(point:threshold:)`, THE Selection_Manager SHALL set the Selection to the single topmost matching Drawing_Item.
5. WHILE the select tool is the active tool, WHEN the user clicks a point for which no Drawing_Item returns true from `hitTest(point:threshold:)` and the Fn_Modifier and Shift modifier are released, THE Selection_Manager SHALL set the Selection to zero items.
6. WHILE the select tool is the active tool AND the Selection contains zero items, WHEN the user drags from a point that hits no Drawing_Item, THE Overlay_View SHALL render a dashed Marquee rectangle spanning the press point and the current cursor point.
7. WHEN a Marquee drag ends, THE Selection_Manager SHALL set the Selection to every Drawing_Item whose bounding rectangle intersects the Marquee rectangle.
8. WHILE the select tool is the active tool, WHEN the user clicks a Drawing_Item that is absent from the Selection with the Shift modifier held, THE Selection_Manager SHALL add that Drawing_Item to the Selection and retain all previously selected items.
9. WHILE the select tool is the active tool, WHEN the user clicks a Drawing_Item that is present in the Selection with the Shift modifier held, THE Selection_Manager SHALL remove that Drawing_Item from the Selection and retain all other selected items.
10. WHILE the select tool is the active tool, WHEN the Overlay_View receives the Key_Binding assigned to the select-all action, THE Selection_Manager SHALL set the Selection to every Drawing_Item in the Drawing_State.
11. WHILE the Selection contains at least one Drawing_Item, THE Overlay_View SHALL render a dashed outline around the bounding rectangle of each selected Drawing_Item.
12. WHEN the active tool of the Drawing_State changes to a tool other than the select tool, THE Selection_Manager SHALL set the Selection to zero items.
13. WHEN the Annotation_Overlay is deactivated, THE Selection_Manager SHALL set the Selection to zero items.
14. WHEN a Drawing_Item is removed from the Drawing_State by any means, THE Selection_Manager SHALL remove that Drawing_Item from the Selection.
15. WHILE the Selection contains at least one Drawing_Item, THE Overlay_View SHALL render the dashed outlines above every Drawing_Item and above the board background.

### Requirement 3: Select Tool — Move and Delete

**User Story:** As a user, I want to move and delete selected annotations, so that I can correct mistakes and rearrange a diagram without starting over.

#### Acceptance Criteria

1. THE `DrawingItem` protocol SHALL expose an operation that translates the item's rendered geometry by a horizontal and vertical offset.
2. WHILE the select tool is the active tool AND the Selection contains at least one Drawing_Item, WHEN the user drags from a point inside the Selection_Bounding_Box, THE Overlay_View SHALL translate every Drawing_Item in the Selection by the drag delta.
3. WHILE a move drag is in progress, THE Overlay_View SHALL render the translated Drawing_Item positions on every mouse-dragged event.
4. WHEN a move drag ends with a net translation of at least 1 point in either axis, THE Drawing_State SHALL record one undoable operation that stores the translated Drawing_Item identifiers and the net offset.
5. WHEN the undo action is invoked immediately after a recorded move operation, THE Drawing_State SHALL translate the affected Drawing_Item instances by the inverse of the recorded offset.
6. WHEN the redo action is invoked immediately after undoing a move operation, THE Drawing_State SHALL translate the affected Drawing_Item instances by the recorded offset.
7. WHILE the Selection contains at least one Drawing_Item, WHEN the Overlay_View receives the Key_Binding assigned to the delete-selection action, THE Drawing_State SHALL remove every Drawing_Item in the Selection and record one undoable operation.
8. WHEN a delete-selection operation is undone, THE Drawing_State SHALL restore every removed Drawing_Item at its original index in the item list.
9. IF a move drag would place the Selection_Bounding_Box entirely outside the bounds of the Overlay_View, THEN THE Overlay_View SHALL clamp the applied translation so that at least 20 points of the Selection_Bounding_Box remain inside the bounds.
10. WHEN a move drag ends with a net translation below 1 point in both axes, THE Drawing_State SHALL leave the undo stack unchanged.
11. THE Selection_Manager SHALL retain the Selection after a completed move drag.

### Requirement 4: Zoom Feature Activation

**User Story:** As a presenter, I want to magnify the area around my cursor, so that my audience can read small on-screen details.

#### Acceptance Criteria

1. THE Hotkey_Manager SHALL register a Shortcut_Action that invokes `CursorManager.toggleZoom()`.
2. THE Shortcut_Store SHALL assign each default Key_Binding such that no two Shortcut_Actions in the same dispatch scope share the same key code and modifier set.
3. WHEN the Key_Binding assigned to the zoom toggle action is pressed AND `CursorManager.isZoomActive` is false, THE Cursor_Manager SHALL show the Zoom_Window and start the capture timer.
4. WHEN the Key_Binding assigned to the zoom toggle action is pressed AND `CursorManager.isZoomActive` is true, THE Cursor_Manager SHALL hide the Zoom_Window and stop the capture timer.
5. THE Menu_Bar_Controller SHALL display a zoom toggle menu item whose title includes the currently assigned Key_Binding.
6. WHEN the zoom active state changes, THE Menu_Bar_Controller SHALL set the zoom menu item state to on while zoom is active and to off while zoom is inactive.
7. IF Screen Recording permission is absent when zoom activation is requested, THEN THE SpotDraw SHALL present an alert that offers a button opening the System Settings Screen Recording pane and SHALL leave `CursorManager.isZoomActive` false.
8. WHILE zoom is active, WHEN the global mouse monitor reports a cursor position change, THE Cursor_Manager SHALL update the Zoom_Window position to that cursor position.
9. WHILE zoom is active, THE Zoom_Window SHALL exclude its own window from each captured image.
10. WHEN the Annotation_Overlay is activated while zoom is active, THE Cursor_Manager SHALL keep zoom active.
11. WHEN SpotDraw terminates while zoom is active, THE Cursor_Manager SHALL stop the capture timer and release the Zoom_Window.

### Requirement 5: Zoom Settings and Controls

**User Story:** As a presenter, I want to adjust the magnification level and bubble size, so that the zoom bubble suits my display and content.

#### Acceptance Criteria

1. THE Settings_Manager SHALL persist a zoom level in the range 2.0 to 4.0, with an initial value of 2.0.
2. THE Settings_Manager SHALL persist a zoom bubble size in the range 100 points to 300 points, with an initial value of 200 points.
3. WHEN the Zoom_Window is shown, THE Cursor_Manager SHALL set the Zoom_Window zoom level and bubble size from the values persisted by the Settings_Manager.
4. WHILE zoom is active, WHEN the Key_Binding assigned to the zoom-in action is pressed, THE Cursor_Manager SHALL increase the zoom level by 0.5 and persist the new value.
5. WHILE zoom is active, WHEN the Key_Binding assigned to the zoom-out action is pressed, THE Cursor_Manager SHALL decrease the zoom level by 0.5 and persist the new value.
6. IF the zoom-in action is invoked while the zoom level equals 4.0, THEN THE Cursor_Manager SHALL retain the zoom level at 4.0.
7. IF the zoom-out action is invoked while the zoom level equals 2.0, THEN THE Cursor_Manager SHALL retain the zoom level at 2.0.
8. THE Settings_Window SHALL provide a Zoom section containing a zoom level control spanning 2.0 to 4.0 and a bubble size control spanning 100 points to 300 points.
9. WHEN a zoom setting value changes while zoom is active, THE Cursor_Manager SHALL apply the new value to the Zoom_Window before the next captured frame is rendered.
10. WHEN the bubble size value changes, THE Zoom_Window SHALL resize its window, its circular mask path, and its border ring path to the new size.

### Requirement 6: Customizable Shortcuts — Storage and Defaults

**User Story:** As a user, I want my own key bindings, so that SpotDraw does not collide with the shortcuts of the applications I present from.

#### Acceptance Criteria

1. THE Shortcut_Store SHALL define one Shortcut_Action for each global toggle: toggle annotation, toggle cursor highlight, toggle spotlight, toggle zoom, cycle cursor size, zoom in, zoom out, and toggle Interactive_Mode.
2. THE Shortcut_Store SHALL define one Shortcut_Action for each annotation tool, including pen, arrow, rectangle, circle, line, highlighter, eraser, text, and select.
3. THE Shortcut_Store SHALL define one Shortcut_Action for each color preset in `ColorShortcut`.
4. THE Shortcut_Store SHALL define one Shortcut_Action for each overlay action: undo, redo, clear all, cycle board mode, toggle fade mode, delete selection, select all, and deactivate overlay.
5. THE Shortcut_Store SHALL store one Key_Binding, consisting of a key code and a modifier flag set, for each assigned Shortcut_Action.
6. THE Shortcut_Store SHALL persist all assigned Key_Bindings through the Settings_Manager and SHALL restore those Key_Bindings at application launch.
7. WHEN the Shortcut_Store is queried for a Shortcut_Action that has no persisted Key_Binding and no cleared marker, THE Shortcut_Store SHALL return that Shortcut_Action's default Key_Binding.
8. THE Shortcut_Store SHALL provide serialization of the complete binding set to a `UserDefaults`-storable representation and deserialization from that representation, such that deserializing a serialized binding set yields an equivalent binding set.
9. WHEN the Hotkey_Manager receives a key-down event through the CGEvent tap, THE Hotkey_Manager SHALL resolve the event against the Shortcut_Store rather than against hardcoded `GlobalShortcut` values.
10. WHEN the Overlay_View receives a key-down event, THE Overlay_View SHALL resolve the event against the Shortcut_Store rather than against hardcoded characters.
11. WHEN a Key_Binding assignment changes, THE Hotkey_Manager SHALL dispatch subsequent matching key events to the newly assigned Shortcut_Action without an application restart.
12. IF a persisted Key_Binding representation fails to deserialize, THEN THE Shortcut_Store SHALL return the default Key_Binding for the affected Shortcut_Action and SHALL write a log entry naming that Shortcut_Action.
13. WHILE a Shortcut_Action carries a cleared marker, THE Shortcut_Store SHALL return no Key_Binding for that Shortcut_Action, and THE Hotkey_Manager and Overlay_View SHALL leave the corresponding key events unhandled.
14. THE Shortcut_Store SHALL define the following default Key_Bindings for backward compatibility: Control+D for toggle annotation, Control+S for toggle cursor highlight, Control+L for toggle spotlight, Control+Shift+S for cycle cursor size, and the existing single-character bindings for tools, colors, board cycle, and fade toggle.
15. WHEN the Hotkey_Manager resolves a key event to an assigned Shortcut_Action, THE Hotkey_Manager SHALL consume the event so that other applications receive no key event.

### Requirement 7: Customizable Shortcuts — Settings UI

**User Story:** As a user, I want to view and change shortcuts in the settings window, so that I can rebind actions without editing configuration files.

#### Acceptance Criteria

1. THE Settings_Window SHALL provide a Shortcuts tab.
2. THE Shortcuts tab SHALL group Shortcut_Action rows under four category headings: Global, Annotation Tools, Colors, and Actions.
3. THE Shortcuts tab SHALL display, for each Shortcut_Action row, the action name and a human-readable rendering of the currently assigned Key_Binding.
4. WHILE a Shortcut_Action carries a cleared marker, THE Shortcuts tab SHALL display the text "None" in that Shortcut_Action's binding field.
5. WHEN the user activates the record control of a Shortcut_Action row, THE Shortcuts tab SHALL enter Recording_State for that Shortcut_Action and SHALL display a prompt requesting a key combination.
6. WHILE the Shortcuts tab is in Recording_State, WHEN the user presses a non-modifier key, THE Shortcuts tab SHALL capture the key code together with the pressed modifier flags as a candidate Key_Binding and SHALL leave Recording_State.
7. WHEN a candidate Key_Binding matches no Key_Binding assigned to another Shortcut_Action, THE Shortcut_Store SHALL assign the candidate Key_Binding to the recorded Shortcut_Action and persist the assignment.
8. IF a candidate Key_Binding matches the Key_Binding assigned to another Shortcut_Action, THEN THE Shortcuts tab SHALL display a conflict message naming that other Shortcut_Action and SHALL retain the existing assignments until the user confirms the replacement.
9. WHEN the user confirms a conflicting replacement, THE Shortcut_Store SHALL set a cleared marker on the previously assigned Shortcut_Action and assign the candidate Key_Binding to the recorded Shortcut_Action.
10. WHILE the Shortcuts tab is in Recording_State, WHEN the user presses Escape, THE Shortcuts tab SHALL leave Recording_State and retain the existing assignment for that Shortcut_Action.
11. IF a candidate Key_Binding for a global Shortcut_Action contains zero modifier flags, THEN THE Shortcuts tab SHALL display a message stating that global shortcuts require at least one modifier key and SHALL retain the existing assignment.
12. WHEN the user activates the clear control of a Shortcut_Action row, THE Shortcut_Store SHALL set a cleared marker on that Shortcut_Action and persist the cleared marker.
13. WHEN the user activates the reset control of a Shortcut_Action row, THE Shortcut_Store SHALL restore that Shortcut_Action's default Key_Binding and persist the assignment.
14. WHEN the user activates the reset-all control, THE Shortcut_Store SHALL restore the default Key_Binding of every Shortcut_Action and persist the assignments.
15. WHEN a Key_Binding assignment changes through the Shortcuts tab, THE Shortcuts tab SHALL display the new binding in the affected Shortcut_Action rows within the same update cycle.
16. WHILE the Shortcuts tab is in Recording_State, THE Hotkey_Manager SHALL leave global Shortcut_Actions undispatched so that the recorded combination reaches the Shortcuts tab.

### Requirement 8: Fn-Key Passthrough

**User Story:** As a presenter, I want to click through my annotations while the overlay stays visible, so that I can operate the application underneath without turning annotation off.

#### Acceptance Criteria

1. WHILE the Annotation_Overlay is active AND Interactive_Mode is disabled, WHEN the Fn_Modifier transitions to pressed, THE Overlay_Window_Controller SHALL enter Passthrough_State by setting every Annotation_Overlay window to ignore mouse events.
2. WHILE the Annotation_Overlay is active AND Interactive_Mode is disabled, WHEN the Fn_Modifier transitions to released, THE Overlay_Window_Controller SHALL leave Passthrough_State by setting every Annotation_Overlay window to accept mouse events.
3. WHILE the Annotation_Overlay is in Passthrough_State, THE Overlay_View SHALL continue to render every committed Drawing_Item and the board background.
4. IF the Fn_Modifier transitions to pressed while a drawing gesture is in progress, THEN THE Overlay_View SHALL commit the in-progress Drawing_Item using the current cursor point and then enter Passthrough_State.
5. IF the Fn_Modifier transitions to pressed while the Overlay_View is in Editing_State, THEN THE Overlay_View SHALL commit the Text_Editor_Field contents, leave Editing_State, and then enter Passthrough_State.
6. WHEN the Annotation_Overlay enters Passthrough_State, THE Overlay_View SHALL display the Mode_Indicator reporting that mouse input passes to the application beneath.
7. WHEN the Annotation_Overlay leaves Passthrough_State, THE Overlay_View SHALL remove the Mode_Indicator that reports passthrough.
8. WHILE the Annotation_Overlay is in Passthrough_State, THE SpotDraw SHALL set the cursor to the system arrow cursor.
9. WHILE the Annotation_Overlay is active AND outside Passthrough_State, THE SpotDraw SHALL set the cursor to the crosshair cursor.
10. WHEN the Annotation_Overlay is deactivated while the Fn_Modifier is pressed, THE Overlay_Window_Controller SHALL set every Annotation_Overlay window to ignore mouse events and remove the Mode_Indicator.
11. WHILE the Annotation_Overlay is in Passthrough_State, THE Hotkey_Manager SHALL continue to dispatch global Shortcut_Actions.
12. WHEN the Annotation_Overlay windows are rebuilt after a screen parameter change, THE Overlay_Window_Controller SHALL apply the current Passthrough_State to every newly created window.

### Requirement 9: Interactive Mode

**User Story:** As a user who annotates occasionally during long working sessions, I want the overlay to stay out of my way by default, so that I can leave it on and draw only when I hold a key.

#### Acceptance Criteria

1. THE Settings_Manager SHALL persist an Interactive_Mode enabled flag with an initial value of false.
2. THE Settings_Window SHALL provide a control in the General tab that sets the persisted Interactive_Mode enabled flag.
3. THE Menu_Bar_Controller SHALL provide an Interactive_Mode menu item whose state is on while Interactive_Mode is enabled and off while Interactive_Mode is disabled.
4. WHILE Interactive_Mode is enabled AND the Annotation_Overlay is active AND the Fn_Modifier is released, THE Overlay_Window_Controller SHALL keep every Annotation_Overlay window in Passthrough_State.
5. WHILE Interactive_Mode is enabled AND the Annotation_Overlay is active, WHEN the Fn_Modifier transitions to pressed, THE Overlay_Window_Controller SHALL set every Annotation_Overlay window to accept mouse events.
6. WHILE Interactive_Mode is enabled AND the Annotation_Overlay is active, WHEN the Fn_Modifier transitions to released, THE Overlay_Window_Controller SHALL set every Annotation_Overlay window to ignore mouse events.
7. WHEN the Interactive_Mode enabled flag changes while the Annotation_Overlay is active, THE Overlay_Window_Controller SHALL apply the mouse-event acceptance state implied by the new flag value and the current Fn_Modifier state.
8. WHILE Interactive_Mode is enabled AND the Annotation_Overlay is active, THE Overlay_View SHALL display the Mode_Indicator reporting whether the overlay currently captures mouse input or passes mouse input through.
9. WHILE Interactive_Mode is enabled AND the Annotation_Overlay is active AND the Fn_Modifier is released, THE Hotkey_Manager SHALL continue to dispatch global Shortcut_Actions.
10. WHEN Interactive_Mode is enabled while the Annotation_Overlay is active, THE Drawing_State SHALL retain every existing Drawing_Item.
11. WHEN the Key_Binding assigned to the toggle Interactive_Mode action is pressed, THE SpotDraw SHALL invert the persisted Interactive_Mode enabled flag.

### Requirement 10: Regression Prevention

**User Story:** As an existing SpotDraw user, I want the features I already rely on to behave exactly as before, so that this release adds capability without cost.

#### Acceptance Criteria

1. WHEN the pen, highlighter, arrow, rectangle, circle, or line tool is active and the user completes a drawing gesture, THE Drawing_State SHALL add the corresponding Drawing_Item with the geometry, color, line width, and alpha produced by the current implementation.
2. WHEN the eraser tool is active and the user presses or drags the primary mouse button, THE Drawing_State SHALL remove every Drawing_Item that returns true from `hitTest(point:threshold:)` at threshold 15.
3. WHEN the undo action is invoked after a Drawing_Item is added, THE Drawing_State SHALL move that Drawing_Item to the redo stack, and WHEN the redo action is invoked, THE Drawing_State SHALL return that Drawing_Item to the item list.
4. WHEN a new Drawing_Item is added, THE Drawing_State SHALL clear the redo stack.
5. WHILE fade mode is enabled, WHEN a Drawing_Item age exceeds the configured fade duration by more than 1 second, THE Overlay_View SHALL remove that Drawing_Item, including Text_Annotation instances.
6. WHEN the board cycle action is invoked, THE Drawing_State SHALL advance the board mode through the sequence none, white, black, none.
7. WHILE the board mode is white or black, THE Overlay_View SHALL render the board background beneath every Drawing_Item, the Marquee, and the selection outlines.
8. WHEN the clear-all action is invoked, THE Drawing_State SHALL remove every Drawing_Item, clear the undo stack, clear the redo stack, and THE Selection_Manager SHALL set the Selection to zero items.
9. WHEN the cursor highlight or spotlight feature is toggled, THE Cursor_Manager SHALL show or hide the corresponding window independently of the Annotation_Overlay state, the Selection, and the Editing_State.
10. WHEN the screen parameters change while the Annotation_Overlay is active, THE Overlay_Window_Controller SHALL rebuild the Annotation_Overlay windows and THE Drawing_State SHALL retain every Drawing_Item.
11. WHILE Accessibility permission is absent, WHEN the user requests Annotation_Overlay activation, THE SpotDraw SHALL present the Accessibility permission alert and leave the Annotation_Overlay inactive.
12. WHEN the Overlay_View receives the Key_Binding assigned to the deactivate-overlay action and the Overlay_View is outside Editing_State, THE Overlay_View SHALL invoke the deactivation callback.
13. WHEN the Cursor_Manager has no active cursor highlight, spotlight, or zoom feature, THE Cursor_Manager SHALL remove the global mouse monitor.

## Open Questions for Design

1. **Zoom toggle default binding.** `GlobalShortcut.toggleZoom` currently declares Control+Z. Control+Z is widely used as an undo binding by other applications, and the CGEvent tap consumes matched events globally, so this default would swallow Control+Z system-wide. Requirement 6.2 forbids duplicate defaults but does not name the zoom default; the design must choose a binding that avoids this collision.
2. **Geometry mutability for moves.** Existing `DrawingItem` conformances in `Spotdraw/Core/DrawingItems.swift` store immutable geometry (`let points`, `let rect`, `let start`, `let end`). Requirement 3.1 requires a translation operation. The design must choose between making the stored geometry mutable, adding a translation offset applied at draw and hit-test time, or replacing items with translated copies.
3. **Fn modifier reliability.** `NSEvent.ModifierFlags.function` is reported for the Fn key on built-in keyboards but behaves inconsistently on some third-party keyboards, and `flagsChanged` only reaches the Overlay_View while a SpotDraw window is key. The design must determine whether Fn state is observed through the existing CGEvent tap, a dedicated flags-changed monitor, or a user-selectable alternate modifier.
4. **Undo stack shape.** `DrawingState` currently models undo as two arrays of items, which cannot represent a move. The design must decide whether to generalize the stack to an operation list.
