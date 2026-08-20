# Spotdraw

**Draw on your screen. Highlight your cursor. Spotlight what matters. Zoom into details.** One native macOS app replaces the paid tools presenters have been buying for years.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-13.0+-blue.svg)](https://www.apple.com/macos/)
[![Built with Kiro](https://img.shields.io/badge/Built%20with-Kiro-blueviolet.svg)](https://kiro.dev/)

## Why it exists

Commercial screen annotation tools charge annual fees, lock you into closed ecosystems, and still only cover part of what presenters need. Open-source alternatives are fragmented: one tool draws, another highlights the cursor, none do everything.

**Spotdraw does.** Four features in a single 450KB native binary:

- **Annotation.** Pen, arrow, rectangle, circle, line, highlighter, eraser, text. Select, move, delete, undo.
- **Cursor highlight.** Colored halo with click animations. Configurable shape, size, glow.
- **Spotlight.** Dim everything except where your cursor points.
- **Zoom.** Magnify content under your cursor in a floating bubble.

## What's new in this release

- Text annotations (create, edit, drag)
- Select, move, and delete with marquee and shift-click
- Fully customizable shortcuts (Settings > Shortcuts tab)
- Floating toolbar panel with dynamic sections per active feature
- Passthrough and Interactive Mode (click through annotations)
- Standard macOS menus (Edit/View/Window/Help)
- Copy selected annotations as PNG to pasteboard
- Right-click contextual menus
- State restoration across relaunches
- Tooltips on all toolbar controls
- VoiceOver accessibility labels
- 78 automated tests passing

## Build and run

**Requirements:** macOS 13.0+, Swift 5.9+ (Xcode 15+ Command Line Tools)

```bash
git clone https://github.com/asub927/spotdraw.git
cd spotdraw
swift build --target Spotdraw
swift run Spotdraw
```

Grant Accessibility permission when prompted. The app appears as a pencil icon in the menu bar.

## Run tests

```bash
swift run SpotdrawTests
```

78 tests: 13 preservation, 26 property-based, 39 unit/regression. All run headlessly from the command line.

## Default shortcuts

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

All shortcuts are rebindable in Settings > Shortcuts.

## Testing instructions for judges

1. Clone and run `swift run Spotdraw`
2. Grant Accessibility permission (System Settings > Privacy & Security > Accessibility)
3. Press `Ctrl+D` to activate. Draw with the mouse. Try tool keys (P/A/R/O/L/H/E/T/S)
4. Press `T`, click, type text, press Return
5. Press `S`, click items, shift-click, drag marquee, Delete to remove, Cmd+Z to undo
6. Press `Ctrl+S` for cursor highlight, `Ctrl+L` for spotlight
7. Toggle features and watch the toolbar panel sections appear/disappear
8. Open Settings > Shortcuts tab to rebind keys
9. Hold Right Option while annotating for passthrough
10. Run `swift run SpotdrawTests` to verify 78/78 passing

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

**Key decisions:**
- Zero third-party dependencies. Pure Apple frameworks (AppKit, SwiftUI, Core Graphics).
- Operation-stack undo model supporting add, remove, move, and edit operations.
- Translation via additive offset. Immutable geometry preserved.
- Non-activating NSPanel for the toolbar. Does not steal keyboard focus.
- CGEvent tap for global shortcuts with ShortcutStore resolution.
- Property-based testing validates invariants across random operation sequences.

## How Kiro was used

Every feature followed the Kiro spec-driven workflow:

```
Requirements > Design > Tasks > Implementation > Verification
```

**The specs are in `.kiro/specs/` in this repository.**

| Spec | Coverage |
|------|----------|
| `annotation-parity-phase-1` | Text, select/move/delete, zoom, shortcuts, passthrough (14 task groups, 78 tests) |
| `panel-redesign` | Floating toolbar panel |
| `shortcut-details` | Shortcut indicators on menu items |
| `swift-redesign` | Mac-native design principles review |
| `annotation-parity-phase-2` | Next phase planning |
| `spotdraw-shortcut-freeze-fix` | Bugfix for overlay deactivation |
| `cursor-highlight-enhancements` | Cursor highlight improvements |
| `swift-code-review` | Code quality pass |

**What Kiro enabled:**
- 13 verification checkpoints. Each task group gated by test passage.
- 26 property tests written by Kiro validating invariants like "selection never contains a stale identifier" and "operation-stack invertibility."
- 5,700+ lines of production code in a single session. All tests passing.

## Mac-native design principles

Spotdraw follows the [Mac-Arsed Mac App](https://github.com/bartreardon/skills/tree/main/mac-arsed-mac-app) principles:

- Standard Edit/View/Window/Help menus with command routing
- Copy/paste annotations as images
- Right-click contextual menus everywhere
- State restoration (last tool, color, toolbar position, active features)
- Tooltips on all toolbar controls
- VoiceOver accessibility labels on all buttons
- Every action reachable without a mouse

## Requirements

- **macOS 13.0** (Ventura) or later
- **Accessibility permission** for global keyboard shortcuts
- **Screen Recording permission** for Zoom feature (optional)

## License

MIT. See [LICENSE](LICENSE).

## Built for the Ready, Spec, Ship Hackathon

Built with [Kiro](https://kiro.dev/) for the [Ready, Spec, Ship Hackathon](https://codingagents.fyi/hackathon/kiro/) hosted by [Coding Agents](https://codingagents.fyi).
