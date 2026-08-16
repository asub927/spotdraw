# Spotdraw

A native macOS screen annotation & presentation tool. Draw on screen, highlight your cursor, spotlight areas, and zoom into details — all from a lightweight menu bar app.

**Free & open-source alternative to [Presentify](https://presentifyapp.com/).**

## Features

- 🎨 **Screen Annotation** — Freehand drawing, arrows, rectangles, circles, lines, highlighter, eraser
- 👆 **Cursor Highlight** — Customizable halo follows your cursor with click animations
- 🔦 **Spotlight** — Dim the screen except the area around your cursor
- 🔍 **Zoom** — Magnify content under your cursor (stretch goal)
- ⌨️ **Global Keyboard Shortcuts** — Toggle any feature instantly from anywhere
- 📋 **Whiteboard Mode** — Draw on an opaque background
- ⏱️ **Auto-Fade** — Annotations disappear after a set duration
- 🖥️ **Multi-Monitor** — Works across all your displays

## Installation

### Download

Download the latest `.dmg` from [Releases](https://github.com/asub927/spotdraw/releases).

### Homebrew

```bash
brew install --cask spotdraw
```

## Requirements

- macOS 13.0 (Ventura) or later
- Accessibility permission (for global keyboard/mouse monitoring)
- Screen Recording permission (for zoom feature only)

## Built With

- **Swift** + **AppKit** + **SwiftUI**
- **Core Graphics** for hardware-accelerated drawing
- **Kiro** for spec-driven development

## Built for the Ready, Spec, Ship Hackathon

This project was built using [Kiro](https://kiro.dev/) for the [Ready, Spec, Ship Hackathon](https://codingagents.fyi/hackathon/kiro/).

## License

MIT — see [LICENSE](LICENSE) for details.
