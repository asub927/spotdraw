# Requirements Document

## Introduction

This specification defines the Swift best practices improvements to be applied across the SpotDraw macOS annotation application codebase. SpotDraw is a menu-bar utility providing screen annotation, cursor highlighting, spotlight dimming, and zoom features. The refactoring targets alignment with Apple's Swift API Design Guidelines, modern Swift language features (5.7+), and preparation for Swift 6 strict concurrency.

## Glossary

- **SpotDraw**: The macOS annotation application under review
- **Overlay_System**: The full-screen transparent overlay that captures drawing input (OverlayWindowController, OverlayView)
- **Drawing_State**: The model layer managing drawing items, undo/redo, and tool/color state (DrawingState.swift)
- **Cursor_System**: The cursor highlight and spotlight subsystem (CursorManager, CursorHighlightWindow, SpotlightWindow, ZoomWindow)
- **Settings_System**: The persistent settings layer and its SwiftUI UI (SettingsManager, SettingsWindowController)
- **Hotkey_System**: The global keyboard shortcut registration and dispatch layer (HotkeyManager)
- **Menu_Bar_System**: The NSStatusItem menu and state controller (MenuBarController)
- **Drawing_Item**: Any annotation element drawn on the overlay (strokes, shapes, arrows, lines)

## Requirements

### Requirement 1: Access Control and Type Safety

**User Story:** As a maintainer, I want explicit access control on all types and members, so that the public API surface is intentional and internal implementation details are protected.

#### Acceptance Criteria

1. THE Refactoring SHALL add explicit `final` keyword to all classes that are not designed for subclassing, including FreehandStroke, ArrowShape, RectangleShape, CircleShape, LineShape, CursorHighlightWindow, SpotlightWindow, ZoomWindow, CursorManager, MenuBarController, OverlayWindowController, OverlayView, SettingsWindowController, HotkeyManager, SettingsManager, and AppDelegate.
2. THE Refactoring SHALL add explicit `private` access control to all stored properties that are not part of a type's intended API, including `currentPoints`, `shapeStartPoint`, `currentShapeEndPoint`, `isDrawing`, `isShiftHeld`, and `fadeTimer` in OverlayView; `window`, `highlightLayer` in CursorHighlightWindow; `window`, `spotlightView` in SpotlightWindow; `overlayWindows`, `drawingState`, `screenObserver` in OverlayWindowController; and `handlers`, `globalMonitor`, `localMonitor` in HotkeyManager.
3. THE Refactoring SHALL mark the `drawingState` property in OverlayView with `private(set)` access control since external code assigns it but should not mutate it arbitrarily.
4. THE Refactoring SHALL add `public` or `internal` access control keywords explicitly to all type declarations to document intent, even where `internal` is the default.
5. WHEN a property is exposed only for reading by external code, THEN THE Refactoring SHALL use `private(set)` pattern, as already done correctly on `isHighlightActive`, `isSpotlightActive`, and `isZoomActive` in CursorManager.

### Requirement 2: Modern Swift Syntax Adoption

**User Story:** As a developer, I want the codebase to use modern Swift syntax (5.7+), so that code is concise, safe, and idiomatic.

#### Acceptance Criteria

1. WHEN optional binding uses the pattern `guard let x = x` or `if let x = x` where the variable name matches, THEN THE Refactoring SHALL use the shorthand `guard let x` or `if let x` syntax introduced in Swift 5.7, applying this to occurrences in SpotlightWindow (`guard let spotlightView, let window`), CursorHighlightWindow (`guard let window`), ZoomWindow (`guard let window`), and OverlayWindowController (`guard let window`).
2. THE Refactoring SHALL replace the forced unwrap `points.last!` in FreehandStroke.draw(in:) and the smoothPoints helper with a safe alternative using `guard let last = points.last else { return }`.
3. THE Refactoring SHALL add `CaseIterable` conformance to ToolType so that menu generation and tool iteration can use `ToolType.allCases`.
4. THE Refactoring SHALL add `Hashable` conformance to ToolType enum since it is used as a conceptual key for tool selection.
5. WHEN a switch statement is used solely to assign a value to a variable, THEN THE Refactoring SHALL evaluate using Swift 5.9 if/switch expressions where the result is clearer, specifically in the `keyCode` and `modifiers` computed properties of GlobalShortcut.

### Requirement 3: Protocol and Enum Design

**User Story:** As a developer, I want protocols and enums to encapsulate their own behavior, so that logic is not duplicated and types are self-documenting.

#### Acceptance Criteria

1. THE Refactoring SHALL add a `nextMode` method or computed property to BoardMode enum that encapsulates the cycling logic (none -> white -> black -> none), eliminating the duplicate switch statements in OverlayView.toggleBoard() and OverlayWindowController.toggleBoard().
2. THE Refactoring SHALL add a `keyCharacter` computed property to ToolType enum mapping each tool to its keyboard shortcut character ("p" for pen, "a" for arrow, "r" for rectangle, "o" for circle, "l" for line, "h" for highlighter, "e" for eraser), replacing the duplicated character-to-tool mapping in OverlayView.keyDown(with:).
3. THE Refactoring SHALL add a protocol extension to DrawingItem providing a default `hitTest` implementation for line-segment-based shapes (ArrowShape, LineShape) that delegates to the shared `distanceFromPointToLine` calculation.
4. THE Refactoring SHALL mark all DrawingItem-conforming classes as `final` to communicate they are not designed for subclassing and to allow compiler optimizations.
5. WHEN the DrawingItem protocol is referenced as a type in collections or function parameters, THEN THE Refactoring SHALL use explicit `any DrawingItem` syntax consistently to prepare for Swift 6 existential requirements.

### Requirement 4: Code Organization and File Structure

**User Story:** As a maintainer, I want source files to follow the single-responsibility principle with consistent internal organization, so that navigation and code review are efficient.

#### Acceptance Criteria

1. THE Refactoring SHALL extract the six DrawingItem conforming types (FreehandStroke, ArrowShape, RectangleShape, CircleShape, LineShape) from DrawingState.swift into a separate DrawingItems.swift file, leaving DrawingState.swift to contain only the DrawingState class, ToolType enum, BoardMode enum, and the geometry utility.
2. THE Refactoring SHALL move the free function `distanceFromPointToLine` into a static method on a `GeometryUtils` enum (caseless enum used as namespace) or as a CGPoint extension method.
3. THE Refactoring SHALL extract the drawing rendering logic from OverlayView (methods `drawCurrentStroke`, `drawCurrentArrow`, `drawCurrentRect`, `drawCurrentCircle`, `drawCurrentLine`, `drawArrowhead`) into a dedicated `DrawingRenderer` helper type or extension.
4. THE Refactoring SHALL add a `typealias` for the handler dictionary type `[GlobalShortcut: () -> Void]` in HotkeyManager to improve readability.
5. THE Refactoring SHALL ensure all files use consistent MARK section structure: Properties, Init, Setup, Public API, Private Methods, Cleanup/Deinit, applying this to SpotlightView and ZoomWindow which currently lack consistent MARK organization.

### Requirement 5: Memory Management and Lifecycle

**User Story:** As a developer, I want deterministic resource cleanup, so that timers, event monitors, and observers do not leak or fire after their owner is logically defunct.

#### Acceptance Criteria

1. THE Refactoring SHALL add `viewDidMoveToWindow` or `viewWillMove(toWindow:)` override in OverlayView that invalidates `fadeTimer` when the view is removed from its window (window becomes nil), preventing timer retention after the view leaves the hierarchy.
2. WHEN NotificationCenter observers are registered with the closure-based API, THEN THE Refactoring SHALL store the observer token and remove it in `deinit`, as already done in OverlayWindowController, and verify this pattern is consistent across all observer registrations.
3. THE Refactoring SHALL add a `typealias EventMonitorToken = Any` in HotkeyManager and CursorManager to document the opaque monitor return type from `NSEvent.addGlobalMonitorForEvents`.
4. IF the OverlayWindowController is deallocated while its overlay windows are still on screen, THEN THE Refactoring SHALL ensure windows are explicitly closed in `deinit` to prevent orphaned windows.
5. THE Refactoring SHALL verify that CursorManager.deinit removes the mouse monitor, and add matching cleanup for SpotlightWindow, CursorHighlightWindow, and ZoomWindow if their windows are ordered on screen at deallocation time.

### Requirement 6: SwiftUI Best Practices

**User Story:** As a developer, I want the SwiftUI settings views to use current API patterns, so that deprecation warnings are eliminated and state is managed correctly.

#### Acceptance Criteria

1. WHEN using `.onChange(of:)` modifier in settings views, THEN THE Refactoring SHALL migrate to the two-parameter closure form `.onChange(of: value) { oldValue, newValue in }` introduced in macOS 14, or use the single-parameter iOS 17+ form if the deployment target permits, eliminating the deprecated single-trailing-closure variant currently used in GeneralSettingsTab, AnnotationSettingsTab, CursorSettingsTab, and SpotlightSettingsTab.
2. THE Refactoring SHALL extract the shared color preset arrays (currently duplicated in AnnotationSettingsTab and CursorSettingsTab) into a single shared constant accessible by both views.
3. THE Refactoring SHALL add inline documentation comments for magic numbers in slider ranges (stroke width 1...20, highlight size 20...100, spotlight size 50...300, dim intensity 0.3...0.9, opacity 0.1...1.0, fade duration 1...10) explaining the rationale for each bound.
4. WHEN `@State` properties are initialized from `SettingsManager.shared` values, THEN THE Refactoring SHALL document that these represent initial snapshots and do not automatically sync with external changes, or refactor to use a shared `@Observable` model if bidirectional sync is needed.
5. THE Refactoring SHALL ensure all SwiftUI views in SettingsWindowController.swift use `some View` return type consistently and avoid unnecessary type erasure.

### Requirement 7: API Design and Naming

**User Story:** As a developer, I want method and type names to follow Apple's Swift API Design Guidelines, so that the code reads naturally at the call site.

#### Acceptance Criteria

1. THE Refactoring SHALL rename the free function `distanceFromPointToLine(point:lineStart:lineEnd:)` to follow Swift naming conventions, using either `CGPoint.distance(toLineFrom:to:)` as an extension method or `GeometryUtils.distance(from:toLineSegment:)` as a static method.
2. WHEN callback closures are stored as properties (e.g., `onDeactivate`, `onToggleAnnotation`), THEN THE Refactoring SHALL ensure they follow the `on` + event name pattern consistently, which is already correctly applied throughout the codebase.
3. THE Refactoring SHALL rename `handleMouseEvent(_:)` in CursorManager to `processMouseEvent(_:)` or `routeMouseEvent(_:)` to better describe its dispatching behavior, following the guideline that methods should describe their effect.
4. THE Refactoring SHALL ensure all Boolean properties read as assertions: verifying that `isHighlightActive`, `isSpotlightActive`, `isZoomActive`, `isActive`, `isDrawing`, `isShiftHeld` all conform to this pattern, which they currently do.
5. WHEN a method creates and returns a configured object, THEN THE Refactoring SHALL use the `make` prefix (e.g., rename `createOverlayWindow(for:)` to `makeOverlayWindow(for:)`) following Apple's factory method naming convention.

### Requirement 8: Swift 6 Concurrency Preparation

**User Story:** As a developer, I want the codebase prepared for Swift 6 strict concurrency checking, so that data races are prevented at compile time.

#### Acceptance Criteria

1. THE Refactoring SHALL add `@MainActor` annotation to all UI classes: AppDelegate, OverlayWindowController, OverlayView, CursorManager, CursorHighlightWindow, SpotlightWindow, ZoomWindow, MenuBarController, SettingsWindowController, and HotkeyManager.
2. THE Refactoring SHALL add `@MainActor` annotation to SettingsManager.shared singleton and its properties, since all access occurs on the main thread for UI updates.
3. WHEN Timer callbacks or NSEvent monitor callbacks are registered, THEN THE Refactoring SHALL ensure closures are annotated or structured to execute on the main actor, preventing potential data races with UI state.
4. THE Refactoring SHALL add `Sendable` conformance to ToolType and BoardMode enums since they may be passed across concurrency boundaries.
5. THE Refactoring SHALL add `nonisolated(unsafe)` or restructure the `SettingsManager.shared` static property to satisfy strict concurrency checking for global actor-isolated static properties.

### Requirement 9: Documentation Standards

**User Story:** As a maintainer, I want consistent documentation on all public APIs and complex logic, so that the codebase is understandable without reading every implementation detail.

#### Acceptance Criteria

1. THE Refactoring SHALL add Swift documentation comments (`///`) to all protocol declarations and their requirements, specifically the DrawingItem protocol and each of its required properties and methods.
2. THE Refactoring SHALL add file-level documentation comments at the top of each Swift source file describing the file's purpose and its role in the architecture.
3. THE Refactoring SHALL add documentation comments to all `public` or `internal` methods that form a type's API surface, including toggle methods in CursorManager, lifecycle methods in OverlayWindowController, and registration methods in HotkeyManager.
4. THE Refactoring SHALL document the design decision for DrawingState being a reference type (class) rather than a value type (struct), explaining that multiple OverlayView instances share the same drawing state instance intentionally.
5. WHEN a class contains complex logic (point smoothing algorithm in OverlayView, hit-test geometry in DrawingItem conformances, screen coordinate conversion in ZoomWindow), THEN THE Refactoring SHALL add inline comments explaining the algorithm or mathematical approach used.
