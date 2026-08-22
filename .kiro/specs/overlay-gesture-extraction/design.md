# Design Document: Overlay Gesture Extraction

## Overview

`OverlayView` today is a shallow module with a large surface: a raw `NSView` whose 45 methods tangle rendering, mouse routing, keyboard dispatch, selection, text-drag, fade, and passthrough. The genuinely valuable and bug-prone logic — the geometry of shape constraints and the select-move-with-clamp interaction — is buried in private handlers with no seam, so it is only reachable through a live view.

This design extracts that logic into two pure value types in `SpotdrawCore`, placing the seam at their interfaces so the same surface serves callers and tests. `OverlayView` becomes a thin adapter: convert event to point, call the module, interpret the result.

The design deliberately keeps the two extractions asymmetric because the underlying flows differ:

- **Shape/freehand creation** accumulates local geometry and commits one `addItem` at the end. It never previews into `DrawingState`.
- **Select-move** uses the `Live_Preview` technique: translate items directly on each drag (bypassing undo), then on release undo the preview and reapply the clamped total delta once through `DrawingState`. The clamp math and the sub-1.0pt threshold are the fragile parts.

## Architecture

### Before (shallow)

```
OverlayView : NSView  (1113 LOC, 45 funcs)
├── rendering: draw, drawBoard, drawCurrent*
├── shape gesture: mouseDown/Dragged/Up shape cases + commitCurrentDrawing (DUPLICATED logic)
├── select: handleSelect*, finishMoveDrag, clampMoveDelta, finishMarqueeDrag, SelectDragMode
├── text drag: handleText*, topmostTextAnnotation, routeTextCommit
└── keyboard, fade timer, context menus, mode indicator, passthrough drain
```

### After (deep modules behind small seams)

```
OverlayView : NSView  (thin adapter)
│   converts NSEvent → point, interprets outcomes, owns rendering + plumbing
├──> Shape_Gesture (SpotdrawCore, nonisolated struct)
│        point stream + tool + shift → preview geometry / committed Drawing_Item
├──> Select_Interaction (SpotdrawCore, nonisolated struct)
│        press/drag/release → Interaction_Outcome (intent, no side effects)
└──> DrawingState (existing, deep, already tested)
```

## Components and Interfaces

### Shape_Gesture (new, `Sources/SpotdrawCore/ShapeGesture.swift`)

A value type accumulating one drawing gesture. It owns no `NSView` and performs no side effects.

```swift
struct ShapeGesture {
    private(set) var tool: ToolType
    private var start: CGPoint
    private var current: CGPoint
    private var freehandPoints: [CGPoint]

    init(tool: ToolType, startingAt point: CGPoint)

    mutating func extend(to point: CGPoint)          // pen/highlighter append; shapes update end

    // Geometry for the in-progress preview (drives OverlayView.drawCurrent*)
    func previewGeometry(shiftHeld: Bool) -> ShapePreview

    // Finished item, or nil if the gesture produced nothing (e.g. single-point stroke)
    func commit(shiftHeld: Bool,
                color: NSColor,
                lineWidth: CGFloat,
                screenID: CGDirectDisplayID) -> DrawingItem?
}
```

`commit` centralizes the rules currently copy-pasted between `mouseUp` and `commitCurrentDrawing`:
- pen/highlighter: `smoothPoints`, highlighter ×4 width + 0.3 alpha, require >1 point;
- rectangle/circle: `rectFrom`, square via `max(w,h)` when shift;
- arrow/line: `constrainToAngles` when shift.

The difference between the two old commit paths (mouseUp appends the final point; drain does not) is captured by whether `extend(to:)` was called with the release point — the caller controls that, so a single `commit` covers both.

### Select_Interaction (new, `Sources/SpotdrawCore/SelectInteraction.swift`)

A state machine over the select drag lifecycle. It returns intent; the view executes it.

```swift
enum SelectDragMode { case none, movingSelection, drawingMarquee }

enum InteractionOutcome: Equatable {
    case none
    case setSelection([UUID])
    case toggleSelection(UUID)
    case clearSelection
    case previewTranslate(CGSize)         // per-drag live delta
    case marquee(CGRect)                  // marquee rect to render
    case commitMarquee(CGRect)            // resolve to intersecting items on release
    case commitMove(delta: CGSize)        // final clamped delta, applied once
}

struct SelectInteraction {
    private(set) var mode: SelectDragMode
    private var pressPoint: CGPoint
    private var lastPoint: CGPoint
    private var totalDelta: CGSize
    private var originalBBox: CGRect?     // pre-preview position, tracked explicitly

    mutating func begin(at point: CGPoint,
                        shiftHeld: Bool,
                        hit: HitResult,
                        currentBBox: CGRect?) -> InteractionOutcome

    mutating func drag(to point: CGPoint) -> InteractionOutcome

    mutating func end(viewBounds: CGRect) -> InteractionOutcome
}
```

Where `HitResult` is a small input describing what the view found at the press point (`insideSelectionBox`, `hitItem(UUID)`, or `emptySpace`) so hit-testing stays with `SelectionManager` in the view and only its result crosses the seam.

`Move_Clamp` moves inside `end`, using `originalBBox` (captured at `begin`) instead of the current, preview-shifted bbox. This removes the "current bbox minus total delta" reconstruction the old `clampMoveDelta` comment struggled to explain.

### OverlayView (reduced)

The view keeps a `var shapeGesture: ShapeGesture?` and `var selectInteraction = SelectInteraction()`. Mouse handlers become:

- shape tools: create/extend `shapeGesture`; on up, `addItem(gesture.commit(...))`.
- select tool: build `HitResult` via `SelectionManager`, call the interaction, then `switch` on the `InteractionOutcome`:
  - `previewTranslate(d)` → translate selected items directly (`Live_Preview`), `needsDisplay`.
  - `commitMove(delta)` → undo the live preview (translate by `-totalDelta`), then `drawingState.translate(ids:by: delta)`.
  - `setSelection/toggle/clear` → mutate `drawingState.selection`.
  - `marquee(r)` → store for `SelectionRenderer.drawMarquee`.
  - `commitMarquee(r)` → `SelectionManager.itemsIntersecting` → `selection.set`.

The undo-then-reapply ordering (Requirement 3.4) stays in the view exactly as today; the module never touches items.

## Data Models

No changes to `DrawingItem`, `DrawingState`, `DrawingOperation`, or `SelectionManager`. The new types are transient interaction state, not persisted model. `ShapePreview` is a small enum of geometry variants consumed only by the renderer.

## Error Handling

Both modules are total functions over their inputs: `commit` returns `nil` for degenerate gestures (single-point stroke), and the interaction returns `.none` for meaningless transitions (drag with `mode == .none`). No throwing. The view treats `nil`/`.none` as "do nothing", matching current behavior.

## Testing Strategy

Tests target the interfaces directly, off the main actor, mirroring the existing property-test style in `Tests/SpotdrawPropertyTests` and `Tests/SpotdrawTests`.

- **Shape_Gesture property tests**: square invariant under shift; angle constraint under shift; highlighter alpha/width; mouseUp-commit equals drain-commit for identical point streams; single-point stroke commits to `nil`.
- **Select_Interaction property tests**: committed move keeps ≥20pt visible for random bboxes and deltas; sub-1.0pt drag yields `commitMove(.zero)`-equivalent no-op; plain click → `setSelection([id])`; shift-click → `toggleSelection`; empty click no-shift → `clearSelection`; marquee → `commitMarquee` whose resolved ids equal `SelectionManager.itemsIntersecting`.
- **Regression**: the existing Selection/Transform/Text/OverlayDeactivation suites run unchanged and must stay green; they are the parity oracle.

Verification gate at each phase: `swift build --target Spotdraw` then `swift run SpotdrawTests`, expecting the prior count plus new tests, all passing.

## Migration / Sequencing

1. `Shape_Gesture` + tests, prove commit-parity, then rewire shape cases and delete duplicated `commitCurrentDrawing` geometry. Build + test.
2. `Select_Interaction` + tests, port clamp with explicit `originalBBox`, then rewire select cases to interpret outcomes. Build + test.

Each step is independently shippable and leaves the view behavior-identical.
