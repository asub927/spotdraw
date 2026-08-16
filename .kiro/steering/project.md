# Spotdraw — Project Steering

## Overview

Spotdraw is a native macOS menu bar app for screen annotation and presentation enhancement.
It provides four independent feature pillars: Screen Annotation, Cursor Highlight, Spotlight, and Zoom.

## Architecture

- **Language:** Swift 5.9+
- **Target:** macOS 13.0 (Ventura) and later
- **UI Framework:** AppKit for overlay windows; SwiftUI for Settings panel and toolbar
- **Drawing:** Core Graphics (CGContext, CGPath) for hardware-accelerated rendering
- **App Lifecycle:** NSApplicationDelegate-based, menu bar only (LSUIElement = true)
- **Build System:** Xcode project (not Swift Package Manager executable)

## Code Conventions

- Use Swift's structured concurrency (async/await) where appropriate
- Prefer value types (structs, enums) over reference types unless identity semantics are needed
- Use `@Observable` (Observation framework) for state management in SwiftUI views
- Use `@Published` / `ObservableObject` only when targeting older patterns
- Follow Swift API Design Guidelines for naming
- Use MARK comments to organize file sections: `// MARK: - Section Name`
- Maximum file length: ~400 lines. Extract into separate files when exceeding.
- One type per file, named to match the type

## Module Structure

```
Spotdraw/
├── App/                    # App lifecycle, AppDelegate, main entry
├── Core/                   # Shared models, protocols, utilities
├── Overlay/                # Transparent overlay window system
├── Annotation/             # Drawing tools (pen, shapes, highlighter, eraser)
├── Cursor/                 # Cursor highlight and click effects
├── Spotlight/              # Spotlight dimming system
├── Zoom/                   # Zoom magnification (stretch goal)
├── Settings/               # SwiftUI settings panel
├── MenuBar/                # Menu bar controller and toolbar
└── Resources/              # Assets, Info.plist
```

## Key Design Decisions

1. **Each feature is an independent overlay window** — Annotation, Cursor, Spotlight, and Zoom each have their own NSWindow. They can be toggled independently.
2. **Global event monitoring** — Use `NSEvent.addGlobalMonitorForEvents` for mouse/keyboard tracking outside our app.
3. **Local event monitoring** — Use `NSEvent.addLocalMonitorForEvents` for events when our overlay is key.
4. **Drawing model** — Strokes/shapes stored as an array of `DrawingItem` structs. Undo/redo is a stack of snapshots.
5. **Settings persistence** — `UserDefaults` with a `SettingsManager` singleton.
6. **No third-party dependencies** — Pure Apple frameworks only. Keeps the app lightweight and avoids supply chain risk.

## Performance Targets

- App size: < 5 MB
- Memory usage: < 50 MB
- Drawing latency: < 16ms (60fps)
- Cursor highlight: smooth 60fps tracking

## Permissions Required

- **Accessibility** (Input Monitoring): For global keyboard shortcuts and mouse event monitoring
- **Screen Recording**: Only for Zoom feature (stretch goal)
