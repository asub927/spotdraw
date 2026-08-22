// FeatureState.swift
// Describes which SpotDraw features are currently active so the toolbar can
// show only the relevant sections. Lives in SpotdrawCore so both the app target
// and ToolbarLayout (and its tests) can reference the same type.

import Foundation

public struct FeatureState: Equatable {
    public var annotationActive: Bool
    public var highlightActive: Bool
    public var spotlightActive: Bool
    public var zoomActive: Bool

    public init(annotationActive: Bool, highlightActive: Bool, spotlightActive: Bool, zoomActive: Bool) {
        self.annotationActive = annotationActive
        self.highlightActive = highlightActive
        self.spotlightActive = spotlightActive
        self.zoomActive = zoomActive
    }

    /// True if any feature is active and the panel should be visible.
    public var anyActive: Bool {
        annotationActive || highlightActive || spotlightActive || zoomActive
    }
}
