# Bugfix Requirements Document

## Introduction

When the user activates the SpotDraw annotation overlay via the Ctrl+D global shortcut, the screen becomes effectively frozen. The full-screen overlay window captures all mouse and keyboard input, other applications become inaccessible, and the global shortcut to toggle annotation off does not fire — leaving the user trapped with no way to deactivate the overlay other than force-quitting the app. The root cause is a combination of missing Accessibility permission validation, an overly aggressive window level, lack of mouse event passthrough for non-drawing areas, and no guaranteed escape mechanism when global hotkeys fail.

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN the user presses Ctrl+D to activate annotation AND Accessibility permission has not been granted THEN the system activates the overlay but global hotkey monitors silently fail to receive subsequent key events, leaving no way to deactivate the overlay via keyboard shortcut

1.2 WHEN the overlay is active THEN the system sets `ignoresMouseEvents = false` on a full-screen `.screenSaver`-level window, capturing ALL mouse events and making every other application completely inaccessible

1.3 WHEN the overlay is active AND the user presses Ctrl+D again to toggle annotation off THEN the global monitor does not fire because the local monitor in OverlayView consumes the key event first without forwarding it to the global hotkey handler

1.4 WHEN the overlay is active THEN there is no reliable escape mechanism — the only exit is pressing Escape (handled locally in OverlayView) which calls `clearAll()` but does NOT deactivate the overlay, so the user remains trapped

1.5 WHEN the overlay is active AND the user wants to interact with the menu bar or Dock THEN the system blocks all interaction because the `.screenSaver` window level renders above everything including the menu bar

### Expected Behavior (Correct)

2.1 WHEN the application launches THEN the system SHALL check for Accessibility permission and prompt the user to grant it if not already authorized, before registering global hotkey monitors

2.2 WHEN the overlay is active THEN the system SHALL use an appropriate window level (e.g., `.floating` or `.statusBar`) that allows the menu bar and Dock to remain accessible

2.3 WHEN the overlay is active AND the user presses the Ctrl+D shortcut THEN the system SHALL reliably deactivate the overlay regardless of whether the event is received via the global or local monitor

2.4 WHEN the overlay is active AND the user presses Escape THEN the system SHALL deactivate the overlay entirely (not just clear drawings), restoring normal desktop interaction

2.5 WHEN the overlay is active THEN the system SHALL provide a way to pass mouse events through to underlying applications for areas where the user is not actively drawing (or provide a clearly documented deactivation shortcut that always works)

2.6 WHEN Accessibility permission is not granted THEN the system SHALL NOT activate the overlay and SHALL inform the user that the permission is required for global shortcuts to function

### Unchanged Behavior (Regression Prevention)

3.1 WHEN the overlay is active AND the user draws with pen, highlighter, arrow, rectangle, circle, or line tools THEN the system SHALL CONTINUE TO capture mouse events for drawing on the overlay

3.2 WHEN the overlay is active AND the user presses tool-switching keys (p, a, r, o, l, h, e) THEN the system SHALL CONTINUE TO switch the active drawing tool

3.3 WHEN the overlay is active AND the user presses Cmd+Z or Cmd+Shift+Z THEN the system SHALL CONTINUE TO perform undo/redo of drawing actions

3.4 WHEN the overlay is deactivated THEN the system SHALL CONTINUE TO preserve drawn items on the overlay (visible but non-interactive) until explicitly cleared

3.5 WHEN the user presses Ctrl+S or Ctrl+L for cursor highlight or spotlight THEN the system SHALL CONTINUE TO toggle those features independently of annotation mode

3.6 WHEN the screen configuration changes (monitor added/removed) THEN the system SHALL CONTINUE TO rebuild overlay windows appropriately
