# Spotdraw

A native macOS screen annotation & presentation tool. Draw on screen, highlight your cursor, spotlight areas, and zoom into details — all from a lightweight menu bar app.

**Free & open-source alternative to [Presentify](https://presentifyapp.com/).**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-13.0+-blue.svg)](https://www.apple.com/macos/)
[![Built with Kiro](https://img.shields.io/badge/Built%20with-Kiro-blueviolet.svg)](https://kiro.dev/)

## The Problem

Presentify ($6/year) is the best macOS screen annotation tool for presentations, but it's closed-source and paid. The open-source alternatives are fragmented:
- **Annotate** handles drawing well but lacks spotlight, zoom, and advanced cursor effects
- **Mac Mouse Highlighter** only does cursor highlighting
- **Lekhini** is Electron-based (200MB+ RAM) and doesn't have cursor/spotlight features

**No single open-source tool combines all four pillars** — annotation, cursor highlight, spotlight, and zoom — in a native, lightweight package.

## The Solution

Spotdraw provides everything you need for presentations and screen sharing in one 440KB native app:

| Feature | Spotdraw | Presentify | Annotate | Mac Mouse Highlighter |
|---------|:---:|:---:|:---:|:---:|
| Freehand drawing | ✅ | ✅ | ✅ | ❌ |
| Shapes (arrow, rect, circle, line) | ✅ | ✅ | ✅ | ❌ |
| Highlighter | ✅ | ✅ | ✅ | ❌ |
| Eraser | ✅ | ✅ | ✅ | ❌ |
| Auto-fade annotations | ✅ | ✅ | ✅ | ❌ |
| Whiteboard/blackboard | ✅ | ✅ | ✅ | ❌ |
| Cursor highlight halo | ✅ | ✅ | ✅ | ✅ |
| Click animations | ✅ | ✅ | ✅ | ✅ |
| Spotlight (dim screen) | ✅ | ✅ | ❌ | Partial |
| Zoom (magnification) | ✅ | ✅ | ❌ | ❌ |
| Native macOS | ✅ | ✅ | ✅ | ✅ |
| Open source | ✅ | ❌ | ✅ | ✅ |
| App size | 440KB | ~1MB | Small | Small |
| Free | ✅ | ❌ ($6/yr) | ✅ | ✅ |

## Features

### 🎨 Screen Annotation
Draw directly on top of any app. Freehand pen, arrows, rectangles, circles, lines, highlighter, and eraser — all with smooth rendering via Core Graphics.

### 👆 Cursor Highlight
A customizable colored halo follows your cursor. Different ripple animations for left and right clicks help your audience see every action.

### 🔦 Spotlight
Dim the entire screen except the area around your cursor. Perfect for directing attention to specific UI elements during demos.

### 🔍 Zoom
Magnify the content under your cursor in a floating bubble. Shows fine details without changing your display settings.

### ⌨️ Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+D` | Toggle annotation overlay |
| `Ctrl+S` | Toggle cursor highlight |
| `Ctrl+L` | Toggle spotlight |
| `Ctrl+Z` | Toggle zoom |
| `P` | Pen tool |
| `A` | Arrow tool |
| `R` | Rectangle tool |
| `O` | Circle tool |
| `L` | Line tool |
| `H` | Highlighter |
| `E` | Eraser |
| `B` | Toggle whiteboard (none → white → black) |
| `Space` | Toggle fade mode |
| `Esc` | Clear all annotations |
| `Cmd+Z` | Undo |
| `Cmd+Shift+Z` | Redo |
| `Shift` (while drawing) | Constrain (square, circle, 45° angles) |

### ⚙️ Settings
SwiftUI settings panel with tabs for General, Annotation, Cursor, and Spotlight. All preferences persist across sessions.

## Installation

### Download (Recommended)

1. Download `Spotdraw-1.0.0.dmg` from [Releases](https://github.com/asub927/spotdraw/releases/tag/v1.0.0)
2. Open the DMG and drag Spotdraw to Applications
3. Right-click → Open (first launch only, since app is not notarized)
4. Grant Accessibility permission when prompted

### Homebrew

```bash
brew install --cask spotdraw
```

### Build from Source

```bash
git clone https://github.com/asub927/spotdraw.git
cd spotdraw
swift build -c release
./scripts/build-dmg.sh
```

Requires Swift 5.9+ (Xcode Command Line Tools or Xcode 15+).

## Requirements

- **macOS 13.0** (Ventura) or later
- **Accessibility permission** — Required for global keyboard shortcuts and mouse event monitoring
- **Screen Recording permission** — Required only for the Zoom feature

## Architecture

```
Spotdraw/
├── App/                 # App lifecycle, AppDelegate
├── Core/                # DrawingState, HotkeyManager, SettingsManager
├── Overlay/             # Transparent overlay windows + OverlayView
├── Cursor/              # CursorManager, CursorHighlightWindow
├── Spotlight/           # SpotlightWindow with dimming cutout
├── Zoom/                # ZoomWindow with screen capture
├── Settings/            # SwiftUI settings panel
├── MenuBar/             # NSStatusItem menu bar controller
└── Resources/           # Info.plist
```

**Key design decisions:**
- Each feature (annotation, cursor, spotlight, zoom) is an independent overlay window
- Zero third-party dependencies — pure Apple frameworks (AppKit, SwiftUI, Core Graphics, QuartzCore)
- Drawing uses CGContext for hardware-accelerated rendering
- Global event monitoring via `NSEvent.addGlobalMonitorForEvents`
- Settings persisted via `UserDefaults`

## How Kiro Was Used

This project was built using [Kiro](https://kiro.dev/) for spec-driven development:

### Steering Files (`.kiro/steering/`)
- **`project.md`** — Defines architecture, coding conventions, module structure, performance targets, and design decisions. Kiro uses this to maintain consistency across all generated code.

### Specs (`.kiro/specs/`)
- **`overlay-system.md`** — Requirements, design, and tasks for the transparent overlay window system
- **`annotation-tools.md`** — Complete spec for all drawing tools with protocol definitions and implementation plan
- **`cursor-spotlight.md`** — Spec for cursor highlight, click effects, and spotlight with system design

### Development Workflow
1. **Spec first** — Wrote requirements and design in `.kiro/specs/` before any implementation
2. **Steering for consistency** — The steering file ensured all code followed the same patterns
3. **Iterative implementation** — Used Kiro CLI to implement each spec's task list
4. **Verification** — Built and verified after each feature with `swift build`

The `.kiro/` directory is committed at the repo root as required.

## Performance

| Metric | Value |
|--------|-------|
| Binary size | 432 KB |
| App bundle size | 440 KB |
| DMG size | 140 KB |
| Memory usage target | < 50 MB |
| Drawing latency | < 16ms (60fps) |
| Cursor tracking | 60fps |

## Testing Instructions

1. Download and install from the DMG
2. Grant Accessibility permission (System Settings → Privacy & Security → Accessibility)
3. Click the pencil icon in the menu bar
4. Test annotation: `Ctrl+D` → draw with mouse → press tool keys (P/A/R/O/L/H/E)
5. Test cursor highlight: `Ctrl+S` → move mouse → click to see ripple effects
6. Test spotlight: `Ctrl+L` → move mouse → see dimmed screen with spotlight
7. Test zoom: `Ctrl+Z` → move mouse → see magnified content (requires Screen Recording permission)
8. Test whiteboard: While annotating, press `B` to cycle backgrounds
9. Test fade mode: Press `Space` to enable, then draw — annotations fade after 3 seconds
10. Test settings: Click menu bar → Settings...

## Tech Stack

- **Swift 5.9+** — Native macOS development
- **AppKit** — Overlay windows, event monitoring, menu bar
- **SwiftUI** — Settings panel
- **Core Graphics** — Hardware-accelerated drawing (CGContext, CGPath)
- **QuartzCore** — CALayer animations for cursor/click effects
- **CGWindowListCreateImage** — Screen capture for zoom feature

## License

MIT — see [LICENSE](LICENSE) for details.

## Built for the Ready, Spec, Ship Hackathon

This project was built using [Kiro](https://kiro.dev/) for the [Ready, Spec, Ship Hackathon](https://codingagents.fyi/hackathon/kiro/) hosted by [Coding Agents](https://codingagents.fyi).
