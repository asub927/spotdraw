# Implementation Plan: Overlay Gesture Extraction

## Overview

Extract the shape/freehand geometry and the select-tool interaction out of `OverlayView` into two pure value types in `SpotdrawCore` — `ShapeGesture` and `SelectInteraction` — placing the seam at their interfaces so the logic is testable without an `NSView`. This is a behavior-preserving refactor gated by the existing 78 tests. Sequenced in two independently shippable phases (shapes first, then select), each ending in a build + full-test checkpoint.

## Tasks

- [ ] 1. Extract Shape_Gesture (pen, highlighter, arrow, rectangle, circle, line)
  - [ ] 1.1 Create the `ShapeGesture` value type
    - Add a nonisolated `struct ShapeGesture` with `tool`, `start`, `current`, `freehandPoints`
    - `init(tool:startingAt:)`, `mutating func extend(to:)`, `func previewGeometry(shiftHeld:)`, `func commit(shiftHeld:color:lineWidth:screenID:) -> DrawingItem?`
    - Port square sizing (`max(w,h)`) for rectangle/circle, `constrainToAngles` for arrow/line, `smoothPoints` + highlighter ×4 width / 0.3 alpha for freehand
    - Return `nil` for single-point strokes
    - File: `Sources/SpotdrawCore/ShapeGesture.swift`
    - _Requirements: 1.1, 1.2, 1.3, 1.6, 5.1_

  - [ ]* 1.2 Write property tests for Shape_Gesture
    - Shift+rectangle and shift+circle produce a square
    - Shift+arrow and shift+line apply the angle constraint
    - Highlighter commit carries alpha 0.3 and ×4 line width
    - Commit for a point stream ending at the release point (mouseUp) equals commit for the same stream without the release point re-appended (drain), for identical inputs
    - Single-point stroke commits to `nil`
    - File: `Tests/SpotdrawPropertyTests/ShapeGesturePropertyTests.swift`
    - **Validates: Requirements 1.2, 1.3, 1.4, 1.5**

  - [ ] 1.3 Rewire OverlayView shape cases to Shape_Gesture
    - Replace `currentPoints`/`shapeStartPoint`/`currentShapeEndPoint`/`isDrawing` bookkeeping in `mouseDown/Dragged/Up` with a `ShapeGesture?`
    - Route `drawCurrent*` through `previewGeometry`
    - Replace both the `mouseUp` shape commit and `commitCurrentDrawing` with `gesture.commit(...)` + `drawingState.addItem`, deleting the duplicated logic
    - File: `Sources/Spotdraw/Overlay/OverlayView.swift`
    - _Requirements: 3.1, 3.3, 1.5_

  - [ ] 1.4 Verification checkpoint — shapes
    - Run `swift build --target Spotdraw`; confirm it succeeds
    - Run `swift run SpotdrawTests`; confirm all existing tests still pass plus the new Shape_Gesture tests
    - _Requirements: 4.1, 4.2, 4.4_

- [ ] 2. Extract Select_Interaction (marquee, hit selection, move-with-clamp)
  - [ ] 2.1 Create the `SelectInteraction` value type and `InteractionOutcome`
    - Add nonisolated `enum InteractionOutcome` (`none`, `setSelection`, `toggleSelection`, `clearSelection`, `previewTranslate`, `marquee`, `commitMarquee`, `commitMove`)
    - Add nonisolated `struct SelectInteraction` with `mode`, `pressPoint`, `lastPoint`, `totalDelta`, `originalBBox`
    - `begin(at:shiftHeld:hit:currentBBox:)`, `drag(to:)`, `end(viewBounds:)` returning outcomes only
    - Define the small `HitResult` input (`insideSelectionBox` / `hitItem(UUID)` / `emptySpace`)
    - File: `Sources/SpotdrawCore/SelectInteraction.swift`
    - _Requirements: 2.1, 2.2, 2.7, 5.1_

  - [ ] 2.2 Port move-clamp and marquee math into Select_Interaction
    - Move `clampMoveDelta` into `end(viewBounds:)`, using the explicitly tracked `originalBBox` instead of "current bbox minus total delta"
    - Move the sub-1.0pt no-op threshold into `end`
    - Move `rectFromPoints` marquee construction; return `commitMarquee(rect)` for the view to resolve via `SelectionManager.itemsIntersecting`
    - Return only the final clamped delta from `commitMove`
    - File: `Sources/SpotdrawCore/SelectInteraction.swift`
    - _Requirements: 2.3, 2.4, 2.5, 2.6_

  - [ ]* 2.3 Write property tests for Select_Interaction
    - Committed move keeps ≥20pt of the bounding box visible for random bboxes/deltas/view bounds
    - Sub-1.0pt drag yields a no-op move
    - Plain click → `setSelection([id])`; shift-click → `toggleSelection(id)`; empty-space no-shift click → `clearSelection`
    - `commitMarquee` rect resolves to exactly the ids from `SelectionManager.itemsIntersecting`
    - File: `Tests/SpotdrawPropertyTests/SelectInteractionPropertyTests.swift`
    - **Validates: Requirements 2.3, 2.4, 2.5, 4.3**

  - [ ] 2.4 Rewire OverlayView select cases to interpret outcomes
    - Build `HitResult` via `SelectionManager` in the view; pass to `SelectInteraction`
    - `switch` each `InteractionOutcome` into the matching `DrawingState` mutation, `Live_Preview` translate, marquee render, or committed move
    - Preserve the undo-then-reapply ordering: undo the live preview (translate by `-totalDelta`) before applying `commitMove` delta via `drawingState.translate(ids:by:)`
    - Remove `handleSelect*`, `finishMoveDrag`, `clampMoveDelta`, `finishMarqueeDrag`, `rectFromPoints`, and `SelectDragMode` from the view
    - File: `Sources/Spotdraw/Overlay/OverlayView.swift`
    - _Requirements: 3.2, 3.4, 2.5_

  - [ ] 2.5 Verification checkpoint — select
    - Run `swift build --target Spotdraw`; confirm it succeeds
    - Run `swift run SpotdrawTests`; confirm the existing Selection/Transform/Text/OverlayDeactivation suites pass unchanged plus the new Select_Interaction tests
    - _Requirements: 4.1, 4.3, 4.4_

- [ ] 3. Finalize and confirm scope
  - [ ] 3.1 Confirm file organization and size reduction
    - Verify `ShapeGesture.swift` and `SelectInteraction.swift` are one-type-per-file in `SpotdrawCore`
    - Verify `OverlayView.swift` LOC dropped materially from 1113 toward the ~400-line guideline via delegated logic
    - Verify text-tool drag path was left intact in `OverlayView`
    - _Requirements: 3.5, 5.2, 5.3_

  - [ ] 3.2 Confirm no scope creep
    - Verify `ToolbarPanelController` and the AppDelegate/CursorManager/MenuBarController toggle wiring are untouched
    - Run the full `swift run SpotdrawTests` a final time; confirm all pass
    - _Requirements: 4.5, 4.4_
