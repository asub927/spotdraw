# Requirements Document

## Introduction

This specification defines the extraction of gesture-to-operation logic out of `OverlayView` (currently 1113 LOC, 45 functions) into two pure, testable value-type modules in `SpotdrawCore`: a shape/freehand gesture accumulator and a select-tool interaction state machine. The goal is a deepening refactor: move the bug-prone geometry and interaction math behind small interfaces at a clean seam, so it can be tested directly (no `NSView`, no running app) and so maintainers have a single home for each concern.

This is a behavior-preserving refactor. The user-facing behavior of drawing, shape constraints, selection, marquee, and move-with-clamp MUST remain identical. The existing 78 tests are the safety net and MUST continue to pass unchanged.

This spec addresses the top recommendation from the architecture review (candidate 1: "The OverlayView god NSView").

## Glossary

- **Overlay_View**: The `NSView` subclass (`OverlayView.swift`) that today handles mouse input, keyboard dispatch, rendering, selection, text-drag, fade, and passthrough.
- **Drawing_State**: The model layer managing drawing items, undo/redo, tool/color state (`DrawingState.swift` in `SpotdrawCore`).
- **Drawing_Item**: Any annotation element (freehand stroke, arrow, rectangle, circle, line, text).
- **Shape_Gesture**: The new pure value type that accumulates a point stream for the pen/highlighter/arrow/rectangle/circle/line tools and produces preview geometry and a committed `Drawing_Item`.
- **Select_Interaction**: The new pure value type that models the select tool's press/drag/release lifecycle (marquee draw, move-with-clamp, hit selection) as data.
- **Interaction_Outcome**: A value returned by `Select_Interaction` describing what should happen (preview translate, commit move, set/toggle/clear selection, draw marquee) without performing any side effect.
- **Live_Preview**: The existing technique where select-move and text-drag translate items directly on each drag event (bypassing `Drawing_State`/undo), accumulate a total delta, then on release undo the preview and reapply the total delta once through `Drawing_State` so exactly one `.move` is recorded.
- **Move_Clamp**: The rule that a committed move keeps at least 20pt of the selection bounding box inside the view bounds (`clampMoveDelta`, Requirement 3.9 of the annotation-parity spec).

## Requirements

### Requirement 1: Shape_Gesture module extraction

**User Story:** As a maintainer, I want the shape and freehand creation geometry in one pure module, so that the square/angle/smoothing/highlighter rules live in a single tested place instead of being duplicated between `mouseUp` and `commitCurrentDrawing`.

#### Acceptance Criteria

1. THE Extraction SHALL introduce a `Shape_Gesture` value type in `SpotdrawCore` that accepts a starting point and `ToolType`, extends with subsequent points, and produces both preview geometry and a committed `Drawing_Item`.
2. THE Shape_Gesture SHALL encapsulate the shift-constraint rules: square sizing (`max(width, height)`) for rectangle and circle when shift is held, and angle constraining (`DrawingRenderer.constrainToAngles`) for arrow and line when shift is held.
3. THE Shape_Gesture SHALL encapsulate the freehand rules: point smoothing (`DrawingRenderer.smoothPoints`) on commit, and the highlighter width multiplier (×4) and alpha (0.3).
4. WHEN `Shape_Gesture` commits, THEN the produced `Drawing_Item` SHALL be identical to what `OverlayView.mouseUp` produced for the same tool, points, and shift state before this refactor.
5. WHEN `Shape_Gesture` commits mid-gesture (passthrough drain), THEN the produced `Drawing_Item` SHALL be identical to what `OverlayView.commitCurrentDrawing` produced before this refactor, eliminating the duplicated commit logic.
6. THE Shape_Gesture SHALL be `@MainActor`-free (nonisolated), containing only value math so it can be tested off the main actor.

### Requirement 2: Select_Interaction module extraction

**User Story:** As a maintainer, I want the select-tool press/drag/release logic as a pure state machine, so that marquee, hit selection, and move-with-clamp become testable through a small interface without an `NSView`.

#### Acceptance Criteria

1. THE Extraction SHALL introduce a `Select_Interaction` value type in `SpotdrawCore` modeling the three drag modes (`none`, `movingSelection`, `drawingMarquee`) and the press/drag/release lifecycle.
2. THE Select_Interaction SHALL return `Interaction_Outcome` values describing intent (`previewTranslate`, `commitMove`, `setSelection`, `toggleSelection`, `clearSelection`, `marquee`, `none`) and SHALL NOT itself mutate `Drawing_Item`s or trigger redraws.
3. THE Select_Interaction SHALL encapsulate `Move_Clamp` (the 20pt minimum-visible rule) and the sub-1.0pt "no-op move" threshold currently in `finishMoveDrag`.
4. THE Select_Interaction SHALL encapsulate marquee rect construction (`rectFromPoints`) and the intersecting-items query contract used by `finishMarqueeDrag`.
5. WHEN `Select_Interaction` computes a committed move delta, THEN it SHALL return only the final clamped delta, matching the pre-refactor flow where `Overlay_View` undoes the `Live_Preview` and reapplies the clamped total through `Drawing_State` exactly once.
6. THE Select_Interaction SHALL track the pre-preview selection position explicitly rather than reconstructing it as "current bbox minus total delta", removing the ambiguity documented in the existing `clampMoveDelta` comments.
7. THE Select_Interaction SHALL be `@MainActor`-free (nonisolated), containing only value math.

### Requirement 3: OverlayView reduction and interpretation

**User Story:** As a maintainer, I want `OverlayView` reduced to input plumbing, rendering, and outcome interpretation, so that the view is a thin adapter over the extracted modules.

#### Acceptance Criteria

1. THE Overlay_View SHALL delegate shape/freehand `mouseDown/Dragged/Up` accumulation and commit to `Shape_Gesture`.
2. THE Overlay_View SHALL delegate select `mouseDown/Dragged/Up` to `Select_Interaction` and interpret each `Interaction_Outcome` into the corresponding `Drawing_State` mutation, `item.translate` `Live_Preview`, and `needsDisplay` call.
3. THE Overlay_View SHALL retain responsibility for rendering (`draw`, `drawBoard`, `drawCurrent*`), keyboard/shortcut dispatch, the fade timer, context menus, the mode indicator, and text editing (which already delegates to `TextEditingController`).
4. THE refactor SHALL NOT change the `Live_Preview` undo-then-reapply ordering; `Overlay_View` SHALL undo the preview translation before applying any committed move delta returned by `Select_Interaction`.
5. THE text-tool drag path SHALL remain in `Overlay_View` for this phase and MAY be extracted in a later phase.

### Requirement 4: Behavior preservation and verification

**User Story:** As a maintainer, I want proof that nothing changed for users, so that the refactor is safe to merge.

#### Acceptance Criteria

1. THE refactor SHALL keep all existing 78 tests passing without modifying their assertions, specifically the Selection, Transform, Text, and Overlay-deactivation suites.
2. THE refactor SHALL add property tests for `Shape_Gesture` proving: shift+rectangle/circle yields a square, shift+arrow/line applies angle constraint, highlighter commit carries alpha 0.3 and ×4 width, and commit-on-mouseUp equals commit-on-drain for identical input.
3. THE refactor SHALL add property tests for `Select_Interaction` proving: a committed move never leaves fewer than 20pt of the bounding box visible, a sub-1.0pt drag records no move, plain click sets a single-item selection, shift-click toggles, empty-space click without shift clears, and a marquee selects exactly the intersecting items.
4. WHEN the refactor is complete, THEN `swift build --target Spotdraw` SHALL succeed and `swift run SpotdrawTests` SHALL report all tests passing (78 existing plus the new gesture/interaction tests).
5. THE refactor SHALL NOT touch `ToolbarPanelController` (review candidate 2) or the feature-toggle wiring across `AppDelegate`/`CursorManager`/`MenuBarController` (review candidate 3).

### Requirement 5: File organization

**User Story:** As a maintainer, I want the new modules to follow the project's own conventions, so that the codebase stays navigable.

#### Acceptance Criteria

1. THE Extraction SHALL place `Shape_Gesture` and `Select_Interaction` in their own files in `Sources/SpotdrawCore`, one type per file, named to match the type.
2. THE resulting `OverlayView.swift` SHALL move materially below its current 1113 LOC toward the project's ~400-line guideline, with the reduction coming from delegated logic rather than reformatting.
3. THE new test files SHALL live under `Tests/` alongside the existing property tests and be wired into the headless `SpotdrawTests` runner.
