# Implementation Plan

## Overview

Fix the overlay trapping bug in Spotdraw where users cannot deactivate the annotation overlay via keyboard shortcuts. The fix adds Ctrl+D and Escape as deactivation keys, lowers the window level from `.screenSaver` to `.floating`, and gates activation on accessibility permissions. Uses bug condition methodology: explore the bug with failing tests, preserve existing behavior, implement the fix, then validate.

## Tasks

- [ ] 1. Write bug condition exploration test
  - **Property 1: Bug Condition** - Overlay Traps User (No Deactivation Possible)
  - **IMPORTANT**: Write this property-based test BEFORE implementing the fix
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior - it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate the overlay cannot be deactivated
  - **Scoped PBT Approach**: Scope properties to concrete failing cases:
    - Ctrl+D keyDown delivered to OverlayView while overlay is active → overlay should deactivate
    - Escape keyDown while overlay is active → overlay should deactivate (not just clear drawings)
    - Window level should be at or below `.statusBar` (not `.screenSaver`)
    - Activation without accessibility permission should be blocked
  - **Test file**: Create `SpotdrawTests/OverlayDeactivationTests.swift`
  - Test 1: Activate overlay via `toggle()`, simulate Ctrl+D keyDown event → assert `isActive == false` (from Bug Condition: `overlayController.isActive == true AND input.keyCode == Ctrl+D AND globalMonitorCannotFire()`)
  - Test 2: Activate overlay, simulate Escape key → assert `isActive == false` (from Bug Condition: `input.keyCode == Escape AND escapeOnlyClearsDrawings()`)
  - Test 3: Create overlay window → assert `window.level` is `.floating` or lower (from Bug Condition: `windowLevelBlocksAccess()`)
  - Test 4: Mock accessibility permission as denied, call `activate()` → assert overlay does NOT activate (from Bug Condition: `NOT accessibilityPermissionGranted()`)
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests FAIL (this is correct - it proves the bug exists):
    - Test 1 fails: OverlayView has no Ctrl+D handler, overlay remains active
    - Test 2 fails: Escape calls `clearAll()` not deactivate, overlay remains active
    - Test 3 fails: Window level is `.screenSaver`, not `.floating`
    - Test 4 fails: No permission check exists, overlay activates regardless
  - Document counterexamples found to understand root cause
  - Mark task complete when tests are written, run, and failures are documented
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5_

- [ ] 2. Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - Drawing and Feature Functionality Unchanged
  - **IMPORTANT**: Follow observation-first methodology
  - **Step 1 - Observe behavior on UNFIXED code for non-buggy inputs:**
    - Observe: Pressing "p" sets `activeTool = .pen`
    - Observe: Pressing "a" sets `activeTool = .arrow`
    - Observe: Pressing "r" sets `activeTool = .rectangle`
    - Observe: Pressing "o" sets `activeTool = .circle`
    - Observe: Pressing "l" sets `activeTool = .line`
    - Observe: Pressing "h" sets `activeTool = .highlighter`
    - Observe: Pressing "e" sets `activeTool = .eraser`
    - Observe: Mouse down/drag/up with pen tool creates FreehandStroke with correct points, color, lineWidth
    - Observe: Mouse down/drag/up with rectangle tool creates RectangleShape with correct rect
    - Observe: Cmd+Z triggers undo (removes last item from drawingState.items)
    - Observe: Cmd+Shift+Z triggers redo (re-adds item)
    - Observe: Pressing "b" cycles board mode (none → white → black → none)
    - Observe: Pressing space toggles fadeMode
    - Observe: Shift-held during shape drawing constrains to 45° angles
  - **Step 2 - Write property-based tests capturing observed behavior:**
    - **Test file**: Create `SpotdrawTests/PreservationPropertyTests.swift`
    - Property: For all tool-switch keys in {p, a, r, o, l, h, e}, pressing key sets `activeTool` to the corresponding tool (from Preservation Requirements: tool-switching keys continue to work)
    - Property: For all drawing sessions (random points with any tool), mouse down/drag/up produces a correctly-typed drawing item with matching properties (from Preservation Requirements: drawing tools continue to capture and produce)
    - Property: For all sequences of draw + Cmd+Z, undo removes the last item; Cmd+Shift+Z re-adds it (from Preservation Requirements: undo/redo unchanged)
    - Property: For all modifier key combinations that are NOT Ctrl+D, the overlay does NOT deactivate (from Preservation: no false-positive deactivation triggers)
    - Property: Board mode toggle cycles correctly for any starting mode
    - Property: Fade mode toggle flips boolean state
  - **Step 3 - Run tests on UNFIXED code:**
  - **EXPECTED OUTCOME**: Tests PASS (confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6_

- [ ] 3. Fix for overlay trapping user with no deactivation mechanism

  - [ ] 3.1 Create AccessibilityManager.swift
    - Create new file `Spotdraw/Core/AccessibilityManager.swift`
    - Implement static `checkPermission() -> Bool` using `AXIsProcessTrusted()`
    - Implement static `requestPermission()` using `AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt: true`
    - Expose permission status for AppDelegate to use at launch
    - _Bug_Condition: isBugCondition(input) where NOT accessibilityPermissionGranted() AND activation attempted_
    - _Expected_Behavior: System SHALL check accessibility permission and prompt user if not granted_
    - _Preservation: No existing behavior affected — this is a new module_
    - _Requirements: 2.1, 2.6_

  - [ ] 3.2 Modify HotkeyManager.swift — Gate global monitor on accessibility permission
    - In `setupMonitors()`, check `AXIsProcessTrusted()` before calling `NSEvent.addGlobalMonitorForEvents`
    - If permission not granted, skip global monitor registration and log a warning
    - Local monitor remains unconditional (works within the app regardless)
    - _Bug_Condition: isBugCondition(input) where globalMonitorCannotFire() due to missing permission_
    - _Expected_Behavior: Global monitor only registered when permission is confirmed_
    - _Preservation: Local monitor behavior unchanged; handler dispatch unchanged_
    - _Requirements: 2.1_

  - [ ] 3.3 Modify OverlayWindowController.swift — Lower window level and gate activation
    - Change `window.level = .screenSaver` to `window.level = .floating` in `createOverlayWindow(for:)`
    - Add guard in `activate()` that checks `AccessibilityManager.checkPermission()` and returns early with user notification if denied
    - Verify `.floating` level allows menu bar and Dock to remain accessible
    - _Bug_Condition: isBugCondition(input) where windowLevelBlocksAccess() OR NOT accessibilityPermissionGranted()_
    - _Expected_Behavior: Window level allows menu bar/Dock access; activation blocked without permission_
    - _Preservation: Window creation, deactivation flow, screen rebuild logic unchanged_
    - _Requirements: 2.2, 2.5, 2.6_

  - [ ] 3.4 Modify OverlayView.swift — Add deactivation callback and key handling
    - Add `var onDeactivate: (() -> Void)?` property
    - In `keyDown(with:)`, add case for Escape (`"\u{1B}"`) to call `onDeactivate?()` instead of just `clearAll()`
    - In `keyDown(with:)`, add case for Ctrl+D (detect `event.modifierFlags.contains(.control)` and `characters == "d"`) to call `onDeactivate?()`
    - Preserve ALL existing key handlers: tool switching (p, a, r, o, l, h, e), undo/redo (Cmd+Z, Cmd+Shift+Z), board toggle (b), fade toggle (space)
    - Ensure Ctrl+D case is checked before the default case to prevent the event from being swallowed
    - _Bug_Condition: isBugCondition(input) where input.keyCode == Ctrl+D AND globalMonitorCannotFire() OR input.keyCode == Escape AND escapeOnlyClearsDrawings()_
    - _Expected_Behavior: Ctrl+D and Escape both trigger overlay deactivation via callback_
    - _Preservation: All other key handlers remain exactly as they are_
    - _Requirements: 2.3, 2.4_

  - [ ] 3.5 Modify AppDelegate.swift — Wire accessibility check and deactivation callback
    - In `applicationDidFinishLaunching`, call `AccessibilityManager.requestPermission()` and show alert if denied
    - In `setupOverlay()` or after overlay creation, wire `overlayView.onDeactivate = { [weak self] in self?.toggleAnnotation() }` for each overlay window's content view
    - In `toggleAnnotation()`, add guard checking `AccessibilityManager.checkPermission()` before activating
    - _Bug_Condition: isBugCondition(input) where activation attempted without permission_
    - _Expected_Behavior: Permission checked at launch; deactivation callback properly wired; activation guarded_
    - _Preservation: Menu bar controller setup, cursor manager, other hotkey registrations unchanged_
    - _Requirements: 2.1, 2.3, 2.4, 2.6_

  - [ ] 3.6 Verify bug condition exploration test now passes
    - **Property 1: Expected Behavior** - Overlay Deactivation Always Works
    - **IMPORTANT**: Re-run the SAME test from task 1 - do NOT write a new test
    - The test from task 1 encodes the expected behavior
    - When this test passes, it confirms the expected behavior is satisfied:
      - Ctrl+D while overlay active → overlay deactivates
      - Escape while overlay active → overlay deactivates
      - Window level is `.floating` (not `.screenSaver`)
      - Activation without accessibility permission is blocked
    - Run bug condition exploration test from step 1
    - **EXPECTED OUTCOME**: Test PASSES (confirms bug is fixed)
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6_

  - [ ] 3.7 Verify preservation tests still pass
    - **Property 2: Preservation** - Drawing and Feature Functionality Unchanged
    - **IMPORTANT**: Re-run the SAME tests from task 2 - do NOT write new tests
    - Run preservation property tests from step 2
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - Confirm all tool-switching, drawing, undo/redo, board/fade toggle, and modifier-key behaviors unchanged
    - Confirm Ctrl+S and Ctrl+L still toggle cursor highlight and spotlight independently
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6_

- [ ] 4. Checkpoint - Ensure all tests pass
  - Run full test suite to confirm all exploration and preservation tests pass
  - Verify no compiler warnings or errors introduced
  - Confirm overlay can be activated and deactivated via Ctrl+D
  - Confirm Escape deactivates overlay
  - Confirm menu bar and Dock remain accessible while overlay is active
  - Confirm drawing, tool switching, undo/redo all work correctly
  - Ensure all tests pass, ask the user if questions arise


## Notes

- Bug condition methodology: Task 1 (exploration) and Task 2 (preservation) tests are written BEFORE the fix. Task 1 should FAIL on unfixed code (proving the bug exists), Task 2 should PASS on unfixed code (capturing baseline behavior to preserve).
- After implementing the fix in Task 3, re-run both test suites to confirm the bug is fixed and no regressions were introduced.
- Accessibility permission (AXIsProcessTrusted) is required for global event monitors on macOS. Without it, Ctrl+D cannot be detected outside the app's own windows.
- Window level `.floating` (NSWindow.Level 3) keeps the overlay above normal windows but below the menu bar and system UI, unlike `.screenSaver` (NSWindow.Level 1000) which blocks everything.
