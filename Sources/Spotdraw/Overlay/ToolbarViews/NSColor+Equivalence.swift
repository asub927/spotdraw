// NSColor+Equivalence.swift
// Toolbar color-matching helper: compares two NSColors in deviceRGB within a
// small tolerance, used to light up the active color swatch in the toolbar.

import Cocoa

extension NSColor {
    func isEquivalent(to other: NSColor) -> Bool {
        guard let c1 = self.usingColorSpace(.deviceRGB),
              let c2 = other.usingColorSpace(.deviceRGB) else {
            return false
        }
        let tolerance: CGFloat = 0.01
        return abs(c1.redComponent - c2.redComponent) < tolerance
            && abs(c1.greenComponent - c2.greenComponent) < tolerance
            && abs(c1.blueComponent - c2.blueComponent) < tolerance
            && abs(c1.alphaComponent - c2.alphaComponent) < tolerance
    }
}
