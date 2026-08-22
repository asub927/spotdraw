// ToolbarLayout.swift
// Pure layout math for the floating toolbar panel: given a FeatureState, computes
// the panel's total width and the ordered list of visible sections.
//
// Extracted verbatim from UnifiedToolbarContentView.computedWidth (see
// .kiro/specs/toolbar-panel-split) so the arithmetic is testable without an
// NSView. The magic-number constants are lifted to named statics but their
// values are unchanged, so the panel renders at an identical width for every
// FeatureState.
//
// Nonisolated: only value math, no AppKit view state.

import CoreGraphics

// MARK: - ToolbarSection

/// One per-feature block of controls in the toolbar, in display order.
public enum ToolbarSection: CaseIterable, Equatable {
    case annotation
    case highlight
    case spotlight
    case zoom
}

// MARK: - ToolbarLayout

public struct ToolbarLayout {

    // MARK: - Constants (moved verbatim from computedWidth)

    private enum K {
        static let hPadding: CGFloat = 16
        static let itemSpacing: CGFloat = 10
        static let dragHandle: CGFloat = 24
        static let dismiss: CGFloat = 26
    }

    public let features: FeatureState

    public init(features: FeatureState) {
        self.features = features
    }

    // MARK: - Visible sections

    /// The sections to show, in the fixed order annotation → highlight → spotlight
    /// → zoom, filtered to those whose FeatureState flag is active.
    public var visibleSections: [ToolbarSection] {
        var result: [ToolbarSection] = []
        if features.annotationActive { result.append(.annotation) }
        if features.highlightActive { result.append(.highlight) }
        if features.spotlightActive { result.append(.spotlight) }
        if features.zoomActive { result.append(.zoom) }
        return result
    }

    // MARK: - Total width

    /// Total panel width for this feature set. Reproduces the original
    /// `computedWidth` arithmetic exactly.
    public var totalWidth: CGFloat {
        let itemSpacing = K.itemSpacing

        var width: CGFloat = K.hPadding // leading padding
        width += K.dragHandle // drag handle
        width += itemSpacing * 2 // spacing after drag handle

        var sectionCount = 0

        if features.annotationActive {
            // 5 swatches + separator + 6 tools
            let swatchesW = CGFloat(5) * 30 + CGFloat(4) * itemSpacing
            let separatorW: CGFloat = 1 + itemSpacing * 2
            let toolsW = CGFloat(6) * 36 + CGFloat(5) * itemSpacing
            width += swatchesW + separatorW + toolsW
            sectionCount += 1
        }

        if features.highlightActive {
            if sectionCount > 0 { width += itemSpacing + 1 + itemSpacing } // separator
            // Label "Highlight" ~40pt + spacing
            width += 50 + itemSpacing
            // 5 small color swatches
            width += CGFloat(5) * 24 + CGFloat(4) * 6
            width += itemSpacing
            // 4 size buttons (S/M/L/XL)
            width += CGFloat(4) * 30 + CGFloat(3) * 6
            width += itemSpacing
            // 4 shape buttons
            width += CGFloat(4) * 30 + CGFloat(3) * 6
            width += itemSpacing
            // Glow button
            width += 20
            sectionCount += 1
        }

        if features.spotlightActive {
            if sectionCount > 0 { width += itemSpacing + 1 + itemSpacing } // separator
            // Label "Spotlight" ~42pt + spacing
            width += 52 + itemSpacing
            // 3 size buttons (S/M/L)
            width += CGFloat(3) * 30 + CGFloat(2) * 6
            width += itemSpacing
            // 3 dim buttons (L/M/D)
            width += CGFloat(3) * 30 + CGFloat(2) * 6
            sectionCount += 1
        }

        if features.zoomActive {
            if sectionCount > 0 { width += itemSpacing + 1 + itemSpacing } // separator
            // Label "Zoom" ~26pt + spacing
            width += 34 + itemSpacing
            // − button + level label + + button
            width += 30 + 6 + 40 + 6 + 30
            width += itemSpacing
            // 3 bubble size buttons (S/M/L)
            width += CGFloat(3) * 30 + CGFloat(2) * 6
            sectionCount += 1
        }

        width += itemSpacing // before dismiss
        width += K.dismiss // dismiss button
        width += K.hPadding // trailing padding

        return width
    }
}
