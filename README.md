# Spotdraw

Draw on your screen. Highlight your cursor. Spotlight what matters. Zoom into details. A native macOS screen annotation tool, open-source, zero dependencies, 450KB.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-13.0+-blue.svg)](https://www.apple.com/macos/)
[![Built with Kiro](https://img.shields.io/badge/Built%20with-Kiro-blueviolet.svg)](https://kiro.dev/)

## What it does

Four features in one binary:

- **Annotation.** Pen, arrow, rectangle, circle, line, highlighter, eraser, text. Select, move, delete, undo.
- **Cursor highlight.** Colored halo with click animations. Configurable shape, size, glow.
- **Spotlight.** Dims the screen except around your cursor.
- **Zoom.** Magnifies content under the cursor in a floating bubble.

Plus a floating toolbar panel that shows controls for whichever features are active, customizable keyboard shortcuts, passthrough mode for clicking through annotations, and state restoration across relaunches.

## Build and run

Requires macOS 13.0+ and Swift 5.9+ (Xcode 15 Command Line Tools).

```bash
git clone https://github.com/asub927/spotdraw.git
cd spotdraw
swift build --target Spotdraw
swift run Spotdraw
```

Grant Accessibility permission when prompted. The app appears as a pencil icon in the menu bar.

## Install

Download the latest release from [Releases](https://github.com/asub927/spotdraw/releases/tag/v1.0.0), or build from source above.

## Run tests

```bash
swift run SpotdrawTests
```

78 tests: 13 preservation, 26 property-based, 39 unit/regression. Runs headlessly from the command line.

## Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+D` | Toggle annotation overlay |
| `Ctrl+S` | Toggle cursor highlight |
| `Ctrl+L` | Toggle spotlight |
| `Ctrl+M` | Toggle zoom |
| `Ctrl+Shift+I` | Toggle Interactive Mode |
| `Ctrl+=` / `Ctrl+-` | Zoom in/out |
| `P/A/R/O/L/H/E/T/S` | Tools |
| `1/2/3/4/5` | Colors |
| `Cmd+Z` / `Cmd+Shift+Z` | Undo / Redo |
| `Cmd+Delete` | Clear all |
| `Cmd+A` | Select all |
| `Delete` | Delete selection |
| `B` | Cycle board mode |
| `Space` | Toggle fade mode |
| `Escape` | Deactivate overlay |

All rebindable in Settings > Shortcuts.

## Testing instructions for judges

1. Clone and run `swift run Spotdraw`
2. Grant Accessibility permission (System Settings > Privacy & Security > Accessibility)
3. `Ctrl+D` to activate. Draw with the mouse. Try tool keys (P/A/R/O/L/H/E/T/S)
4. `T`, click, type text, press Return
5. `S`, click items, shift-click, drag marquee, Delete to remove, Cmd+Z to undo
6. `Ctrl+S` for cursor highlight, `Ctrl+L` for spotlight
7. Toggle features and watch the toolbar panel sections appear/disappear
8. Open Settings > Shortcuts tab to rebind keys
9. Hold Right Option while annotating for passthrough
10. `swift run SpotdrawTests` to verify 78/78 passing

## Architecture

```
Spotdraw/
├── App/           AppDelegate, app lifecycle
├── Core/          DrawingState, SelectionManager, ShortcutStore,
│                  HotkeyManager, SettingsManager, PassthroughModifier
├── Overlay/       OverlayWindowController, OverlayView,
│                  TextEditingController, TextAnnotation,
│                  SelectionRenderer, ToolbarPanelController
├── Cursor/        CursorManager, CursorHighlightWindow
├── Spotlight/     SpotlightWindow
├── Zoom/          ZoomWindow
├── Settings/      SettingsWindowController, ShortcutsSettingsTab
├── MenuBar/       MenuBarController
└── Resources/     Info.plist
```

Zero third-party dependencies. Pure AppKit, SwiftUI, and Core Graphics.

Operation-stack undo model supports add, remove, move, and edit. Translation uses an additive offset so immutable geometry stays untouched. The toolbar is a non-activating NSPanel that never steals keyboard focus. Global shortcuts use a CGEvent tap resolved through ShortcutStore. Property-based tests validate invariants across random operation sequences.

## How Kiro was used

The `.kiro/specs/` directory in this repository contains the full spec-driven workflow. Each feature started as a requirements document, became a design, broke into ordered tasks, and was implemented with verification checkpoints.

| Spec | What it covers |
|------|----------------|
| `annotation-parity-phase-1` | Text, select/move/delete, zoom, shortcuts, passthrough. 14 task groups, 78 tests. |
| `panel-redesign` | Floating toolbar panel with dynamic sections |
| `shortcut-details` | Shortcut indicators on menu items |
| `swift-redesign` | Mac-native design review against Mac-Arsed Mac App principles |
| `spotdraw-shortcut-freeze-fix` | Bugfix for overlay deactivation |
| `cursor-highlight-enhancements` | Cursor highlight improvements |
| `swift-code-review` | Code quality pass |

Kiro wrote 26 property tests that validate invariants like "selection never contains a stale identifier" and "operation-stack invertibility." It produced 5,700+ lines of production code across one session with 13 verification checkpoints gating each task group.

## Mac-native design

Follows the [Mac-Arsed Mac App](https://github.com/bartreardon/skills/tree/main/mac-arsed-mac-app) principles:

- Standard Edit/View/Window/Help menus with command routing
- Copy/paste annotations as PNG images
- Right-click contextual menus
- State restoration (tool, color, toolbar position, active features)
- Tooltips on toolbar controls
- VoiceOver accessibility labels
- Every action reachable without a mouse

## License

MIT. See [LICENSE](LICENSE).

## Hackathon

Built with [Kiro](https://kiro.dev/) for the [Ready, Spec, Ship Hackathon](https://codingagents.fyi/hackathon/kiro/) by [Coding Agents](https://codingagents.fyi).
