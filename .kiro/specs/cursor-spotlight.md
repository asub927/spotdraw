# Spec: Cursor Highlight & Spotlight

## Requirements

### Cursor Highlight
1. A colored halo/ring follows the mouse cursor at all times (when enabled)
2. Works independently of annotation mode — runs globally across all apps
3. Customizable: color, size (20-100px), opacity, shape (circle, ring, squircle)
4. Click animation: expanding ripple on left/right click with different colors
5. "Highlight only on click" mode — halo hidden until a click occurs
6. Toggle via global shortcut (default: Ctrl+S)
7. Smooth 60fps tracking with no perceptible lag

### Spotlight
1. Dims the entire screen except a region around the cursor
2. Spotlight region follows cursor in real-time
3. Customizable: size, shape (circle, rectangle, squircle), dim intensity (0-95%)
4. Adjustable size while active via shortcuts (Ctrl+- / Ctrl+=)
5. Toggle via global shortcut (default: Ctrl+L)
6. Smooth animation, no flickering

## Design

### CursorHighlightWindow
- Separate NSWindow per screen, always on top, always ignores mouse events
- Uses CALayer for the highlight shape (better animation performance)
- Updates position on every mouseMoved event via global monitor
- Click effects use CABasicAnimation for ripple expansion + fade

### SpotlightWindow
- Fullscreen NSWindow per screen with semi-transparent black fill
- Uses CGPath with even-odd fill rule to create transparent cutout
- The cutout shape (circle/rect) is centered on cursor position
- CAShapeLayer for the mask — animate path changes for smooth movement
- Dim intensity controlled by the background alpha

### CursorManager
- Owns both CursorHighlightWindow and SpotlightWindow
- Manages global mouse event monitor (shared for efficiency)
- Dispatches position updates to both systems
- Handles toggle state for each independently

## Tasks

- [ ] Create CursorHighlightWindow with CALayer-based rendering
- [ ] Implement circle/ring/squircle shape rendering
- [ ] Add global mouse position tracking via NSEvent monitor
- [ ] Implement smooth position updates at display refresh rate
- [ ] Add click detection and ripple animation (left=blue, right=red)
- [ ] Add "highlight only on click" mode
- [ ] Create SpotlightWindow with even-odd fill cutout
- [ ] Implement spotlight size adjustment shortcuts
- [ ] Create CursorManager coordinating both windows
- [ ] Wire to global toggle shortcuts (Ctrl+S, Ctrl+L)
- [ ] Add customization options (color, size, shape, intensity)
- [ ] Test: 60fps tracking with no dropped frames
