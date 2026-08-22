# Design Document: Toolbar Panel Split

## Overview

`ToolbarPanelController.swift` is 1512 lines and 14 types: a panel controller, a ~620-line content view (`UnifiedToolbarContentView`), ten reusable button/swatch/handle views, a `TooltipWindow`, a `FeatureState` model, and a trailing `CGFloat` extension. It is not one deep module — it is a dozen shallow ones sharing a file. Understanding any one section means scrolling past ten unrelated view classes, and the one piece of genuinely testable logic — the ~90-line `computedWidth` arithmetic — is trapped inside a view with no seam.

This design proceeds in two phases:

- **Phase A (split):** relocate the reusable views, the tooltip window, and `FeatureState` into their own files. Pure code motion; no logic changes. This is the "one type per file" cleanup the steering doc asks for and shrinks the controller file to the controller plus the content view.
- **Phase B (deepen):** lift `computedWidth` and the section-visibility ordering into a pure `ToolbarLayout` value type in `SpotdrawCore`, placing the seam at its interface so the arithmetic is testable without an `NSView`.

Phase A is mechanical and low-risk but touches many files; Phase B is where the deepening (and the `STRONG` recommendation) lives. They are separate commits so a bisect stays clean.

## Architecture

### Before (shallow: 14 types, one file)

```
ToolbarPanelController.swift (1512 LOC)
├── TooltipWindow
├── FeatureState
├── ToolbarPanelController        (panel lifecycle, positioning, drag)
├── UnifiedToolbarContentView     (~620 LOC: computedWidth + setupSubviews + buildXSection + handlers)
├── DragHandleView
├── AnnotationColorSwatchButton
├── AnnotationToolIconButton
├── SmallColorSwatchButton
├── LabelButton
├── ShapeIconButton
├── IconButton
├── SeparatorView
├── DismissButtonView
└── extension CGFloat
```

### After Phase A (types split out)

```
Overlay/
├── ToolbarPanelController.swift   (controller + UnifiedToolbarContentView)
├── FeatureState.swift             (moved; → SpotdrawCore in Phase B)
└── ToolbarViews/
    ├── TooltipWindow.swift
    ├── DragHandleView.swift
    ├── IconButton.swift
    ├── ShapeIconButton.swift
    ├── LabelButton.swift
    ├── SmallColorSwatchButton.swift
    ├── AnnotationToolIconButton.swift
    ├── AnnotationColorSwatchButton.swift
    ├── SeparatorView.swift
    └── DismissButtonView.swift
```

### After Phase B (width logic deepened)

```
SpotdrawCore/
├── FeatureState.swift             (moved here so both targets share it)
└── ToolbarLayout.swift            (nonisolated: totalWidth + visibleSections)

Overlay/UnifiedToolbarContentView
    calls ToolbarLayout(features:).totalWidth   ← no inline arithmetic
```

## Components and Interfaces

### FeatureState (moved to SpotdrawCore in Phase B)

Already a clean `Equatable` struct with four `Bool`s and an `anyActive` convenience. Moving it to `SpotdrawCore` lets `ToolbarLayout` and its tests reference it without importing the app target. No shape change.

### ToolbarLayout (new, `Sources/SpotdrawCore/ToolbarLayout.swift`)

A nonisolated value type. The width arithmetic moves verbatim from `UnifiedToolbarContentView.computedWidth`, including every magic constant (swatch 30, tool 36, spacing 6/10, hPadding 16, drag handle 24, dismiss 26, per-section label widths). The constants become named `static` values inside `ToolbarLayout` so tests and the view share one source of truth.

```swift
public enum ToolbarSection: CaseIterable, Equatable {
    case annotation, highlight, spotlight, zoom
}

public struct ToolbarLayout {
    public let features: FeatureState
    public init(features: FeatureState)

    /// Ordered annotation → highlight → spotlight → zoom, filtered to active flags.
    public var visibleSections: [ToolbarSection]

    /// Total panel width for this feature set. Reproduces computedWidth exactly.
    public var totalWidth: CGFloat
}
```

`totalWidth` walks `visibleSections`, adding each section's width plus inter-section separators, wrapped by leading/trailing chrome (padding, drag handle, dismiss button). Keeping section membership and section widths in the same type gives it locality: the "which sections and how wide" question has one home.

### UnifiedToolbarContentView (reduced)

`computedWidth` becomes `ToolbarLayout(features: features).totalWidth`. The `setupSubviews`/`buildXSection` methods stay in the view — they instantiate AppKit subviews and are not pure. Only the width math and section ordering cross the seam.

## Data Models

No change to the drawing model. `FeatureState` relocates but keeps its shape. `ToolbarSection` is a new pure enum consumed by layout and (optionally) by the view when iterating sections.

## Error Handling

`ToolbarLayout` is a total function of `FeatureState`: every combination (including all-false) yields a defined width and section list. No throwing, no optionals.

## Testing Strategy

Tests target `ToolbarLayout` directly, off the main actor, in the existing `SpotdrawTests` harness style (`runAllToolbarLayoutTests()` registered in `main.swift`).

- **Monotonicity**: turning any feature from off to on never decreases `totalWidth`.
- **Chrome floor**: all-inactive `FeatureState` yields the minimum width (leading padding + drag handle + dismiss + trailing padding), matching the old arithmetic for the empty case.
- **Single-section widths**: each one-feature width equals chrome plus exactly that section's contribution (no stray separator, since there is only one section).
- **Section membership**: `visibleSections.contains(.zoom)` iff `features.zoomActive`, and likewise for the other three; order is always annotation → highlight → spotlight → zoom.
- **Regression**: the full existing suite runs unchanged; because Phase A changes no logic and Phase B moves the arithmetic verbatim, the toolbar renders identically.

Verification gate after each phase: `swift build --target Spotdraw` then `swift run SpotdrawTests`, all passing.

## Migration / Sequencing

1. **Phase A**: relocate the ten views + `TooltipWindow` + `FeatureState` into their own files. Build + test. Commit as a pure move.
2. **Phase B**: add `ToolbarLayout` (+ tests) in `SpotdrawCore`, move `FeatureState` there, rewire `computedWidth` to delegate, prove width parity. Build + test. Commit.

Out of scope: `OverlayView` (candidate 1, already done) and the feature-toggle wiring (candidate 3). Magic-number values are moved, not changed.
