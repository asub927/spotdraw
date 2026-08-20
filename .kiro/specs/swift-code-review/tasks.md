# Implementation Plan: Swift Code Review Refactoring

## Overview

This plan implements a 5-phase refactoring of the SpotDraw macOS annotation application to align with Swift best practices, modern syntax (5.7+), and Swift 6 concurrency preparation. Phases are ordered by increasing risk: documentation/annotations first, structural changes last. Each phase produces a compilable, testable state with zero behavioral regression.

## Tasks

- [ ] 1. Phase 1: Documentation & Access Control
  - [ ] 1.1 Add `final` keyword to all 16 classes and explicit `internal` access control to all type declarations
    - Add `final` to: FreehandStroke, ArrowShape, RectangleShape, CircleShape, LineShape, CursorHighlightWindow, SpotlightWindow, ZoomWindow, CursorManager, MenuBarController, OverlayWindowController, OverlayView, SettingsWindowController, HotkeyManager, SettingsManager, AppDelegate
    - Add explicit `internal` keyword to all type declarations
    - _Requirements: 1.1, 1.4, 3.4_

  - [ ] 1.2 Add `private` access control to internal stored properties
    - OverlayView: `currentPoints`, `shapeStartPoint`, `currentShapeEndPoint`, `isDrawing`, `isShiftHeld`, `fadeTimer` → `private`
    - OverlayView: `drawingState` → `private(set)`
    - CursorHighlightWindow: `window`, `highlightLayer` → `private`
    - SpotlightWindow: `window`, `spotlightView` → `private`
    - OverlayWindowController: `overlayWindows`, `drawingState`, `screenObserver` → `private`
    - HotkeyManager: `handlers`, `globalMonitor`, `localMonitor` → `private`
    - _Requirements: 1.2, 1.3, 1.5_

  - [ ] 1.3 Add file-level documentation comments to all Swift source files
    - Add `///` file-level comment at top of each `.swift` file describing purpose and architectural role
    - Cover all ~12 source files: AppDelegate, DrawingState, OverlayView, OverlayWindowController, CursorManager, CursorHighlightWindow, SpotlightWindow, ZoomWindow, MenuBarController, SettingsWindowController, SettingsManager, HotkeyManager
    - _Requirements: 9.2_

  - [ ] 1.4 Add protocol and API documentation comments
    - Add `///` documentation to DrawingItem protocol and all its required properties/methods
    - Add documentation to all public/internal API methods: toggle methods in CursorManager, lifecycle methods in OverlayWindowController, registration methods in HotkeyManager
    - Add design-decision comment on DrawingState being a reference type (shared state across OverlayView instances)
    - _Requirements: 9.1, 9.3, 9.4_

  - [ ] 1.5 Add inline algorithm documentation comments
    - Document point smoothing algorithm in OverlayView
    - Document hit-test geometry in DrawingItem conformances (ArrowShape, LineShape)
    - Document screen coordinate conversion in ZoomWindow
    - _Requirements: 9.5_

- [ ] 2. Phase 1 Checkpoint
  - Run `swift build --package-path /Users/aaranvi/dev/spotdraw` and existing test suite
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 3. Phase 2: Modern Syntax & Enum Enhancements
  - [ ] 3.1 Add `CaseIterable`, `Hashable` conformance to ToolType and add `keyCharacter` computed property
    - Add `CaseIterable, Hashable` protocol conformance
    - Add `keyCharacter: String` computed property mapping each tool to its shortcut character (p, a, r, o, l, h, e)
    - Replace duplicated character-to-tool mapping in OverlayView.keyDown(with:) to use `ToolType.allCases.first { $0.keyCharacter == ... }`
    - _Requirements: 2.3, 2.4, 3.2_

  - [ ] 3.2 Add `BoardMode.next` computed property and eliminate duplicate cycling logic
    - Add `next: BoardMode` computed property implementing none → white → black → none, custom → none
    - Replace duplicate switch statements in OverlayView.toggleBoard() and OverlayWindowController.toggleBoard() with `drawingState.boardMode = drawingState.boardMode.next`
    - _Requirements: 3.1_

  - [ ] 3.3 Eliminate force unwraps in FreehandStroke and OverlayView
    - Replace `points.last!` in FreehandStroke.draw(in:) with `guard let lastPoint = points.last else { return }`
    - Replace `points.last!` in smoothPoints helper with safe `if let` binding
    - _Requirements: 2.2_

  - [ ] 3.4 Use Swift 5.9 switch expressions in GlobalShortcut
    - Convert `keyCode` and `modifiers` computed properties from `switch ... return` to switch expressions
    - _Requirements: 2.5_

  - [ ] 3.5 Add protocol extension for shared line-segment hitTest and use `any DrawingItem` consistently
    - Add `lineSegmentHitTest(point:start:end:threshold:)` as a DrawingItem protocol extension
    - Delegate hitTest in ArrowShape and LineShape to this shared implementation
    - Verify `any DrawingItem` syntax is used consistently in all collections and parameters
    - _Requirements: 3.3, 3.5_

- [ ] 4. Phase 2 Checkpoint
  - Run `swift build --package-path /Users/aaranvi/dev/spotdraw` and existing test suite
  - Verify BoardMode.next produces same cycling behavior as existing switch statements
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 5. Phase 3: File Restructuring & Memory Management
  - [ ] 5.1 Create DrawingItems.swift and extract shape classes from DrawingState.swift
    - Create `Spotdraw/Core/DrawingItems.swift`
    - Move FreehandStroke, ArrowShape, RectangleShape, CircleShape, LineShape into new file
    - Leave DrawingState.swift containing: DrawingItem protocol, ToolType enum, BoardMode enum, DrawingState class
    - _Requirements: 4.1_

  - [ ] 5.2 Create GeometryUtils.swift with caseless enum namespace
    - Create `Spotdraw/Core/GeometryUtils.swift`
    - Move `distanceFromPointToLine` into `GeometryUtils.distance(from:toLineSegmentFrom:to:)` static method
    - Move the DrawingItem protocol extension for lineSegmentHitTest here
    - _Requirements: 4.2, 7.1_

  - [ ] 5.3 Create DrawingRenderer.swift and extract rendering methods from OverlayView
    - Create `Spotdraw/Overlay/DrawingRenderer.swift`
    - Extract: drawCurrentStroke, drawCurrentArrow, drawCurrentRect, drawCurrentCircle, drawCurrentLine, drawArrowhead, smoothPoints, constrainToAngles, rectFrom
    - OverlayView retains event handling, view lifecycle, and fade timer management
    - _Requirements: 4.3_

  - [ ] 5.4 Add type aliases in HotkeyManager and CursorManager
    - Add `private typealias ShortcutHandler = () -> Void` in HotkeyManager
    - Add `private typealias EventMonitorToken = Any` in HotkeyManager and CursorManager
    - _Requirements: 4.4, 5.3_

  - [ ] 5.5 Add memory management improvements
    - Add `viewDidMoveToWindow()` override in OverlayView to invalidate fadeTimer when window becomes nil and restart when reattached
    - Add window cleanup in OverlayWindowController `deinit` (close overlay windows, remove observer)
    - Verify CursorManager.deinit removes mouse monitor; add cleanup for SpotlightWindow, CursorHighlightWindow, ZoomWindow if needed
    - _Requirements: 5.1, 5.2, 5.4, 5.5_

  - [ ] 5.6 Apply consistent MARK structure to all files
    - Ensure all files use: `// MARK: - Properties`, `// MARK: - Init`, `// MARK: - Setup`, `// MARK: - Public API`, `// MARK: - Private Methods`, `// MARK: - Cleanup`
    - Focus on SpotlightView and ZoomWindow which currently lack consistent MARK organization
    - _Requirements: 4.5_

- [ ] 6. Phase 3 Checkpoint
  - Run `swift build --package-path /Users/aaranvi/dev/spotdraw` and existing test suite
  - This is the highest-risk phase — verify no compilation errors from file moves
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 7. Phase 4: Concurrency Annotations
  - [ ] 7.1 Add `@MainActor` annotation to all UI classes
    - Annotate: AppDelegate, OverlayWindowController, OverlayView, CursorManager, CursorHighlightWindow, SpotlightWindow, ZoomWindow, MenuBarController, SettingsWindowController, HotkeyManager
    - _Requirements: 8.1_

  - [ ] 7.2 Add `@MainActor` to SettingsManager with `nonisolated(unsafe)` static property
    - Add `@MainActor` to SettingsManager class
    - Add `nonisolated(unsafe)` to `static let shared` property
    - _Requirements: 8.2, 8.5_

  - [ ] 7.3 Add `Sendable` conformance to ToolType and BoardMode enums
    - Add `Sendable` to ToolType enum declaration
    - Add `extension BoardMode: @unchecked Sendable {}` (needed because NSColor is not Sendable)
    - _Requirements: 8.4_

  - [ ] 7.4 Verify Timer and NSEvent monitor callbacks are main-actor safe
    - Confirm Timer.scheduledTimer callbacks execute on main run loop
    - Confirm NSEvent.addGlobalMonitorForEvents dispatches to main thread
    - Document that @MainActor class annotations ensure compiler verification at Swift 6 level
    - _Requirements: 8.3_

- [ ] 8. Phase 4 Checkpoint
  - Run `swift build --package-path /Users/aaranvi/dev/spotdraw` and existing test suite
  - Verify no new warnings introduced by concurrency annotations (expected in language mode v5)
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 9. Phase 5: SwiftUI & API Naming
  - [ ] 9.1 Create `onChangeCompat` view extension for cross-version `.onChange` support
    - Create a View extension with `@ViewBuilder` that uses `#available(macOS 14.0, *)` to conditionally call the modern two-parameter `.onChange` or the legacy single-parameter form
    - _Requirements: 6.1_

  - [ ] 9.2 Migrate all `.onChange` calls to use `onChangeCompat` wrapper
    - Update GeneralSettingsTab, AnnotationSettingsTab, CursorSettingsTab, SpotlightSettingsTab
    - Replace all `.onChange(of:) { newValue in }` with `.onChangeCompat(of:) { newValue in }`
    - _Requirements: 6.1_

  - [ ] 9.3 Extract shared ColorPresets enum and add slider documentation
    - Create `ColorPresets` caseless enum with `annotation` and `cursor` static arrays
    - Replace duplicated color arrays in AnnotationSettingsTab and CursorSettingsTab
    - Add inline documentation comments for all magic number slider ranges explaining rationale
    - Document `@State` initialization pattern (snapshot from SettingsManager.shared)
    - _Requirements: 6.2, 6.3, 6.4_

  - [ ] 9.4 Rename `createOverlayWindow(for:)` to `makeOverlayWindow(for:)` in OverlayWindowController
    - Rename method and update all call sites
    - _Requirements: 7.5_

  - [ ] 9.5 Rename `handleMouseEvent(_:)` to `routeMouseEvent(_:)` in CursorManager
    - Rename method and update all call sites
    - _Requirements: 7.3_

  - [ ] 9.6 Use Swift 5.9 switch expressions in GlobalShortcut (if not already done in Phase 2)
    - Verify `keyCode` and `modifiers` use switch expressions; apply if missed
    - Confirm `some View` return type consistency and no unnecessary type erasure in SwiftUI views
    - _Requirements: 6.5, 7.4_

- [ ] 10. Final Checkpoint
  - Run `swift build --package-path /Users/aaranvi/dev/spotdraw` and full test suite
  - Verify no deprecation warnings remain for macOS 14+ builds
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- This is a pure refactoring — zero user-facing behavioral changes expected
- The project uses swift-tools-version 6.0 with `.swiftLanguageMode(.v5)` and targets macOS 13+
- `@MainActor` annotations are additive in language mode v5 (no warnings/errors until v6 migration)
- The `onChangeCompat` wrapper maintains macOS 13 backward compatibility while eliminating deprecation warnings on macOS 14+
- `BoardMode` uses `@unchecked Sendable` because `NSColor` is not Sendable, but the enum is only used on the main thread
- Existing property-based tests in `PreservationPropertyTests.swift` serve as regression guard throughout all phases
- Build command: `swift build --package-path /Users/aaranvi/dev/spotdraw`
- Test command: `swift build --target SpotdrawTests --package-path /Users/aaranvi/dev/spotdraw && .build/debug/SpotdrawTests`

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.3"] },
    { "id": 1, "tasks": ["1.2", "1.4", "1.5"] },
    { "id": 2, "tasks": ["3.1", "3.2", "3.3", "3.4"] },
    { "id": 3, "tasks": ["3.5"] },
    { "id": 4, "tasks": ["5.1", "5.4"] },
    { "id": 5, "tasks": ["5.2", "5.3", "5.5", "5.6"] },
    { "id": 6, "tasks": ["7.1", "7.3"] },
    { "id": 7, "tasks": ["7.2", "7.4"] },
    { "id": 8, "tasks": ["9.1", "9.3"] },
    { "id": 9, "tasks": ["9.2", "9.4", "9.5", "9.6"] }
  ]
}
```
