# Implementation Plan: Toolbar Panel Split

## Overview

Split `ToolbarPanelController.swift` (1512 LOC, 14 types) into one-type-per-file modules and deepen the panel width/section logic into a pure, testable `ToolbarLayout` value type in `SpotdrawCore`. Two independently shippable, separately committed phases: a mechanical file split (Phase A), then the width extraction (Phase B). Behavior-preserving; gated by the existing test suite.

## Tasks

- [ ] 1. Phase A — split reusable types into their own files
  - [ ] 1.1 Move the reusable Toolbar_View types into ToolbarViews/
    - Create `Sources/Spotdraw/Overlay/ToolbarViews/` and move `IconButton`, `ShapeIconButton`, `LabelButton`, `SmallColorSwatchButton`, `AnnotationToolIconButton`, `AnnotationColorSwatchButton`, `DragHandleView`, `SeparatorView`, `DismissButtonView` each into its own file, named to match the type
    - Preserve access levels and interfaces exactly
    - File(s): `Sources/Spotdraw/Overlay/ToolbarViews/*.swift`
    - _Requirements: 1.1, 1.4_

  - [ ] 1.2 Move TooltipWindow and FeatureState to their own files
    - Move `TooltipWindow` to `Sources/Spotdraw/Overlay/ToolbarViews/TooltipWindow.swift`
    - Move `FeatureState` to `Sources/Spotdraw/Overlay/FeatureState.swift` (relocated to SpotdrawCore in Phase B)
    - Relocate the trailing `CGFloat` extension to the type it serves or a helpers file
    - File(s): `Sources/Spotdraw/Overlay/ToolbarViews/TooltipWindow.swift`, `Sources/Spotdraw/Overlay/FeatureState.swift`
    - _Requirements: 1.2, 1.3, 1.4_

  - [ ] 1.3 Verification checkpoint — Phase A
    - Confirm `ToolbarPanelController.swift` now holds only the controller and `UnifiedToolbarContentView`, with a materially lower line count
    - Run `swift build --target Spotdraw`; confirm success
    - Run `swift run SpotdrawTests`; confirm all existing tests still pass (pure move, no logic change)
    - Commit as a standalone "file split" commit
    - _Requirements: 1.5, 3.1, 4.1, 4.2_

- [ ] 2. Phase B — deepen width and section logic into ToolbarLayout
  - [ ] 2.1 Move FeatureState to SpotdrawCore
    - Relocate `FeatureState` to `Sources/SpotdrawCore/FeatureState.swift`, making it `public` as needed
    - Update the app target references
    - File: `Sources/SpotdrawCore/FeatureState.swift`
    - _Requirements: 2.6_

  - [ ] 2.2 Create the ToolbarLayout value type
    - Add nonisolated `enum ToolbarSection` (annotation, highlight, spotlight, zoom) and `struct ToolbarLayout`
    - `init(features:)`, `var visibleSections: [ToolbarSection]` (fixed order, filtered to active flags), `var totalWidth: CGFloat`
    - Port the `computedWidth` arithmetic verbatim; lift the magic constants (swatch 30, tool 36, spacing 6/10, hPadding 16, drag handle 24, dismiss 26, per-section label widths) to named statics
    - File: `Sources/SpotdrawCore/ToolbarLayout.swift`
    - _Requirements: 2.1, 2.2, 2.4, 2.5, 4.3_

  - [ ]* 2.3 Write property tests for ToolbarLayout
    - Monotonicity: turning any feature on never decreases totalWidth
    - Chrome floor: all-inactive FeatureState yields the minimum (chrome-only) width
    - Single-section widths: each one-feature width equals chrome plus that section, no stray separator
    - Membership: visibleSections contains a section iff its flag is set; order is annotation → highlight → spotlight → zoom
    - Register `runAllToolbarLayoutTests()` in `Tests/SpotdrawTests/main.swift`
    - File: `Tests/SpotdrawTests/ToolbarLayoutTests.swift`
    - **Validates: Requirements 2.2, 2.4, 3.2**

  - [ ] 2.4 Rewire UnifiedToolbarContentView to use ToolbarLayout
    - Replace inline `computedWidth` arithmetic with `ToolbarLayout(features: features).totalWidth`
    - Optionally iterate `visibleSections` where the view currently branches on individual flags
    - Leave `setupSubviews`/`buildXSection` (AppKit instantiation) in the view
    - File: `Sources/Spotdraw/Overlay/ToolbarPanelController.swift`
    - _Requirements: 2.3_

  - [ ] 2.5 Verification checkpoint — Phase B
    - Run `swift build --target Spotdraw`; confirm success
    - Run `swift run SpotdrawTests`; confirm existing tests pass plus the new ToolbarLayout tests
    - Commit as a standalone "ToolbarLayout extraction" commit
    - _Requirements: 3.1, 3.3, 4.1_

- [ ] 3. Finalize and confirm scope
  - [ ] 3.1 Confirm file organization and size reduction
    - Verify every reusable view and TooltipWindow is one-type-per-file
    - Verify `ToolbarPanelController.swift` dropped materially from 1512 LOC
    - Verify `ToolbarLayout.swift` and `FeatureState.swift` live in SpotdrawCore
    - _Requirements: 1.5, 2.1, 2.6_

  - [ ] 3.2 Confirm no scope creep
    - Verify `OverlayView` and the AppDelegate/CursorManager/MenuBarController toggle wiring are untouched
    - Run the full `swift run SpotdrawTests` a final time; confirm all pass
    - _Requirements: 3.4, 3.3_
