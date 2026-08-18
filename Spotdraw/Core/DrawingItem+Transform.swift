// DrawingItem+Transform.swift
// Protocol extension applying accumulated translation to any DrawingItem at
// render and hit-test time. Every conforming type's `draw(in:)` and
// `hitTest(point:threshold:)` bodies remain byte-for-byte unchanged; translation
// is layered on top here.
//
// See design.md, Decision 2 ("Move geometry: caller-applied translation offset,
// not mutable geometry") for the full rationale.

import Cocoa

extension DrawingItem {

    /// Bounding rectangle in view coordinates, including `offset`.
    var bounds: CGRect {
        untranslatedBounds.offsetBy(dx: offset.width, dy: offset.height)
    }

    /// Renders with `offset` applied via a context transform.
    ///
    /// Untranslated items — the overwhelming majority — take the fast path
    /// and pay nothing beyond the equality check.
    func render(in context: CGContext) {
        guard offset != .zero else {
            draw(in: context)
            return
        }
        context.saveGState()
        context.translateBy(x: offset.width, y: offset.height)
        draw(in: context)
        context.restoreGState()
    }

    /// Hit-tests in view coordinates by moving the test point into untranslated space.
    func hitTestTranslated(point: CGPoint, threshold: CGFloat) -> Bool {
        let local = CGPoint(x: point.x - offset.width, y: point.y - offset.height)
        return hitTest(point: local, threshold: threshold)
    }

    /// Accumulates a translation into `offset`.
    func translate(by delta: CGSize) {
        offset = CGSize(width: offset.width + delta.width, height: offset.height + delta.height)
    }
}
