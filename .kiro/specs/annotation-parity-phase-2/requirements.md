# Requirements Document: Annotation Parity Phase 2

## Introduction

Phase 1 closed five capability gaps (text annotation, select/move/delete, zoom activation, customizable shortcuts, passthrough/interactive mode) and passed all 78 tests. Phase 2 addresses the technical debt and feature gaps that Phase 1 explicitly deferred:

1. **Multi-screen coordinate mismatch** — the most user-visible issue, flagged as "opening item"
2. **SpotdrawCore library extraction + PropertyBased test target** — project structure improvement
3. **CGWindowListCreateImage → ScreenCaptureKit migration** — API deprecation
4. **Multi-line text support** — feature gap in the text annotation tool

## Requirements

### Requirement 1: Multi-Screen Coordinate Fix

**User Story:** As a user with multiple displays, I want annotations to appear only on the display where I drew them, not duplicated on every screen.

**Context:** Each `OverlayView` uses view-local coordinates while `DrawingState` is shared across all displays. An item drawn on one display renders at the same local point on every other display. The select tool makes this more visible because the selection bounding box appears on all screens.

#### Acceptance Criteria

1. WHEN the user draws an annotation on one display, THE annotation SHALL render only on that display.
2. WHEN the user selects items on one display, THE selection outlines SHALL render only on the display where those items exist.
3. EACH Drawing_Item SHALL store a screen identity or global coordinate that associates it with the display where it was created.
4. WHEN a display is disconnected, annotations associated with that display SHALL migrate to the primary display.
5. WHEN a display is reconnected, annotations SHALL remain on the display where they currently render (no automatic migration back).
6. THE existing preservation test suite (13/13) SHALL continue to pass after this change.
7. ALL existing keyboard shortcuts, undo/redo, fade, board mode, and clear-all SHALL continue to function correctly across all displays.

### Requirement 2: SpotdrawCore Library Extraction

**User Story:** As a developer, I want the core drawing model separated from the application layer, so that tests compile faster and the architecture is clearer.

**Context:** Currently all production code lives in a single executable target. The test target compiles production sources via symlinks. A proper library target would allow the test target to import it directly.

#### Acceptance Criteria

1. A new SwiftPM library target `SpotdrawCore` SHALL contain all model, protocol, and utility files from `Spotdraw/Core/`, `Spotdraw/Overlay/` (model-only files), and `Spotdraw/Cursor/` (model-only files).
2. The `Spotdraw` executable target SHALL depend on `SpotdrawCore`.
3. THE `SpotdrawTests` executable target SHALL depend on `SpotdrawCore` directly rather than via symlinks for core files.
4. IF SwiftPM does not accept nested target paths (`SpotdrawCore` at `path: "Spotdraw"` with `exclude: ["App"]` alongside an executable at `path: "Spotdraw/App"`), THEN a `Sources/` directory reshuffle SHALL be performed.
5. `project.yml` SHALL be updated to match the new directory structure.
6. All 78+ existing tests SHALL continue to pass after the extraction.

### Requirement 3: PropertyBased Test Target

**User Story:** As a developer, I want property tests to use a real property-based testing library, so that shrinking and replay work automatically.

**Context:** Phase 1 wrote 26 property tests against a hand-rolled harness (`SimplePRNG`, `runPreservationTest`). Properties 6–26 carry a port note to migrate to PropertyBased.

#### Acceptance Criteria

1. A new SwiftPM test target `SpotdrawPropertyTests` SHALL be created with the PropertyBased package dependency.
2. Properties 6–26 SHALL be ported from the hand-rolled harness to PropertyBased generators and assertions.
3. Properties 1–5 MAY remain on the hand-rolled harness (they gate Phase 1 and are proven stable).
4. THE ported tests SHALL exercise the same invariants as the originals.
5. Failing property tests SHALL produce a minimal shrunk counterexample.

### Requirement 4: ScreenCaptureKit Migration

**User Story:** As a developer, I want to use the supported screen capture API, so that the zoom feature continues to work on future macOS versions.

**Context:** `ZoomWindow.captureScreen()` uses `CGWindowListCreateImage` which is deprecated on macOS 14+ in favor of ScreenCaptureKit.

#### Acceptance Criteria

1. `ZoomWindow.captureScreen()` SHALL use ScreenCaptureKit (`SCScreenshotManager` or `SCStream`) on macOS 14 and later.
2. On macOS 13 and earlier, THE existing `CGWindowListCreateImage` path SHALL be retained as a fallback.
3. THE zoom bubble SHALL continue to exclude its own window from captures.
4. Screen Recording permission behavior SHALL remain unchanged (gate on `CGPreflightScreenCaptureAccess`, alert on denial).
5. THE zoom level, bubble size, and cursor-following behavior SHALL be unchanged.

### Requirement 5: Multi-Line Text Support

**User Story:** As a presenter, I want to type multi-line text annotations, so that I can write longer notes and explanations on screen.

**Context:** Phase 1 uses a single-line `NSTextField` with Return as the commit gesture. Multi-line requires `NSTextView` and a different commit mechanism.

#### Acceptance Criteria

1. THE text editing field SHALL support multiple lines of text.
2. PRESSING Return SHALL insert a newline within the text (not commit).
3. PRESSING Escape SHALL commit the text annotation (same as Phase 1).
4. PRESSING Command+Return SHALL commit the text annotation as an alternative to Escape.
5. CLICKING outside the text field SHALL commit the text annotation.
6. THE committed TextAnnotation SHALL render all lines with appropriate line spacing.
7. THE TextAnnotation bounding rectangle SHALL encompass all rendered lines.
8. DOUBLE-CLICKING an existing multi-line TextAnnotation SHALL enter editing with all lines preserved.
9. THE existing single-line text behavior (from Phase 1) SHALL continue to work for single-line inputs.
10. THE font size setting SHALL apply uniformly to all lines.

## Priority Order

1. Multi-screen coordinate fix (most user-visible, flagged as "opening item")
2. Multi-line text support (feature gap users will notice)
3. SpotdrawCore extraction + PropertyBased (developer experience, no user impact)
4. ScreenCaptureKit migration (future-proofing, no immediate user impact)

## Open Questions for Design

1. **Screen identity storage.** Should items store a screen `CGDirectDisplayID`, an index, or the screen's frame at creation time? Display IDs persist across reconnections but indices shift.
2. **Multi-line commit gesture.** Is Escape intuitive for committing? Should there be a visible "Done" button on the text field? Consider that Escape currently also deactivates the overlay when not editing.
3. **ScreenCaptureKit permission model.** SCK uses the same Screen Recording TCC entry as CGWindowListCreateImage — verify no additional permission prompt is needed.
4. **PropertyBased library choice.** Is the `PropertyBased` package still maintained, or should we evaluate alternatives like `SwiftCheck` or a custom solution?
