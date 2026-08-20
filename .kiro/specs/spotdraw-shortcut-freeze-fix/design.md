# SpotDraw Shortcut Freeze Fix — Bugfix Design

## Overview

When the annotation overlay is activated via Ctrl+D, the application creates a full-screen `.screenSaver`-level window that captures all input, blocks access to other applications (including the menu bar and Dock), and — critically — prevents the global hotkey from firing again to deactivate the overlay. The user becomes trapped with no escape. The fix involves five coordinated changes: adding Accessibility permission gating, lowering the window level, ensuring the toggle shortcut always fires, making Escape deactivate the overlay, and providing mouse event passthrough when not actively drawing.

## Glossary

- **Bug_Condition (C)**: The set of states where the overlay is active AND the user cannot deactivate it via the expected mechanisms (Ctrl+D shortcut or Escape)
- **Property (P)**: The overlay SHALL always be deactivatable via Ctrl+D or Escape, the menu bar and Dock SHALL remain accessible, and the overlay SHALL NOT activate without Accessibility permission
- **Preservation**: All drawing functionality (tools, undo/redo, fade mode, board toggle), cursor highlight/spotlight features, and screen-change handling must remain unchanged
- **OverlayWindowController**: The class in `Spotdraw/Overlay/OverlayWindowController.swift` that manages overlay window creation, activation, and deactivation
- **HotkeyManager**: The class in `Spotdraw/Core/HotkeyManager.swift` that registers global and local event monitors for keyboard shortcuts
- **OverlayView**: The NSView subclass in `Spotdraw/Overlay/OverlayView.swift` that handles drawing, tool switching, and local key events
- **AXIsProcessTrusted()**: macOS Accessibility API function that returns whether the app has permission to monitor global keyboard events

## Bug Details

### Bug Condition

The bug manifests when the user presses Ctrl+D to activate the annotation overlay. Once active, the `.screenSaver`-level window captures all keyboard and mouse events, the `OverlayView`'s `keyDown` handler consumes key events (including Ctrl+D) without forwarding them to the global hotkey system, and there is no mechanism to deactivate the overlay — leaving the user trapped.

**Formal Specification:**
```
FUNCTION isBugCondition(input)
  INPUT: input of type UserAction (keyboard or mouse event while overlay is active)
  OUTPUT: boolean
  
  RETURN overlayController.isActive == true
         AND (
           (input.isKeyboardEvent AND input.keyCode == Ctrl+D AND globalMonitorCannotFire())
           OR (input.isKeyboardEvent AND input.keyCode == Escape AND escapeOnlyClearsDrawings())
           OR (input.isMouseEvent AND targetIsMenuBarOrDock(input) AND windowLevelBlocksAccess())
           OR (input.isActivationAttempt AND NOT accessibilityPermissionGranted())
         )
END FUNCTION
```

### Examples

- **Ctrl+D while overlay active**: User presses Ctrl+D expecting to deactivate the overlay, but `OverlayView.keyDown` receives the event first. Since "d" with control modifier doesn't match any case in the `switch`, it falls through to `super.keyDown(with:)` — but the global monitor never fires because the local monitor in `HotkeyManager` already handled it by calling the toggle handler, yet the event was already consumed by the view's responder chain. In practice, depending on event routing order, the shortcut may silently fail.
- **Escape while overlay active**: User presses Escape, `OverlayView.keyDown` matches `"\u{1B}"` and calls `clearAll()`, which only clears drawn items but does NOT call `overlayController.deactivate()`. The overlay remains active and capturing all input.
- **Click on menu bar while overlay active**: User tries to click the menu bar or Dock, but the overlay window at `.screenSaver` level with `ignoresMouseEvents = false` captures the click. The menu bar and Dock are inaccessible.
- **Activation without Accessibility permission**: User presses Ctrl+D, the overlay activates, but `NSEvent.addGlobalMonitorForEvents` silently fails without Accessibility permission. No subsequent global shortcut can be detected to deactivate the overlay.

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- All drawing tools (pen, highlighter, arrow, rectangle, circle, line, eraser) must continue to capture mouse events and produce drawings when the overlay is active
- Tool-switching keys (p, a, r, o, l, h, e, b, space) must continue to work as keyboard shortcuts while the overlay is active
- Cmd+Z and Cmd+Shift+Z must continue to perform undo/redo
- Drawn items must persist on the overlay when it is deactivated (visible but non-interactive)
- Ctrl+S and Ctrl+L must continue to toggle cursor highlight and spotlight independently
- Screen configuration changes must continue to trigger overlay window rebuilds
- Fade mode timer behavior must remain unchanged
- Shift-constrain behavior for shapes must remain unchanged

**Scope:**
All inputs that do NOT involve overlay activation/deactivation or desktop accessibility should be completely unaffected by this fix. This includes:
- Drawing interactions (mouse down, drag, up sequences)
- Tool switching via keyboard
- Undo/redo operations
- Board mode toggling
- Fade mode toggling
- Cursor highlight and spotlight features
- Screen change handling

## Hypothesized Root Cause

Based on the bug description and code analysis, the issues are:

1. **No Accessibility Permission Check**: `HotkeyManager.setupMonitors()` calls `NSEvent.addGlobalMonitorForEvents` unconditionally. Without Accessibility permission (AXIsProcessTrusted), this call succeeds but the monitor never fires for events outside the app. Once the overlay is active and the app owns focus, only the local monitor fires — but if the view's responder chain consumes the event first, the toggle handler may not execute reliably.

2. **Window Level Too High**: `OverlayWindowController.createOverlayWindow` sets `window.level = .screenSaver`, which renders above everything including the menu bar. Combined with `ignoresMouseEvents = false` during activation, this blocks ALL interaction with the rest of macOS.

3. **OverlayView Consumes Toggle Shortcut**: `OverlayView.keyDown` receives key events as first responder. While Ctrl+D doesn't match any explicit case (so it calls `super.keyDown`), the event routing between NSView's responder chain and `NSEvent.addLocalMonitorForEvents` creates ambiguity. The local monitor in `HotkeyManager` returns the event (doesn't consume it), but the ordering is fragile and platform-dependent.

4. **Escape Doesn't Deactivate**: `OverlayView.keyDown` handles Escape by calling `clearAll()` which only clears drawing state. It has no reference to `OverlayWindowController` and cannot call `deactivate()`. The user's only "escape" mechanism does nothing to exit the trapped state.

5. **No Mouse Passthrough Strategy**: When active, `ignoresMouseEvents = false` is set globally on the window. There's no mechanism to pass events through when the user isn't actively drawing, such as clicking the menu bar area.

## Correctness Properties

Property 1: Bug Condition - Overlay Deactivation Always Works

_For any_ state where the overlay is active, pressing Ctrl+D SHALL deactivate the overlay and restore normal desktop interaction, regardless of which view or monitor receives the event first.

**Validates: Requirements 2.3**

Property 2: Bug Condition - Escape Deactivates Overlay

_For any_ state where the overlay is active and the user presses Escape, the system SHALL deactivate the overlay entirely (not just clear drawings), restoring normal desktop interaction.

**Validates: Requirements 2.4**

Property 3: Bug Condition - Accessibility Permission Gating

_For any_ activation attempt where Accessibility permission has NOT been granted, the system SHALL NOT activate the overlay and SHALL inform the user that permission is required.

**Validates: Requirements 2.1, 2.6**

Property 4: Bug Condition - Menu Bar and Dock Accessible

_For any_ state where the overlay is active, the menu bar and Dock SHALL remain accessible for mouse interaction.

**Validates: Requirements 2.2, 2.5**

Property 5: Preservation - Drawing Functionality Unchanged

_For any_ drawing input (mouse events within the overlay area, tool-switch keys, undo/redo) while the overlay is active, the fixed code SHALL produce exactly the same behavior as the original code, preserving all drawing, tool-switching, and undo/redo functionality.

**Validates: Requirements 3.1, 3.2, 3.3**

Property 6: Preservation - Non-Overlay Features Unchanged

_For any_ input involving cursor highlight (Ctrl+S), spotlight (Ctrl+L), or screen configuration changes, the fixed code SHALL produce exactly the same behavior as the original code.

**Validates: Requirements 3.4, 3.5, 3.6**

## Fix Implementation

### Changes Required

Assuming our root cause analysis is correct:

**File**: `Spotdraw/Core/AccessibilityManager.swift` (NEW)

**Purpose**: New module to check and request Accessibility permission

**Specific Changes**:
1. **Create AccessibilityManager class**: Expose a static `checkPermission() -> Bool` method that calls `AXIsProcessTrusted()` and a `requestPermission()` method that calls `AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt: true` to show the system dialog
2. **Provide permission status observable**: Allow `AppDelegate` to check permission before registering hotkeys or activating overlay

---

**File**: `Spotdraw/Core/HotkeyManager.swift`

**Function**: `setupMonitors()`, `handleKeyEvent()`

**Specific Changes**:
1. **Gate monitor setup on Accessibility permission**: Only call `NSEvent.addGlobalMonitorForEvents` if `AXIsProcessTrusted()` returns true. Log a warning otherwise.
2. **Ensure local monitor forwards toggle events**: In the local monitor closure, after calling `handleKeyEvent`, return the event (already done — confirm this works correctly with the view responder chain fix below)

---

**File**: `Spotdraw/Overlay/OverlayWindowController.swift`

**Function**: `createOverlayWindow(for:)`, `activate()`, `deactivate()`

**Specific Changes**:
1. **Lower window level**: Change `window.level = .screenSaver` to `window.level = .floating` (or `.statusBar` at most). This keeps the overlay above normal windows but below the menu bar and system UI.
2. **Gate activation on permission**: Add a guard in `activate()` that checks `AccessibilityManager.checkPermission()` and returns early (with user notification) if permission is not granted.
3. **Consider NSPanel**: Optionally convert to `NSPanel` with `.nonactivatingPanel` style to allow clicks outside the panel to reach other apps. If staying with NSWindow, ensure window level allows menu bar access.

---

**File**: `Spotdraw/Overlay/OverlayView.swift`

**Function**: `keyDown(with:)`

**Specific Changes**:
1. **Add delegate/callback for deactivation**: Add a `var onDeactivate: (() -> Void)?` property (or weak delegate reference)
2. **Change Escape handling**: Replace `clearAll()` call with `onDeactivate?()` (which will call `overlayController.deactivate()`)
3. **Forward Ctrl+D to deactivation**: Add a case in `keyDown` that detects Ctrl+D (`characters == "d" && hasControl`) and calls `onDeactivate?()`, preventing the event from being swallowed silently
4. **Preserve existing shortcuts**: Ensure all other key handlers (tool switching, undo/redo, board toggle, fade toggle) remain unchanged

---

**File**: `Spotdraw/App/AppDelegate.swift`

**Function**: `applicationDidFinishLaunching(_:)`, `setupHotkeys()`, `setupOverlay()`

**Specific Changes**:
1. **Check Accessibility on launch**: Call `AccessibilityManager.requestPermission()` at the start of `applicationDidFinishLaunching`. If denied, show an alert explaining the requirement.
2. **Wire deactivation callback**: When setting up the overlay, configure `OverlayView.onDeactivate` to call `toggleAnnotation()` so that Escape and Ctrl+D from within the view properly deactivate the overlay.
3. **Guard toggle on permission**: In `toggleAnnotation()`, check permission before activating.

## Testing Strategy

### Validation Approach

The testing strategy follows a two-phase approach: first, surface counterexamples that demonstrate the bug on unfixed code, then verify the fix works correctly and preserves existing behavior.

### Exploratory Bug Condition Checking

**Goal**: Surface counterexamples that demonstrate the bug BEFORE implementing the fix. Confirm or refute the root cause analysis. If we refute, we will need to re-hypothesize.

**Test Plan**: Write tests that simulate the overlay being activated and then attempt deactivation through various mechanisms. Run these tests on the UNFIXED code to observe failures and understand the root cause.

**Test Cases**:
1. **Ctrl+D Toggle Test**: Activate overlay via `toggle()`, then simulate Ctrl+D keyDown event delivered to OverlayView — verify that `isActive` becomes false (will fail on unfixed code because OverlayView has no handler for Ctrl+D deactivation)
2. **Escape Deactivation Test**: Activate overlay, simulate Escape key — verify that `isActive` becomes false (will fail on unfixed code because Escape only calls `clearAll()`)
3. **Window Level Test**: Create overlay window and assert `window.level` is at or below `.statusBar` (will fail on unfixed code because it uses `.screenSaver`)
4. **Accessibility Permission Gate Test**: Mock `AXIsProcessTrusted()` returning false, call `activate()` — verify overlay does NOT activate (will fail on unfixed code because there's no permission check)

**Expected Counterexamples**:
- Overlay remains active after Ctrl+D is pressed while it has focus
- Overlay remains active after Escape is pressed (only drawings are cleared)
- Window level is `.screenSaver`, blocking menu bar
- Overlay activates without Accessibility permission, trapping the user

### Fix Checking

**Goal**: Verify that for all inputs where the bug condition holds, the fixed function produces the expected behavior.

**Pseudocode:**
```
FOR ALL input WHERE isBugCondition(input) DO
  result := fixedBehavior(input)
  ASSERT overlay.isActive == false OR accessibilityAlertShown OR menuBarAccessible
END FOR
```

### Preservation Checking

**Goal**: Verify that for all inputs where the bug condition does NOT hold, the fixed function produces the same result as the original function.

**Pseudocode:**
```
FOR ALL input WHERE NOT isBugCondition(input) DO
  ASSERT originalBehavior(input) == fixedBehavior(input)
END FOR
```

**Testing Approach**: Property-based testing is recommended for preservation checking because:
- It generates many test cases automatically across the drawing input domain (random points, tool selections, modifier key states)
- It catches edge cases that manual unit tests might miss (e.g., shift-constrained shapes, rapid tool switching)
- It provides strong guarantees that drawing behavior is unchanged for all non-deactivation inputs

**Test Plan**: Observe behavior on UNFIXED code first for drawing operations and tool switching, then write property-based tests capturing that behavior.

**Test Cases**:
1. **Drawing Preservation**: Verify that mouse down/drag/up sequences with each tool produce identical drawing items after fix
2. **Tool Switching Preservation**: Verify that pressing p, a, r, o, l, h, e changes `activeTool` identically after fix
3. **Undo/Redo Preservation**: Verify that Cmd+Z and Cmd+Shift+Z produce identical state changes after fix
4. **Cursor/Spotlight Preservation**: Verify that Ctrl+S and Ctrl+L continue to toggle their respective features

### Unit Tests

- Test `AccessibilityManager.checkPermission()` returns correct boolean based on system state
- Test that `OverlayWindowController.activate()` returns early when permission is denied
- Test that `OverlayView.keyDown` with Escape calls `onDeactivate` callback
- Test that `OverlayView.keyDown` with Ctrl+D calls `onDeactivate` callback
- Test that window level is `.floating` (not `.screenSaver`)
- Test that all tool-switching keys still work after adding Ctrl+D and Escape handling
- Test that Cmd+Z/Cmd+Shift+Z still trigger undo/redo

### Property-Based Tests

- Generate random sequences of tool-switch keys and verify `activeTool` matches expected tool for each key
- Generate random drawing sessions (random points, random tools) and verify drawn items are created correctly
- Generate random modifier key combinations and verify only Ctrl+D triggers deactivation (not Cmd+D, Shift+D, etc.)
- Generate random event sequences mixing drawing and shortcut keys to verify no state corruption

### Integration Tests

- Test full activation → draw → deactivate → reactivate cycle preserves drawing state
- Test that Ctrl+D deactivation and Escape deactivation both result in `isActive == false` and `ignoresMouseEvents == true`
- Test that overlay windows at `.floating` level do not obscure menu bar clicks (using accessibility API or UI testing)
- Test that permission denial at launch prevents any activation and shows appropriate alert
- Test that screen configuration changes still rebuild windows correctly after the fix
