# Spec: Transparent Overlay Window System

## Requirements

1. The app must create a transparent, borderless NSWindow that covers the entire screen
2. The overlay must float above all other windows (including fullscreen apps where possible)
3. Mouse events must pass through the overlay when annotation mode is inactive
4. Mouse events must be captured by the overlay when annotation mode is active
5. A global keyboard shortcut must toggle annotation mode on/off
6. The overlay must support multiple monitors (one window per screen)
7. The overlay must not appear in screenshots/recordings of other apps when inactive

## Design

### OverlayWindow (NSWindow subclass)
- `level`: `.screenSaver` (above most windows)
- `styleMask`: `.borderless`
- `backgroundColor`: `.clear`
- `isOpaque`: false
- `hasShadow`: false
- `ignoresMouseEvents`: true (when inactive), false (when active)
- `collectionBehavior`: [.canJoinAllSpaces, .fullScreenAuxiliary]

### OverlayWindowController
- Manages one OverlayWindow per NSScreen
- Listens for screen configuration changes (NSApplication.didChangeScreenParametersNotification)
- Provides `activate()` / `deactivate()` methods

### OverlayView (NSView subclass)
- Custom drawing via `draw(_ dirtyRect:)` using CGContext
- Handles mouse events (mouseDown, mouseDragged, mouseUp)
- Handles keyboard events for tool switching
- Maintains the drawing state (current tool, strokes array)

### HotkeyManager
- Registers global keyboard shortcut (default: Ctrl+D) using NSEvent.addGlobalMonitorForEvents
- Toggles overlay active/inactive state
- Notifies via callback/delegate pattern

## Tasks

- [ ] Create OverlayWindow NSWindow subclass with correct configuration
- [ ] Create OverlayWindowController managing per-screen windows
- [ ] Create OverlayView NSView subclass with event handling stubs
- [ ] Implement HotkeyManager for global shortcut detection
- [ ] Wire toggle logic: hotkey → controller → window ignoresMouseEvents
- [ ] Handle screen configuration changes (add/remove monitors)
- [ ] Test: overlay appears over all windows when activated
- [ ] Test: clicks pass through when deactivated
