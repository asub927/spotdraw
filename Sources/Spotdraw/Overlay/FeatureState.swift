// FeatureState.swift
// Describes which SpotDraw features are currently active so the toolbar can
// show only the relevant sections.

import Foundation

internal struct FeatureState: Equatable {
    var annotationActive: Bool
    var highlightActive: Bool
    var spotlightActive: Bool
    var zoomActive: Bool

    /// True if any feature is active and the panel should be visible.
    var anyActive: Bool {
        annotationActive || highlightActive || spotlightActive || zoomActive
    }
}
