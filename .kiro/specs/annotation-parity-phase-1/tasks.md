# Implementation Plan: Annotation Parity Phase 1

## Overview

Implementation language is **Swift** — the design specifies concrete Swift types throughout, so no language selection is needed.

The seven task groups below mirror the design's Implementation Phasing section exactly and are strictly sequential: each group's checkpoint must pass before the next begins. The two changes that put existing tests at risk (the `DrawingState` operation-stack rewrite and the test-source drift fix) are front-loaded so a regression surfaces while the diff is still small.

**Property-test harness split (design Decision 5).** Properties 1–5 are written against the existing hand-rolled harness in `SpotdrawTests` (`SimplePRNG`, `runPreservationTest(_:iterations:_:)`), are **not** optional, and gate phase 1. Properties 6–26 are also written against the hand-rolled harness in this phase but are marked optional (`*`) and carry a port note: they migrate to PropertyBased when the deferred `SpotdrawPropertyTests` target lands. No task in this plan touches `Package.swift` or `project.yml` — both are explicitly out of scope.

**Checkpoint commands** (run from `/Users/aaranvi/dev/spotdraw`):

```
swift build --target Spotdraw
swift build --target SpotdrawTests
swift run SpotdrawTests
```

`SpotdrawTests/PreservationPropertyTests.swift` must stay at **13/13 passing** at every checkpoint and **must never be modified**.

---

## Tasks

- [x] 1. Operation stack and translation offset

  - [x] 1.1 Record the preservation-suite baseline before touching any model code
    - Run `swift build --target SpotdrawTests` and `swift run SpotdrawTests` on the unmodified tree
    - Record the result in the task notes; it must read 13/13 passing
    - Do not edit any file in this task — this is the reference point the rest of phase 1 is measured against
    - _Requirements: 10.3, 10.4, 10.6, 10.8_

  - [x] 1.2 Add `offset` and `untranslatedBounds` to the `DrawingItem` protocol and all five conformances
    - In `Spotdraw/Core/DrawingState.swift`, add `var offset: CGSize { get set }` and `var untranslatedBounds: CGRect { get }` to the `DrawingItem` protocol
    - In `Spotdraw/Core/DrawingItems.swift`, give each of `FreehandStroke`, `ArrowShape`, `RectangleShape`, `CircleShape`, `LineShape` exactly one stored line `var offset: CGSize = .zero` plus a computed `untranslatedBounds` per the design's bounds table
    - `FreehandStroke.untranslatedBounds` must cache via `lazy var` — it is derived from a `let points` array that can hold hundreds of entries and is read on every marquee test and outline draw
    - Leave every existing `draw(in:)` and `hitTest(point:threshold:)` body byte-for-byte unchanged
    - _Requirements: 2.3, 3.1_

  - [x] 1.3 Create the `DrawingItem` transform extension
    - New file `Spotdraw/Core/DrawingItem+Transform.swift`
    - Implement `bounds` (`untranslatedBounds` offset by `offset`), `render(in:)` (fast path when `offset == .zero`, otherwise `saveGState` / `translateBy` / `draw` / `restoreGState`), `hitTestTranslated(point:threshold:)` (moves the test point into untranslated space), and `translate(by:)` (accumulates into `offset`)
    - _Requirements: 3.1, 3.2, 3.3_

  - [x] 1.4 Create the `DrawingOperation` type and its inverse application
    - New file `Spotdraw/Core/DrawingOperation.swift` with cases `.add(item:)`, `.remove(entries:)`, `.move(itemIDs:offset:)`, `.edit(index:before:after:)`
    - **`.remove` undo MUST reinsert at the recorded indices in ascending index order.** Descending reinsertion places later items at indices of a list that does not yet contain the earlier ones and silently corrupts order
    - Implement the full inverse table from design Decision 1 for both undo and redo directions
    - _Requirements: 3.5, 3.6, 3.8, 1.9_

  - [x] 1.5 Rewrite `DrawingState` onto the operation stacks as an isolated change
    - In `Spotdraw/Core/DrawingState.swift`, replace `private var undoStack: [any DrawingItem]` with `private var undoStack: [DrawingOperation]` and `private var redoStack: [DrawingOperation]`
    - Add `translate(ids:by:)` recording `.move`, `replaceItem(at:with:)` recording `.edit`, and `item(withID:)`
    - Route every item-removing mutation through a single private helper, so later selection pruning holds by construction
    - **`clearAll()` must clear items and BOTH stacks — it must not record a `.remove` operation.** Recording `.remove` would let undo resurrect every cleared item, a behavior change Requirement 10.8 forbids and the existing tests do not catch
    - **No feature work in this task.** No new `ToolType` cases, no `SelectionManager`, no `activeTool` observer — those land in phases 3 and 4
    - The six observable behaviors from design Decision 1 must hold: undo after N adds leaves N−1 and redo restores N; K undos then K redos returns to the original count; undo on empty is a no-op; redo with nothing undone is a no-op; adding after an undo makes redo a no-op; `clearAll()` empties items and makes redo a no-op
    - _Requirements: 10.3, 10.4, 10.8, 3.4, 3.7, 1.9_

  - [x] 1.6 Update the two call sites that consume the transform extension
    - `Spotdraw/Overlay/OverlayView.swift`: in `draw(_:)`, change `item.draw(in: context)` to `item.render(in: context)`
    - `Spotdraw/Core/DrawingState.swift`: in `removeItems(intersecting:threshold:)`, change `hitTest` to `hitTestTranslated`
    - These are the only two call-site changes in phase 1
    - _Requirements: 10.1, 10.2_

  - [x] 1.7 Link the new production files into the test target
    - Add symlinks under `SpotdrawTests/` for `DrawingOperation.swift` and `DrawingItem+Transform.swift` pointing at their `Spotdraw/Core/` counterparts
    - Confirm `swift build --target SpotdrawTests` resolves the new symbols
    - _Requirements: 10.3_

  - [x] 1.8 Write the property test for operation-stack invertibility
    - New file `SpotdrawTests/OperationPropertyTests.swift`; register the test in `SpotdrawTests/main.swift`
    - **Property 1: Operation-stack invertibility** — compare identifier sequences, accumulated offsets, and text content, not counts; count equality is too weak an oracle to catch a mis-ordered `.remove` inverse
    - Use `runPreservationTest(_:iterations:_:)` with at least 100 iterations; tag with `// Feature: annotation-parity-phase-1, Property 1: Operation-stack invertibility`
    - Build a `DrawingOperation` sequence generator over `SimplePRNG` for reuse by tasks 1.9 and 7.12
    - **Validates: Requirements 3.5, 3.6, 3.8, 1.9, 10.3**

  - [x] 1.9 Write the property test for redo invalidation on add
    - Extend `SpotdrawTests/OperationPropertyTests.swift`; register in `SpotdrawTests/main.swift`
    - **Property 2: Redo invalidation on add** — after any operation sequence, at least one undo, then an add, redo leaves the item list unchanged
    - Minimum 100 iterations; carry the property comment tag
    - **Validates: Requirements 10.4**

  - [x] 1.10 Write the property test for translation accumulation
    - New file `SpotdrawTests/TransformPropertyTests.swift`; register in `SpotdrawTests/main.swift`
    - **Property 3: Translation accumulation** — two sequential deltas equal their component-wise sum applied once, and `bounds` equals `untranslatedBounds` shifted by the accumulated offset
    - Build shared `SimplePRNG`-driven factory functions for every `DrawingItem` type, including degenerate cases (single-point strokes, zero-size rects, coincident endpoints)
    - Minimum 100 iterations; carry the property comment tag
    - **Validates: Requirements 3.1, 3.2, 1.10**

  - [x] 1.11 Write the property test for bounds and hit-test agreement
    - Extend `SpotdrawTests/TransformPropertyTests.swift`; register in `SpotdrawTests/main.swift`
    - **Property 4: Bounds and hit-test agreement** — a true `hitTestTranslated` implies `bounds` outset by `threshold` contains the point, and every defining geometry point lies within `bounds`
    - Cover all five existing item types; minimum 100 iterations
    - **Validates: Requirements 2.3, 1.11**

  - [x] 1.12 Write the property test for eraser semantics under translation
    - Extend `SpotdrawTests/TransformPropertyTests.swift`; register in `SpotdrawTests/main.swift`
    - **Property 5: Eraser semantics under translation** — after `removeItems(intersecting:threshold: 15)`, survivors are exactly the items for which `hitTestTranslated` returns false
    - Minimum 100 iterations
    - **Validates: Requirements 10.2**

- [x] 2. HARD GATE — phase 1 checkpoint
  - Run `swift build --target Spotdraw`, `swift build --target SpotdrawTests`, `swift run SpotdrawTests`
  - The preservation suite must report **13/13 passing**, matching the task 1.1 baseline exactly
  - Properties 1–5 must all pass
  - Any preservation failure is a genuine behavior change and MUST be resolved by fixing the implementation. **Never edit `SpotdrawTests/PreservationPropertyTests.swift`**
  - **Do not proceed past this gate.** Ensure all tests pass, ask the user if questions arise.

- [x] 3. Test source drift fix

  - [x] 3.1 Create the idempotent test-source link script
    - New file `scripts/link-test-sources.sh` (the repository already uses lowercase `scripts/`), executable
    - Glob every `*.swift` under `Spotdraw` excluding `App/`, and `ln -sf` each into `SpotdrawTests/` by basename
    - The script must be safe to re-run and must **replace** existing real files, not sit beside them
    - _Requirements: 10.3_

  - [x] 3.2 Replace the three drifted real copies with symlinks and re-verify
    - Run `scripts/link-test-sources.sh`, converting `SpotdrawTests/AccessibilityManager.swift`, `SpotdrawTests/DrawingRenderer.swift`, and `SpotdrawTests/GeometryUtils.swift` from real copies into symlinks
    - `AccessibilityManager.swift` regaining its production `internal final class` declaration changes what the test target compiles, so re-run the full suite and confirm 13/13 against the now-current source
    - Do not modify `Package.swift` or `project.yml`
    - _Requirements: 10.3, 10.11_

- [x] 4. Checkpoint — drift fix verified
  - Run all three checkpoint commands; preservation suite must remain 13/13 and Properties 1–5 must still pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. Text annotation

  - [x] 5.1 Persist the default text font size
    - `Spotdraw/Core/SettingsManager.swift`: add a `textFontSize` accessor clamped to 8…96 with a default of 24, following the existing `clamped(to:)` pattern
    - _Requirements: 1.13_

  - [x] 5.2 Implement `TextAnnotation`
    - New file `Spotdraw/Core/TextAnnotation.swift`; add a symlink under `SpotdrawTests/`
    - Conform to `DrawingItem`: `id`, `color`, `lineWidth` returning 0, `createdAt`, mutable `opacity`, `offset`, `draw(in:)` via `NSAttributedString` pushed through an `NSGraphicsContext`, `hitTest(point:threshold:)` against measured glyph bounds, and a cached `untranslatedBounds` derived from `NSAttributedString.size()` anchored at `anchor`
    - Apply `opacity` through `context.setAlpha` so existing fade processing works unchanged
    - Add `replacingString(_:)` returning a copy that preserves `id`, `anchor`, `fontSize`, and `color`, which is what makes `.edit` trivially invertible
    - _Requirements: 1.11, 1.12, 10.5_

  - [x] 5.3 Add the `.text` tool case and widen the affected switches
    - `Spotdraw/Core/DrawingState.swift`: add `case text` to `ToolType`
    - `Spotdraw/Overlay/OverlayView.swift`: add `.text` arms to `drawCurrentItem`, `mouseDown`, `mouseDragged`, and `mouseUp` — the compiler enforces exhaustiveness, so there is no silent-fallthrough risk
    - Leave `ToolType.keyCharacter` in place for now; it is removed in phase 6
    - _Requirements: 1.1_

  - [x] 5.4 Implement `TextEditingController`
    - New file `Spotdraw/Overlay/TextEditingController.swift`; add a symlink under `SpotdrawTests/`
    - Manage a borderless, transparent single-line `NSTextField` subview lifecycle via `begin(at:existing:in:color:fontSize:)` and `commit() -> TextCommitResult`
    - Snapshot the color and font size at `begin` time and carry them into the committed item
    - Both Return and Escape commit; `commit()` trims whitespace and returns `.discarded` for an empty result, leaving `DrawingState.items` and both stacks untouched
    - Beginning an edit while one is active commits the first, then begins the second
    - _Requirements: 1.4, 1.5, 1.6, 1.7, 1.15_

  - [x] 5.5 Wire text interactions into `OverlayView`
    - Press on empty space with the text tool active begins editing anchored at that point
    - Double-click inside an existing `TextAnnotation` bounding rectangle begins editing with its current string at its anchor
    - Drag from inside an existing `TextAnnotation` bounding rectangle translates it and records one `.move` operation on drag end
    - Route `.created` to `DrawingState.addItem` and `.edited` to `DrawingState.replaceItem(at:with:)` so the edit occupies the same index and records exactly one undoable operation
    - _Requirements: 1.3, 1.8, 1.9, 1.10_

  - [x] 5.6 Make `keyDown` Editing_State-aware
    - `Spotdraw/Overlay/OverlayView.swift`: the `textEditing.isEditing` guard must be the **first** thing `keyDown(with:)` checks, before any character or modifier inspection
    - Inside Editing_State, Escape and Return commit and return; everything else falls through to `super.keyDown`. Escape must not invoke `onDeactivate`
    - Outside Editing_State the existing deactivate path is unchanged for now; it becomes a store lookup in phase 6
    - _Requirements: 1.6, 10.12_

  - [x] 5.7 Add the font-size control to the Annotation settings tab
    - `Spotdraw/Settings/SettingsWindowController.swift`: add a control in the Annotation tab bound to the persisted text font size across 8…96 points
    - _Requirements: 1.14_

  - [x] 5.8* Write the property test for fade removal across every item type
    - New file `SpotdrawTests/TextPropertyTests.swift`; register in `SpotdrawTests/main.swift`
    - **Property 6: Fade removal covers every item type** — with fade mode on, survivors are exactly the items whose age does not exceed the fade duration by more than one second, including `TextAnnotation`
    - Hand-rolled harness now; port to PropertyBased after the target split
    - **Validates: Requirements 10.5**

  - [x] 5.9* Write the property test for text commit acceptance
    - Extend `SpotdrawTests/TextPropertyTests.swift`; register in `SpotdrawTests/main.swift`
    - **Property 7: Text commit accepts exactly the non-empty strings** — commit creates one `TextAnnotation` whose string equals the trimmed input when non-empty, and leaves items and both stacks unchanged otherwise
    - Build a whitespace generator covering spaces, tabs, newlines, and Unicode whitespace
    - Hand-rolled harness now; port to PropertyBased after the target split
    - **Validates: Requirements 1.5, 1.6, 1.7**

  - [x] 5.10* Write the property test for style snapshotting
    - Extend `SpotdrawTests/TextPropertyTests.swift`; register in `SpotdrawTests/main.swift`
    - **Property 8: Text style is snapshotted when editing begins** — mutating active color and persisted font size mid-composition does not affect the committed item
    - Hand-rolled harness now; port to PropertyBased after the target split
    - **Validates: Requirements 1.15, 1.4**

  - [x] 5.11* Write the property test for text bounds
    - Extend `SpotdrawTests/TextPropertyTests.swift`; register in `SpotdrawTests/main.swift`
    - **Property 9: Text bounds are non-degenerate and monotonic in font size**
    - Hand-rolled harness now; port to PropertyBased after the target split
    - **Validates: Requirements 1.12**

- [x] 6. Checkpoint — text annotation
  - Run all three checkpoint commands; preservation suite must remain 13/13
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 7. Select, move, and delete

  - [ ] 7.1 Implement `SelectionManager` and give `DrawingState` ownership of it
    - New file `Spotdraw/Core/SelectionManager.swift`; add a symlink under `SpotdrawTests/`
    - Implement `selectedIDs`, `contains`, `set`, `toggle`, `insert`, `remove`, `clear`, `boundingBox(in:)`, `itemsIntersecting(_:in:)`, and `topmostHit(at:threshold:in:)` iterating items in reverse so later items win
    - `Spotdraw/Core/DrawingState.swift`: add `let selection = SelectionManager()`, an `activeTool` `didSet` that clears the selection whenever the new tool is not `.select`, selection pruning inside the shared item-removal helper, plus `removeSelected()` and `selectAll()`
    - Selection lives on `DrawingState`, not `OverlayView`, because a single `DrawingState` instance is shared across every per-screen view
    - _Requirements: 2.10, 2.12, 2.14, 3.7, 10.8_

  - [ ] 7.2 Implement `SelectionRenderer`
    - New file `Spotdraw/Overlay/SelectionRenderer.swift`; add a symlink under `SpotdrawTests/`
    - Draw the dashed marquee rectangle and the dashed per-item selection outlines
    - _Requirements: 2.6, 2.11_

  - [ ] 7.3 Add the `.select` tool case and widen the affected switches
    - `Spotdraw/Core/DrawingState.swift`: add `case select` to `ToolType`
    - `Spotdraw/Overlay/OverlayView.swift`: add `.select` arms to `drawCurrentItem`, `mouseDown`, `mouseDragged`, `mouseUp`
    - _Requirements: 2.1_

  - [ ] 7.4 Implement click and shift-click selection in `OverlayView`
    - Click on a hit resolves to the single topmost matching item; click on empty space with no modifiers clears the selection
    - Shift-click computes the symmetric difference: adds an unselected item, removes a selected one, leaving all other membership unchanged
    - _Requirements: 2.4, 2.5, 2.8, 2.9_

  - [ ] 7.5 Implement marquee selection
    - Dragging from a point that hits nothing while the selection is empty renders the dashed marquee spanning press point and current point
    - On drag end, set the selection to every item whose `bounds` intersect the marquee. A zero-size marquee selects nothing, which needs no special case
    - _Requirements: 2.6, 2.7_

  - [ ] 7.6 Implement move drag with clamping and the undo threshold
    - Dragging from inside the selection bounding box translates every selected item, redrawing on each `mouseDragged`
    - Clamp the applied translation so at least 20 points of the selection bounding box remain inside the view bounds, including for arbitrarily large deltas
    - On drag end, record exactly one `.move` operation when the larger absolute axis component is at least 1 point, and record nothing below that threshold. Retain the selection in both cases
    - _Requirements: 3.2, 3.3, 3.4, 3.9, 3.10, 3.11_

  - [ ] 7.7 Implement delete-selection and select-all
    - Delete removes every selected item and records one `.remove` operation carrying the original indices; undo restores each at its original index
    - Empty selection with a delete keystroke is a no-op that records nothing
    - Use provisional literal key handling in `OverlayView.keyDown` (Delete, Command+A); phase 6 replaces it with `ShortcutStore` resolution
    - _Requirements: 2.10, 3.7, 3.8_

  - [ ] 7.8 Wire selection lifecycle and draw ordering
    - `Spotdraw/Overlay/OverlayView.swift`: render board background, then items, then marquee and selection outlines on top
    - Clear the selection when the overlay deactivates
    - _Requirements: 2.11, 2.13, 2.15, 10.7_

  - [ ] 7.9* Write the property test for marquee exactness
    - New file `SpotdrawTests/SelectionPropertyTests.swift`; register in `SpotdrawTests/main.swift`
    - **Property 10: Marquee selection is exact**
    - Hand-rolled harness now; port to PropertyBased after the target split
    - **Validates: Requirements 2.6, 2.7**

  - [ ] 7.10* Write the property test for click selection
    - Extend `SpotdrawTests/SelectionPropertyTests.swift`
    - **Property 11: Click selection resolves to the topmost hit**
    - Hand-rolled harness now; port to PropertyBased after the target split
    - **Validates: Requirements 2.4, 2.5**

  - [ ] 7.11* Write the property test for shift-click
    - Extend `SpotdrawTests/SelectionPropertyTests.swift`
    - **Property 12: Shift-click computes symmetric difference**
    - Hand-rolled harness now; port to PropertyBased after the target split
    - **Validates: Requirements 2.8, 2.9**

  - [ ] 7.12* Write the property test for selection staleness
    - Extend `SpotdrawTests/SelectionPropertyTests.swift`; reuse the operation-sequence generator from task 1.8
    - **Property 13: Selection never contains a stale identifier** — across add, erase, delete-selection, undo, redo, clear-all, fade removal, select-all, and tool changes
    - Hand-rolled harness now; port to PropertyBased after the target split
    - **Validates: Requirements 2.10, 2.12, 2.14, 10.8**

  - [ ] 7.13* Write the property test for move clamping
    - Extend `SpotdrawTests/SelectionPropertyTests.swift`
    - **Property 14: Move clamping preserves a minimum visible area**
    - Hand-rolled harness now; port to PropertyBased after the target split
    - **Validates: Requirements 3.9**

  - [ ] 7.14* Write the property test for the move undo threshold
    - Extend `SpotdrawTests/SelectionPropertyTests.swift`
    - **Property 15: Move records an undo entry exactly at the threshold**
    - Hand-rolled harness now; port to PropertyBased after the target split
    - **Validates: Requirements 3.4, 3.10, 3.11, 3.7**

- [ ] 8. Checkpoint — select, move, delete
  - Run all three checkpoint commands; preservation suite must remain 13/13
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 9. Zoom wiring

  - [ ] 9.1 Persist zoom level and bubble size
    - `Spotdraw/Core/SettingsManager.swift`: add `zoomLevel` clamped to 2.0…4.0 defaulting to 2.0, and `zoomBubbleSize` clamped to 100…300 defaulting to 200
    - _Requirements: 5.1, 5.2_

  - [ ] 9.2 Gate zoom activation on Screen Recording permission with an injectable probe
    - `Spotdraw/Cursor/CursorManager.swift`: add a screen-recording probe stored as a closure defaulting to `CGPreflightScreenCaptureAccess`, so the denial path is testable without manipulating system TCC state
    - When the probe reports absent, present an alert offering a button that opens the System Settings Screen Recording pane and leave `isZoomActive` false. Do not call `CGRequestScreenCaptureAccess()` on this path
    - Apply the persisted zoom level and bubble size before `show()`
    - _Requirements: 4.7, 5.3_

  - [ ] 9.3 Implement zoom level stepping
    - `Spotdraw/Cursor/CursorManager.swift`: add `zoomIn()`, `zoomOut()`, and `updateZoomAppearance()`
    - Step by 0.5 and persist; clamping to 2.0…4.0 is already enforced by `ZoomWindow.zoomLevel`'s property observer, so saturation needs no new logic
    - Apply changed values to the `ZoomWindow` before the next captured frame
    - _Requirements: 5.4, 5.5, 5.6, 5.7, 5.9_

  - [ ] 9.4 Manage zoom lifecycle and the shared global mouse monitor
    - `Spotdraw/Cursor/CursorManager.swift`: install the global mouse monitor if and only if at least one of cursor highlight, spotlight, or zoom is active; update the `ZoomWindow` position on cursor movement while zoom is active
    - Add `shutdown()` that stops the capture timer and releases the window, and call it from `applicationWillTerminate` in `Spotdraw/App/AppDelegate.swift`
    - Keep zoom independent of overlay activation — no cross-wiring
    - _Requirements: 4.3, 4.8, 4.10, 4.11, 10.13_

  - [ ] 9.5 Make the zoom toggle reachable
    - `Spotdraw/App/AppDelegate.swift`: register a handler that invokes `CursorManager.toggleZoom()` using a provisional Control+M binding; phase 6 moves this to `ShortcutStore`
    - `Spotdraw/MenuBar/MenuBarController.swift`: add a zoom toggle menu item and set its state to on while zoom is active, off while inactive
    - _Requirements: 4.1, 4.4, 4.5, 4.6_

  - [ ] 9.6 Add the Zoom section to the settings window
    - `Spotdraw/Settings/SettingsWindowController.swift`: add a Zoom section to the Cursor tab with a zoom level control spanning 2.0…4.0 and a bubble size control spanning 100…300 points
    - _Requirements: 5.8_

  - [ ] 9.7 Write unit tests for zoom wiring and bubble resizing
    - New file `SpotdrawTests/ZoomUnitTests.swift`; register in `SpotdrawTests/main.swift`
    - Assert a handler is registered for the zoom toggle action and invoking it flips `isZoomActive` — the direct assertion that the reported dead-code bug is fixed
    - Assert `ZoomWindow.bubbleSize` changes resize the window, the circular mask path, and the border ring path
    - Assert menu item state mirrors zoom active, and exercise the denial path through the injected probe stub
    - _Requirements: 4.1, 4.6, 4.7, 5.10_

  - [ ] 9.8* Write the property test for settings clamping
    - New file `SpotdrawTests/ZoomPropertyTests.swift`; register in `SpotdrawTests/main.swift`
    - **Property 23: Settings accessors clamp to their documented ranges** — text font size, zoom level, bubble size, highlight size, stroke width, glow radius
    - Hand-rolled harness now; port to PropertyBased after the target split
    - **Validates: Requirements 1.13, 5.1, 5.2**

  - [ ] 9.9* Write the property test for zoom stepping saturation
    - Extend `SpotdrawTests/ZoomPropertyTests.swift`
    - **Property 24: Zoom level stepping saturates at its bounds**
    - Hand-rolled harness now; port to PropertyBased after the target split
    - **Validates: Requirements 5.3, 5.4, 5.5, 5.6, 5.7, 5.9, 5.10**

  - [ ] 9.10* Write the property test for global mouse monitor lifetime
    - Extend `SpotdrawTests/ZoomPropertyTests.swift`; must run on the main actor with `NSApplication.shared` initialized, following the existing `SpotdrawTests/main.swift` pattern
    - **Property 25: The global mouse monitor lives exactly as long as it is needed**
    - Hand-rolled harness now; port to PropertyBased after the target split
    - **Validates: Requirements 10.13, 4.3, 4.4**

- [ ] 10. Checkpoint — zoom wiring
  - Run all three checkpoint commands; preservation suite must remain 13/13
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 11. Customizable shortcuts

  - [ ] 11.1 Implement the shortcut model and default binding table
    - New file `Spotdraw/Core/ShortcutStore.swift`; add a symlink under `SpotdrawTests/`
    - Define `ShortcutScope`, `ShortcutCategory` (Global, Annotation Tools, Colors, Actions), `KeyBinding` (key code plus modifier raw value, with `cgEventFlags` and `displayString`), and `ShortcutAction` with `String` raw values as persistence keys so later additions cannot invalidate stored bindings
    - Cover every action in Requirements 6.1–6.4: the eight global toggles, all nine tools including text and select, the five colors, and the eight overlay actions
    - Encode the full default table from the design, preserving Control+D, Control+S, Control+L, Control+Shift+S and the existing single-character tool, color, board, and fade bindings
    - **Zoom defaults are Control+M, Control+=, and Control+-. Control+Z must not be a global default** — the tap consumes matched events session-wide and Control+Z is `SIGTSTP` in every shell
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.14, 4.2_

  - [ ] 11.2 Implement store resolution, conflicts, and persistence
    - `Spotdraw/Core/ShortcutStore.swift`: implement `binding(for:)`, `resolve(keyCode:modifiers:scope:)` over a per-scope reverse index rebuilt on each mutation, `conflictingAction(for:excluding:)`, `assign`, `clear`, `reset`, `resetAll`, and `didChangeNotification`
    - Distinguish "absent, use default" from "explicitly cleared" with a `StoredBinding { cleared: Bool, binding: KeyBinding? }` sentinel record
    - Persist as JSON-encoded `[String: StoredBinding]` under a single `UserDefaults` key through `SettingsManager`
    - Uniqueness is enforced within a dispatch scope only, which is what lets overlay tool keys stay unmodified single characters. Note the requirements document attributes this to 6.2; the constraint is actually stated in 4.2 and the implementation follows 4.2
    - Corrupt or undecodable data must fall back to defaults without trapping and log the affected action; unknown action keys are ignored
    - _Requirements: 6.6, 6.7, 6.8, 6.9, 6.10, 6.12, 6.13, 7.7, 7.8, 7.9, 7.12, 7.13, 7.14_

  - [ ] 11.3 Rewire `HotkeyManager` onto the store
    - `Spotdraw/Core/HotkeyManager.swift`: delete the `GlobalShortcut` enum; resolve tap events via `ShortcutStore.shared.resolve(..., scope: .global)` and dispatch through a `[ShortcutAction: () -> Void]` map, returning `nil` to consume on a match
    - **Remove the local `NSEvent` monitor entirely.** It currently double-dispatches with the tap; with the store in place every global shortcut would fire twice while a SpotDraw window is key. The tap already covers the key-window case
    - Add `nonisolated(unsafe) var isRecordingSuppressed`, checked in the callback immediately after the tap-disabled handling, returning the event unchanged when set
    - Preserve the `.tapDisabledByTimeout` / `.tapDisabledByUserInput` re-enable path verbatim, and the existing behavior of logging and staying inert when tap creation fails
    - Treat `isRecordingSuppressed` as advisory: clear it whenever the Settings window is not visible, so a stranded flag cannot silently kill global shortcuts
    - _Requirements: 6.9, 6.11, 6.15, 7.16_

  - [ ] 11.4 Rewire `OverlayView.keyDown` onto the store and delete the hardcoded key tables
    - `Spotdraw/Overlay/OverlayView.swift`: after the Editing_State guard, resolve the event with `scope: .overlay` and dispatch the resulting action; fall through to `super.keyDown` on no match. Replace the provisional Delete / Command+A handling from task 7.7 and the hardcoded Control+D and Escape paths
    - `Spotdraw/Core/DrawingState.swift`: delete `ToolType.keyCharacter` and `ColorShortcut.keyCharacter`, retaining `ColorShortcut.color` as the color source for the five color actions. Removing these now — after the text and select tools exist — makes it a single sweep
    - The preservation suite drives `state.activeTool` directly and keeps its own local key table, so the removal does not break it
    - _Requirements: 6.10, 6.13, 10.12_

  - [ ] 11.5 Register every action handler
    - `Spotdraw/App/AppDelegate.swift`: register handlers for all `ShortcutAction` cases, replacing the provisional zoom registration from task 9.5
    - _Requirements: 6.1, 6.4, 4.1_

  - [ ] 11.6 Drive menu titles from the store
    - `Spotdraw/MenuBar/MenuBarController.swift`: build item titles from `ShortcutStore.shared.binding(for:)?.displayString` instead of hardcoded strings, add Text and Select entries to the Tool submenu, and rebuild the menu on `ShortcutStore.didChangeNotification`
    - _Requirements: 4.5, 6.11_

  - [ ] 11.7 Build the Shortcuts settings tab
    - New file `Spotdraw/Settings/ShortcutsSettingsTab.swift`, registered from `Spotdraw/Settings/SettingsWindowController.swift`
    - Group rows under the four category headings; show the action name and either the binding's `displayString` or "None" when cleared; provide record, clear, and reset controls per row plus a reset-all control
    - Use an `NSViewRepresentable` key-capture view for Recording_State, since SwiftUI has no raw-key-capture affordance
    - Reject a zero-modifier candidate for a global action with an explanatory message, retaining the existing assignment
    - On a conflict, name the other action and retain both assignments until the user confirms
    - **Set `HotkeyManager.isRecordingSuppressed` on entering Recording_State and clear it on every exit path — successful capture, Escape, the conflict path, and `onDisappear`.** A stranded flag silently kills all global shortcuts
    - Do not follow the other tabs' snapshot-into-`@State` pattern: observe `didChangeNotification` and re-read, because bindings change from outside this tab
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.10, 7.11, 7.15, 7.16_

  - [ ] 11.8 Write unit tests for the shortcut contract
    - New file `SpotdrawTests/ShortcutUnitTests.swift`; register in `SpotdrawTests/main.swift`
    - Table-driven backward-compatibility assertions: Control+D, Control+S, Control+L, Control+Shift+S, and each historical single-character tool and color binding resolve to their historical actions
    - Assert Control+M, Control+=, Control+- are the zoom defaults and that no global default is Control+Z
    - Assert the four categories partition `ShortcutAction.allCases` with no orphans or duplicates, and that `ToolType.allCases` contains `.text` and `.select` with a one-to-one correspondence to the tool actions
    - Assert Recording_State entry sets `isRecordingSuppressed` and that both Escape and the conflict path clear it
    - _Requirements: 6.14, 6.1, 6.2, 6.3, 6.4, 7.5, 7.10, 7.11, 4.2_

  - [ ] 11.9* Write the property test for binding persistence
    - New file `SpotdrawTests/ShortcutPropertyTests.swift`; register in `SpotdrawTests/main.swift`
    - **Property 16: Binding persistence round-trips** — including cleared markers and defaults. Build a `KeyBinding` generator over plausible key codes and modifier subsets, including the zero-modifier case
    - Hand-rolled harness now; port to PropertyBased after the target split
    - **Validates: Requirements 6.5, 6.6, 6.8**

  - [ ] 11.10* Write the property test for scope uniqueness and conflict exactness
    - Extend `SpotdrawTests/ShortcutPropertyTests.swift`
    - **Property 17: Bindings are unique within a scope and conflict detection is exact**
    - Hand-rolled harness now; port to PropertyBased after the target split
    - **Validates: Requirements 4.2, 7.8, 7.9**

  - [ ] 11.11* Write the property test for assignment and resolution round-tripping
    - Extend `SpotdrawTests/ShortcutPropertyTests.swift`
    - **Property 18: Assignment and resolution round-trip, and cleared actions are unresolvable**
    - Hand-rolled harness now; port to PropertyBased after the target split
    - **Validates: Requirements 6.9, 6.10, 6.11, 6.13, 7.7, 7.12, 7.16**

  - [ ] 11.12* Write the property test for corrupt persisted data
    - Extend `SpotdrawTests/ShortcutPropertyTests.swift`; build an arbitrary-`Data` generator
    - **Property 19: Corrupt persisted data yields defaults without trapping**
    - Hand-rolled harness now; port to PropertyBased after the target split
    - **Validates: Requirements 6.12**

  - [ ] 11.13* Write the property test for reset
    - Extend `SpotdrawTests/ShortcutPropertyTests.swift`
    - **Property 20: Reset restores defaults and is idempotent**
    - Hand-rolled harness now; port to PropertyBased after the target split
    - **Validates: Requirements 7.13, 7.14**

- [ ] 12. Checkpoint — customizable shortcuts
  - Run all three checkpoint commands; preservation suite must remain 13/13
  - Verify by inspection that no global shortcut fires twice now that the local `NSEvent` monitor is gone
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 13. Passthrough and Interactive Mode

  - [ ] 13.1 Implement `PassthroughModifier`
    - New file `Spotdraw/Core/PassthroughModifier.swift`; add a symlink under `SpotdrawTests/`
    - Cases `off`, `rightOption` (default), `rightCommand`, `fn`, with `displayName` and `isHeld(in:)`
    - Detect left/right using the device-dependent bits of the modifier flags raw value: `0x40` for right Option, `0x10` for right Command; Fn uses `NSEvent.ModifierFlags.function`
    - _Requirements: 8.1, 8.2_

  - [ ] 13.2 Observe the passthrough modifier process-wide from `HotkeyManager`
    - `Spotdraw/Core/HotkeyManager.swift`: add `onPassthroughModifierChange: ((Bool) -> Void)?` backed by `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)`
    - Install the monitor only while the overlay is active and tear it down on deactivation, so an inactive overlay costs nothing
    - The monitor must be owned here, not by `OverlayView` — `NSView.flagsChanged` only fires while a SpotDraw window is key, which is never true during passthrough
    - _Requirements: 8.1, 8.2, 8.11, 9.9_

  - [ ] 13.3 Implement the passthrough state machine in `OverlayWindowController`
    - `Spotdraw/Overlay/OverlayWindowController.swift`: add `isPassthrough`, `modifierHeld`, `interactiveModeEnabled`, `setPassthroughModifierHeld(_:)`, and a private `applyMouseAcceptance()`
    - `applyMouseAcceptance()` must be the **sole writer** of `ignoresMouseEvents` and cursor state, deriving everything from `capturesMouse = isActive && (interactiveModeEnabled ? modifierHeld : !modifierHeld)`
    - Call it from `activate()`, `deactivate()`, `setPassthroughModifierHeld(_:)`, the `interactiveModeEnabled` setter, and `rebuildWindows()`. `rebuildWindows()` currently calls `activate()`, which unconditionally sets `ignoresMouseEvents = false`; that becomes a call to the applier so rebuilt windows inherit the current state
    - Deactivating while the modifier is held must set every window to ignore mouse events and remove the indicator
    - Arrow cursor while passing through, crosshair while capturing
    - _Requirements: 8.1, 8.2, 8.8, 8.9, 8.10, 8.12, 9.4, 9.5, 9.6, 9.7_

  - [ ] 13.4 Implement `ModeIndicatorView`
    - New file `Spotdraw/Overlay/ModeIndicatorView.swift`; add a symlink under `SpotdrawTests/`
    - Render a badge reporting whether the overlay captures or passes through mouse input; shown whenever the overlay is active and either Interactive Mode is enabled or the overlay is not capturing
    - Committed items and the board background continue to render in passthrough
    - _Requirements: 8.3, 8.6, 8.7, 9.8_

  - [ ] 13.5 Drain in-flight interaction on entry to passthrough
    - `Spotdraw/Overlay/OverlayView.swift`: expose a drain entry point that commits any in-progress drawing gesture at the current cursor point and commits any open text edit, then reports no gesture and no editing session remain
    - `OverlayWindowController` calls it on each view before entering passthrough
    - Overlay deactivation during an edit also commits, matching the Return and Escape semantics — no path silently discards typed text except the whitespace-only path
    - _Requirements: 8.4, 8.5_

  - [ ] 13.6 Persist and expose Interactive Mode and the modifier choice
    - `Spotdraw/Core/SettingsManager.swift`: add `interactiveModeEnabled` defaulting to false via `bool(forKey:)`, and `passthroughModifier` storing the enum raw value defaulting to `.rightOption`
    - `Spotdraw/Settings/SettingsWindowController.swift`: add a General tab Interactive Mode toggle and a passthrough-modifier picker (Right Option / Right Command / Fn / Off) with an advisory noting macOS may intercept Fn and that some keyboards report it inconsistently
    - _Requirements: 9.1, 9.2_

  - [ ] 13.7 Wire the Interactive Mode toggle through the menu and shortcut
    - `Spotdraw/MenuBar/MenuBarController.swift`: add an Interactive Mode item whose state mirrors the persisted flag
    - `Spotdraw/App/AppDelegate.swift`: wire the `toggleInteractiveMode` action to invert the persisted flag and push the new value into `OverlayWindowController`, and connect `HotkeyManager.onPassthroughModifierChange` to `setPassthroughModifierHeld(_:)`
    - _Requirements: 9.3, 9.7, 9.11_

  - [ ] 13.8* Write the property test for the derived passthrough state
    - New file `SpotdrawTests/PassthroughPropertyTests.swift`; register in `SpotdrawTests/main.swift`. Must run on the main actor with `NSApplication.shared` initialized
    - **Property 21: Passthrough state is a pure function of activation, mode, and modifier** — assert against both the pure derived predicate and the applied window state, so a correct predicate with a broken applier is still caught
    - Hand-rolled harness now; port to PropertyBased after the target split
    - **Validates: Requirements 8.1, 8.2, 8.6, 8.7, 8.8, 8.9, 8.10, 8.12, 9.4, 9.5, 9.6, 9.7, 9.8**

  - [ ] 13.9* Write the property test for the interaction drain
    - Extend `SpotdrawTests/PassthroughPropertyTests.swift`
    - **Property 22: Entering passthrough drains in-flight interaction**
    - Hand-rolled harness now; port to PropertyBased after the target split
    - **Validates: Requirements 8.4, 8.5**

  - [ ] 13.10* Write the property test for model survival across mode changes and rebuilds
    - Extend `SpotdrawTests/PassthroughPropertyTests.swift`
    - **Property 26: Mode changes and rebuilds preserve the model**
    - Hand-rolled harness now; port to PropertyBased after the target split
    - **Validates: Requirements 9.10, 10.10**

- [ ] 14. Final checkpoint
  - Run all three checkpoint commands; preservation suite must remain 13/13 and every property test must pass
  - Confirm `swift run SpotdrawTests` also passes `SpotdrawTests/OverlayDeactivationTests.swift`
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP. Properties 1–5 are deliberately **not** optional: they are the oracle the existing preservation tests lack and they gate task 2.
- All property tests in this plan are written against the existing hand-rolled harness (`SimplePRNG`, `runPreservationTest(_:iterations:_:)`) with a minimum of 100 iterations and a `// Feature: annotation-parity-phase-1, Property N: ...` comment tag. Properties 6–26 carry a port note and migrate to PropertyBased once the follow-up test target lands. Record the failing iteration index when a property fails — it determines the seed and reproduces the case exactly.
- `Package.swift` and `project.yml` are untouched by every task here. The `SpotdrawCore` extraction, the `SpotdrawPropertyTests` target, and the PropertyBased dependency are a **post-Phase-1 follow-up** that must first verify whether SwiftPM accepts nested target paths (`SpotdrawCore` at `path: "Spotdraw"` with `exclude: ["App"]` alongside an executable at `path: "Spotdraw/App"`). If it does not, the split becomes a `Sources/` reshuffle that also rewrites `project.yml`, and the scope is materially different.
- Every new production file must be linked under `SpotdrawTests/` via `scripts/link-test-sources.sh`. Forgetting fails loudly at compile time rather than silently compiling a stale copy.
- **The multi-screen coordinate mismatch must be filed as the opening item of the next phase before this one closes.** Each `OverlayView` uses view-local coordinates while `DrawingState` is shared, so an item drawn on one display also renders at the same local point on every other. It is pre-existing; the select tool makes it more visible without causing it.
- `CGWindowListCreateImage` in `ZoomWindow.captureScreen()` is deprecated in favor of ScreenCaptureKit on macOS 14+. Tracked, not addressed here — a future macOS release may remove it.
- Multi-line text is not supported in Phase 1. `NSTextField` is single-line and Return is the commit gesture.
- `CircleShape.hitTest` divides by `rx * rx` and is a pre-existing division-by-zero hazard for zero-width rects. Bounds computation does not divide, so `untranslatedBounds` is safe. Out of scope, noted.
- Requirement 8 is written against the Fn modifier specifically; the implementation generalizes to a configured modifier with Fn as one selectable option and Right Option as the default. Every Requirement 8 criterion remains satisfiable as written by selecting Fn.
- Manual and integration verification not covered by automated tasks: global shortcut consumption against a foreground text editor, global dispatch while another app is key during passthrough, real screen-capture magnification, and click-through against a real application beneath the overlay on both a built-in and a third-party keyboard.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2", "1.4"] },
    { "id": 2, "tasks": ["1.3"] },
    { "id": 3, "tasks": ["1.5"] },
    { "id": 4, "tasks": ["1.6", "1.7"] },
    { "id": 5, "tasks": ["1.8"] },
    { "id": 6, "tasks": ["1.9", "1.10"] },
    { "id": 7, "tasks": ["1.11"] },
    { "id": 8, "tasks": ["1.12"] },
    { "id": 9, "tasks": ["3.1"] },
    { "id": 10, "tasks": ["3.2"] },
    { "id": 11, "tasks": ["5.1", "5.2"] },
    { "id": 12, "tasks": ["5.3", "5.4"] },
    { "id": 13, "tasks": ["5.5", "5.7"] },
    { "id": 14, "tasks": ["5.6"] },
    { "id": 15, "tasks": ["5.8"] },
    { "id": 16, "tasks": ["5.9"] },
    { "id": 17, "tasks": ["5.10"] },
    { "id": 18, "tasks": ["5.11"] },
    { "id": 19, "tasks": ["7.1", "7.2"] },
    { "id": 20, "tasks": ["7.3"] },
    { "id": 21, "tasks": ["7.4"] },
    { "id": 22, "tasks": ["7.5"] },
    { "id": 23, "tasks": ["7.6"] },
    { "id": 24, "tasks": ["7.7"] },
    { "id": 25, "tasks": ["7.8"] },
    { "id": 26, "tasks": ["7.9"] },
    { "id": 27, "tasks": ["7.10"] },
    { "id": 28, "tasks": ["7.11"] },
    { "id": 29, "tasks": ["7.12"] },
    { "id": 30, "tasks": ["7.13"] },
    { "id": 31, "tasks": ["7.14"] },
    { "id": 32, "tasks": ["9.1"] },
    { "id": 33, "tasks": ["9.2"] },
    { "id": 34, "tasks": ["9.3"] },
    { "id": 35, "tasks": ["9.4"] },
    { "id": 36, "tasks": ["9.5", "9.6"] },
    { "id": 37, "tasks": ["9.7"] },
    { "id": 38, "tasks": ["9.8"] },
    { "id": 39, "tasks": ["9.9"] },
    { "id": 40, "tasks": ["9.10"] },
    { "id": 41, "tasks": ["11.1"] },
    { "id": 42, "tasks": ["11.2"] },
    { "id": 43, "tasks": ["11.3"] },
    { "id": 44, "tasks": ["11.4"] },
    { "id": 45, "tasks": ["11.5", "11.6"] },
    { "id": 46, "tasks": ["11.7"] },
    { "id": 47, "tasks": ["11.8"] },
    { "id": 48, "tasks": ["11.9"] },
    { "id": 49, "tasks": ["11.10"] },
    { "id": 50, "tasks": ["11.11"] },
    { "id": 51, "tasks": ["11.12"] },
    { "id": 52, "tasks": ["11.13"] },
    { "id": 53, "tasks": ["13.1"] },
    { "id": 54, "tasks": ["13.2", "13.6"] },
    { "id": 55, "tasks": ["13.4"] },
    { "id": 56, "tasks": ["13.5"] },
    { "id": 57, "tasks": ["13.3"] },
    { "id": 58, "tasks": ["13.7"] },
    { "id": 59, "tasks": ["13.8"] },
    { "id": 60, "tasks": ["13.9"] },
    { "id": 61, "tasks": ["13.10"] }
  ]
}
```
