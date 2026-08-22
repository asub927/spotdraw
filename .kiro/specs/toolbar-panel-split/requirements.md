# Requirements Document

## Introduction

This specification defines the split and deepening of `ToolbarPanelController.swift`, the largest file in the repository (1512 LOC, 14 types). Today it bundles a panel controller, a ~620-line content view, ten bespoke button/swatch/handle view types, a tooltip window, and a `FeatureState` model into one file — violating the project's one-type-per-file and ~400-line conventions. The genuinely valuable, bug-prone, and currently untested logic is the panel width arithmetic (`computedWidth`), a ~90-line pure function of `FeatureState` buried inside a view class.

This spec has two phases. Phase A is a mechanical, behavior-preserving split of the reusable types into their own files. Phase B deepens the width/section logic into a pure, testable `Toolbar_Layout` module in `SpotdrawCore`. Both phases preserve behavior exactly; the existing 90 tests (78 original plus the 12 added by the overlay-gesture-extraction spec) MUST continue to pass.

This spec addresses candidate 2 from the architecture review ("ToolbarPanelController: 15 types in one file").

## Glossary

- **Toolbar_Panel**: The floating non-activating `NSPanel` that shows controls for whichever features are active (`ToolbarPanelController`).
- **Toolbar_Content_View**: The `NSView` (`UnifiedToolbarContentView`) that lays out and owns the per-feature section subviews.
- **Feature_State**: The `Equatable` struct describing which of the four feature pillars (annotation, highlight, spotlight, zoom) are currently active.
- **Toolbar_Section**: One per-feature block of controls in the panel (annotation, highlight, spotlight, or zoom).
- **Toolbar_Layout**: The new pure value type that, given a `Feature_State`, computes the panel's total width and the ordered set of visible sections.
- **Toolbar_View**: Any of the reusable button/swatch/handle subviews (`IconButton`, `ShapeIconButton`, `LabelButton`, `SmallColorSwatchButton`, `AnnotationToolIconButton`, `AnnotationColorSwatchButton`, `DragHandleView`, `SeparatorView`, `DismissButtonView`) and the `TooltipWindow`.

## Requirements

### Requirement 1: Phase A — file split of reusable types

**User Story:** As a maintainer, I want each reusable toolbar view and the tooltip window in its own file, so that the codebase follows the project's one-type-per-file convention and each type is independently navigable.

#### Acceptance Criteria

1. THE Split SHALL move each Toolbar_View type (`IconButton`, `ShapeIconButton`, `LabelButton`, `SmallColorSwatchButton`, `AnnotationToolIconButton`, `AnnotationColorSwatchButton`, `DragHandleView`, `SeparatorView`, `DismissButtonView`) into its own file under `Sources/Spotdraw/Overlay/ToolbarViews/`, named to match the type.
2. THE Split SHALL move `TooltipWindow` into its own file.
3. THE Split SHALL move any file-scoped extension (e.g. the trailing `CGFloat` helper) to the file of the type it most naturally belongs to, or to a dedicated helpers file.
4. THE Split SHALL NOT change the behavior, access level, or public interface of any moved type.
5. WHEN Phase A is complete, THEN `ToolbarPanelController.swift` SHALL contain only `ToolbarPanelController` and, until Phase B moves it, `UnifiedToolbarContentView`, materially reducing its line count from 1512.

### Requirement 2: Phase B — deepen width and section logic into Toolbar_Layout

**User Story:** As a maintainer, I want the panel width arithmetic and section-visibility logic in a pure module, so that "how wide is the panel for a given feature set" and "which sections show" become testable without instantiating an NSView.

#### Acceptance Criteria

1. THE Extraction SHALL introduce a `Toolbar_Layout` value type in `SpotdrawCore` that takes a `Feature_State` and exposes the total panel width and the ordered list of visible Toolbar_Sections.
2. THE Toolbar_Layout SHALL reproduce the existing `computedWidth` arithmetic exactly, including all spacing, padding, separator, swatch, tool, label, and per-section widths, so the panel renders at an identical width for every Feature_State.
3. THE Toolbar_Content_View SHALL obtain its width from `Toolbar_Layout` rather than computing it inline.
4. THE Toolbar_Layout SHALL expose the visible sections in the fixed order annotation → highlight → spotlight → zoom, including only sections whose corresponding Feature_State flag is active.
5. THE Toolbar_Layout SHALL be `@MainActor`-free (nonisolated), containing only value math.
6. WHEN `Feature_State` is required by both the app target and `SpotdrawCore`, THEN `Feature_State` SHALL be moved to `SpotdrawCore` so both can reference the same type.

### Requirement 3: Behavior preservation and verification

**User Story:** As a maintainer, I want proof the toolbar looks and behaves identically, so that the refactor is safe to merge.

#### Acceptance Criteria

1. THE refactor SHALL keep all existing tests passing without modifying their assertions.
2. THE refactor SHALL add property tests for `Toolbar_Layout` proving: total width is non-decreasing as features are activated; the all-inactive state yields the minimum (chrome-only) width; each single-feature width equals base chrome plus that section; and `visibleSections` contains a section if and only if its Feature_State flag is set.
3. WHEN the refactor is complete, THEN `swift build --target Spotdraw` SHALL succeed and `swift run SpotdrawTests` SHALL report all tests passing (existing plus the new Toolbar_Layout tests).
4. THE refactor SHALL NOT change `OverlayView` or the feature-toggle wiring across `AppDelegate`/`CursorManager`/`MenuBarController` (review candidate 3).

### Requirement 4: Sequencing and commit hygiene

**User Story:** As a maintainer, I want the split and the deepening as separate, bisectable commits, so that a regression can be localized.

#### Acceptance Criteria

1. THE work SHALL land Phase A (file split) and Phase B (Toolbar_Layout extraction) as separate commits, each independently building and passing tests.
2. THE Phase A commit SHALL be a pure code move with no logic change, verifiable by the unchanged test results.
3. THE magic-number constants in the width arithmetic (swatch, tool, spacing, padding sizes) SHALL be moved verbatim into `Toolbar_Layout`; any change to their values is out of scope for this spec.
