# Spotdraw

A native macOS screen annotation & presentation tool. Draw on screen, place text labels, select and move annotations, highlight your cursor, spotlight areas, and zoom into details — all from a lightweight menu bar app with a floating toolbar panel.

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

Spotdraw provides everything you need for presentations and screen sharing in one native app:

| Feature | Spotdraw | Presentify | Annotate |
|---------|:---:|:---:|:---:|
| Freehand drawing | ✅ | ✅ | ✅ |
| Shapes (arrow, rect, circle, line) | ✅ | ✅ | ✅ |
| Text annotations | ✅ | ✅ | ❌ |
| Select / move / delete | ✅ | ✅ | ❌ |
| Highlighter | ✅ | ✅ | ✅ |
| Eraser | ✅ | ✅ | ✅ |
| Auto-fade annotations | ✅ | ✅ | ✅ |
| Whiteboard/blackboard | ✅ | ✅ | ✅ |
| Cursor highlight halo | ✅ | ✅ | ✅ |
| Click animations | ✅ | ✅ | ✅ |
| Spotlight (dim screen) | ✅ | ✅ | ❌ |
| Zoom (magnification) | ✅ | ✅ | ❌ |
| Customizable shortcuts | ✅ | ✅ | ❌ |
| Floating toolbar panel | ✅ | ✅ | ❌ |
| Passthrough / Interactive Mode | ✅ | ✅ | ❌ |
| Native macOS (Swift/AppKit) | ✅ | ✅ | ✅ |
| Open source | ✅ | ❌ | ✅ |
| Free | ✅ | ❌ ($6/yr) | ✅ |

## Features

### 🎨 Screen Annotation
Draw directly on top of any app. Freehand pen, arrows, rectangles, circles, lines, highlighter, and eraser — all with smooth Core Graphics rendering. Undo/redo, fade mode, and whiteboard backgrounds.

### ✏️ Text Annotations
Place text labels anywhere on screen. Click to create, double-click to edit, drag to reposition. Font size configurable in Settings.

### 🔲 Select / Move / Delete
Click to select individual items, shift-click to multi-select, drag a marquee to select by region. Move selections by dragging, delete with the Delete key. Full undo/redo support for all operations.

### 👆 Cursor Highlight
A customizable colored halo follows your cursor with ripple animations for clicks. Multiple shapes (circle, ring, square, crosshair), sizes, colors, and optional glow effect.

### 🔦 Spotlight
Dim the entire screen except the area around your cursor. Adjustable spotlight size and dim intensity.

### 🔍 Zoom
Magnify content under your cursor in a floating bubble. Adjustable zoom level (2x–4x) and bubble size. Requires Screen Recording permission.

### 🎛️ Floating Toolbar Panel
A unified dark floating panel appears at the top of the screen showing controls for all active features. Sections appear/disappear dynamically as you toggle features. Drag to reposition, dismiss with ×.

### ⌨️ Fully Customizable Shortcuts
Every action is rebindable through the Settings → Shortcuts tab. Record new bindings, clear them, or reset to defaults. Conflicts are detected and resolved interactively.

**Default shortcuts:**

| Shortcut | Action |
|----------|--------|
| `Ctrl+D` | Toggle annotation overlay |
| `Ctrl+S` | Toggle cursor highlight |
| `Ctrl+L` | Toggle spotlight |
| `Ctrl+M` | Toggle zoom |
| `Ctrl+Shift+S` | Cycle cursor size |
| `Ctrl+=` / `Ctrl+-` | Zoom in/out |
| `Ctrl+Shift+I` | Toggle Interactive Mode |
| `P/A/R/O/L/H/E/T/S` | Tools (Pen/Arrow/Rect/Circle/Line/Highlighter/Eraser/Text/Select) |
| `1/2/3/4/5` | Colors (Red/Blue/Green/Yellow/White) |
| `Cmd+Z` / `Cmd+Shift+Z` | Undo / Redo |
| `Cmd+Delete` | Clear all |
| `Cmd+A` | Select all |
| `Delete` | Delete selection |
| `B` | Cycle board mode |
| `Space` | Toggle fade mode |
| `Escape` | Deactivate overlay |

### 🔀 Passthrough & Interactive Mode
Hold Right Option to click through annotations to the app beneath while keeping annotations visible. Or enable Interactive Mode (Ctrl+Shift+I) to default to passthrough and hold the modifier only when you want to draw.

### ⚙️ Settings
Full settings window with tabs for General, Annotation, Cursor (including Zoom), Spotlight, and Shortcuts. All preferences persist across sessions.

## Build & Run

### Prerequisites
- macOS 13.0+ (Ventura or later)
- Swift 5.9+ (Xcode 15+ Command Line Tools)

### Build from Source

```bash
git clone https://github.com/asub927/spotdraw.git
cd spotdraw
swift build --target Spotdraw
```

### Run

```bash
swift run Spotdraw
```

The app appears as a pencil icon in the menu bar. Grant Accessibility permission when prompted (required for global keyboard shortcuts).

### Run Tests

```bash
swift build --target SpotdrawTests
swift run SpotdrawTests
```

The test suite includes 78 tests: 13 preservation property tests, 26 property-based tests (operation stack, transforms, text, selection, shortcuts, zoom, passthrough), and 39 unit/regression tests. All tests run headlessly via the command line — no Xcode required.

## Testing Instructions for Judges

1. Clone the repo and run `swift run Spotdraw`
2. Grant **Accessibility** permission (System Settings → Privacy & Security → Accessibility → add the Spotdraw binary)
3. Test annotation: Press `Ctrl+D` → draw with mouse → try tools P/A/R/O/L/H/E/T/S
4. Test text: Press `T`, click anywhere, type text, press Return
5. Test select: Press `S`, click items, shift-click, drag marquee, Delete to remove, Cmd+Z to undo
6. Test cursor highlight: `Ctrl+S` → move mouse → click to see ripple effects
7. Test spotlight: `Ctrl+L` → move mouse → see dimmed screen with spotlight
8. Test zoom: `Ctrl+M` → move mouse (requires Screen Recording permission — add binary via + button)
9. Test toolbar panel: Toggle features on/off and observe the panel sections appear/disappear
10. Test shortcuts: Open Settings → Shortcuts tab → record new bindings
11. Test passthrough: While annotating, hold Right Option → annotations stay visible but clicks go through
12. Run automated tests: `swift run SpotdrawTests` (expects 78/78 passing)

## Requirements

- **macOS 13.0** (Ventura) or later
- **Accessibility permission** — Required for global keyboard shortcuts
- **Screen Recording permission** — Required only for the Zoom feature (optional)

## Architecture

```
Spotdraw/
├── App/                 # AppDelegate, app lifecycle
├── Core/                # DrawingState, DrawingOperation, SelectionManager,
│                        # ShortcutStore, HotkeyManager, SettingsManager,
│                        # PassthroughModifier
├── Overlay/             # OverlayWindowController, OverlayView,
│                        # TextEditingController, TextAnnotation,
│                        # SelectionRenderer, ModeIndicatorView,
│                        # ToolbarPanelController
├── Cursor/              # CursorManager, CursorHighlightWindow
├── Spotlight/           # SpotlightWindow
├── Zoom/                # ZoomWindow
├── Settings/            # SettingsWindowController, ShortcutsSettingsTab
├── MenuBar/             # MenuBarController
└── Resources/           # Info.plist

SpotdrawTests/           # 78 automated tests (property-based + unit)
scripts/                 # link-test-sources.sh
.kiro/                   # Kiro specs, steering, and session history
```

**Key design decisions:**
- Zero third-party dependencies — pure Apple frameworks (AppKit, SwiftUI, Core Graphics)
- Operation-stack undo model (supports add, remove, move, edit operations)
- Translation via additive offset (immutable geometry preserved)
- Selection lives on shared DrawingState, not per-view
- Non-activating NSPanel for the toolbar (doesn't steal keyboard focus)
- CGEvent tap for global shortcuts with ShortcutStore resolution
- Property-based testing validates invariants across random operation sequences

## How Kiro Was Used

This project was built using [Kiro](https://kiro.dev/) with a spec-driven development workflow. Every major feature went through the full Kiro spec lifecycle:

### Spec-Driven Workflow

```
Requirements → Design → Implementation Tasks → Code → Verification
```

1. **Requirements** — Wrote detailed acceptance criteria for each feature
2. **Design** — Kiro helped produce design documents with type definitions, state machines, and implementation strategies
3. **Tasks** — Broke designs into ordered implementation tasks with dependency graphs
4. **Implementation** — Kiro implemented each task, following the design exactly
5. **Verification** — Property-based tests validated invariants at each checkpoint

### Specs in This Repository (`.kiro/specs/`)

| Spec | What It Covers |
|------|---------------|
| `annotation-parity-phase-1` | Text annotation, select/move/delete, zoom activation, customizable shortcuts, passthrough & interactive mode (14 task groups, 78 tests) |
| `panel-redesign` | Floating toolbar panel with dynamic sections |
| `shortcut-details` | Shortcut key indicators on all menu items |
| `annotation-parity-phase-2` | Next phase planning (multi-screen fix, multi-line text, ScreenCaptureKit) |
| `spotdraw-shortcut-freeze-fix` | Bugfix for overlay deactivation |
| `cursor-highlight-enhancements` | Cursor highlight improvements |
| `swift-code-review` | Code quality pass |

### What Kiro Enabled

- **13 checkpoints** — Each task group had a verification gate ensuring no regressions
- **26 property tests** — Kiro wrote property-based tests validating invariants like "selection never contains a stale identifier" and "operation-stack invertibility"
- **5,700+ lines of production code** in a single session, all passing tests
- **Zero manual debugging** of the spec-driven code — bugs only appeared in integration (UI rendering, system permissions)

The complete `.kiro/` directory is committed to this repository, showing the full spec history.

## Performance

| Metric | Value |
|--------|-------|
| Binary size | ~450 KB |
| Memory usage | < 50 MB |
| Drawing latency | < 16ms (60fps) |
| Dependencies | 0 (pure Apple frameworks) |

## License

MIT — see [LICENSE](LICENSE) for details.

## Built for the Ready, Spec, Ship Hackathon

This project was built using [Kiro](https://kiro.dev/) for the [Ready, Spec, Ship Hackathon](https://codingagents.fyi/hackathon/kiro/) hosted by [Coding Agents](https://codingagents.fyi).
