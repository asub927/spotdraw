// DrawingItems.swift
// Concrete DrawingItem conformances: freehand strokes, arrows, rectangles, circles, and lines.
// Each type stores its geometry, color, and line width, and implements rendering and hit-testing.

import Cocoa

// MARK: - FreehandStroke

public final class FreehandStroke: DrawingItem {
    public let id = UUID()
    public let points: [CGPoint]
    public let color: NSColor
    public let lineWidth: CGFloat
    public let createdAt = Date()
    public var opacity: CGFloat = 1.0
    public let alpha: CGFloat
    public var offset: CGSize = .zero
    public var screenID: CGDirectDisplayID = CGMainDisplayID()

    public init(points: [CGPoint], color: NSColor, lineWidth: CGFloat, alpha: CGFloat = 1.0) {
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
        self.alpha = alpha
    }

    // Cached because `points` can hold hundreds of entries and this is read on
    // every marquee test and every selection-outline draw.
    public lazy var untranslatedBounds: CGRect = {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x
        var minY = first.y, maxY = first.y
        for p in points {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }
        let box = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return box.insetBy(dx: -(lineWidth / 2), dy: -(lineWidth / 2))
    }()

    // Quadratic Bézier smoothing: uses midpoints between consecutive points as
    // curve endpoints, with the original points as control points. This produces
    // a C1-continuous curve that passes near (but not through) the sampled points.
    public func draw(in context: CGContext) {
        guard points.count > 1 else { return }

        let path = CGMutablePath()
        path.move(to: points[0])

        if points.count == 2 {
            path.addLine(to: points[1])
        } else {
            for i in 1..<(points.count - 1) {
                let mid = CGPoint(
                    x: (points[i].x + points[i + 1].x) / 2,
                    y: (points[i].y + points[i + 1].y) / 2
                )
                path.addQuadCurve(to: mid, control: points[i])
            }
            if let lastPoint = points.last {
                path.addLine(to: lastPoint)
            }
        }

        context.saveGState()
        context.setAlpha(opacity * alpha)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    public func hitTest(point: CGPoint, threshold: CGFloat) -> Bool {
        let hitDistance = max(threshold, lineWidth / 2 + 5)
        for p in points {
            let dx = p.x - point.x
            let dy = p.y - point.y
            if dx * dx + dy * dy <= hitDistance * hitDistance {
                return true
            }
        }
        return false
    }
}

// MARK: - ArrowShape

public final class ArrowShape: DrawingItem {
    public let id = UUID()
    public let start: CGPoint
    public let end: CGPoint
    public let color: NSColor
    public let lineWidth: CGFloat
    public let createdAt = Date()
    public var opacity: CGFloat = 1.0
    public var offset: CGSize = .zero
    public var screenID: CGDirectDisplayID = CGMainDisplayID()

    public init(start: CGPoint, end: CGPoint, color: NSColor, lineWidth: CGFloat) {
        self.start = start
        self.end = end
        self.color = color
        self.lineWidth = lineWidth
    }

    public var untranslatedBounds: CGRect {
        let minX = min(start.x, end.x)
        let maxX = max(start.x, end.x)
        let minY = min(start.y, end.y)
        let maxY = max(start.y, end.y)
        let box = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return box.insetBy(dx: -(lineWidth * 2), dy: -(lineWidth * 2))
    }

    public func draw(in context: CGContext) {
        context.saveGState()
        context.setAlpha(opacity)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)

        // Draw line
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        // Draw arrowhead
        let headLength: CGFloat = lineWidth * 4
        let headAngle: CGFloat = .pi / 6
        let angle = atan2(end.y - start.y, end.x - start.x)

        let point1 = CGPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)
        )
        let point2 = CGPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)
        )

        context.setFillColor(color.cgColor)
        context.move(to: end)
        context.addLine(to: point1)
        context.addLine(to: point2)
        context.closePath()
        context.fillPath()

        context.restoreGState()
    }

    public func hitTest(point: CGPoint, threshold: CGFloat) -> Bool {
        lineSegmentHitTest(point: point, start: start, end: end, threshold: threshold)
    }
}

// MARK: - RectangleShape

public final class RectangleShape: DrawingItem {
    public let id = UUID()
    public let rect: CGRect
    public let color: NSColor
    public let lineWidth: CGFloat
    public let createdAt = Date()
    public var opacity: CGFloat = 1.0
    public var offset: CGSize = .zero
    public var screenID: CGDirectDisplayID = CGMainDisplayID()

    public init(rect: CGRect, color: NSColor, lineWidth: CGFloat) {
        self.rect = rect
        self.color = color
        self.lineWidth = lineWidth
    }

    public var untranslatedBounds: CGRect {
        rect.insetBy(dx: -(lineWidth / 2), dy: -(lineWidth / 2))
    }

    public func draw(in context: CGContext) {
        context.saveGState()
        context.setAlpha(opacity)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.stroke(rect)
        context.restoreGState()
    }

    // Expand/contract approach: checks if the point is within an expanded rect
    // (outside boundary) but NOT within a contracted rect (inside boundary),
    // effectively testing proximity to the rect's border.
    public func hitTest(point: CGPoint, threshold: CGFloat) -> Bool {
        let expanded = rect.insetBy(dx: -(threshold + lineWidth), dy: -(threshold + lineWidth))
        let inner = rect.insetBy(dx: threshold + lineWidth, dy: threshold + lineWidth)
        return expanded.contains(point) && !inner.contains(point)
    }
}

// MARK: - CircleShape

public final class CircleShape: DrawingItem {
    public let id = UUID()
    public let rect: CGRect
    public let color: NSColor
    public let lineWidth: CGFloat
    public let createdAt = Date()
    public var opacity: CGFloat = 1.0
    public var offset: CGSize = .zero
    public var screenID: CGDirectDisplayID = CGMainDisplayID()

    public init(rect: CGRect, color: NSColor, lineWidth: CGFloat) {
        self.rect = rect
        self.color = color
        self.lineWidth = lineWidth
    }

    public var untranslatedBounds: CGRect {
        rect.insetBy(dx: -(lineWidth / 2), dy: -(lineWidth / 2))
    }

    public func draw(in context: CGContext) {
        context.saveGState()
        context.setAlpha(opacity)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.strokeEllipse(in: rect)
        context.restoreGState()
    }

    // Normalized distance check: maps the point into ellipse space where the
    // ellipse boundary is at distance 1.0, then checks if the normalized distance
    // falls within the threshold band around the boundary.
    public func hitTest(point: CGPoint, threshold: CGFloat) -> Bool {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let rx = rect.width / 2
        let ry = rect.height / 2
        let dx = point.x - center.x
        let dy = point.y - center.y
        let normalizedDist = (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry)
        let outerThreshold = ((rx + threshold) * (rx + threshold)) / (rx * rx)
        let innerThreshold = ((rx - threshold) * (rx - threshold)) / (rx * rx)
        return normalizedDist <= outerThreshold && normalizedDist >= innerThreshold
    }
}

// MARK: - LineShape

public final class LineShape: DrawingItem {
    public let id = UUID()
    public let start: CGPoint
    public let end: CGPoint
    public let color: NSColor
    public let lineWidth: CGFloat
    public let createdAt = Date()
    public var opacity: CGFloat = 1.0
    public var offset: CGSize = .zero
    public var screenID: CGDirectDisplayID = CGMainDisplayID()

    public init(start: CGPoint, end: CGPoint, color: NSColor, lineWidth: CGFloat) {
        self.start = start
        self.end = end
        self.color = color
        self.lineWidth = lineWidth
    }

    public var untranslatedBounds: CGRect {
        let minX = min(start.x, end.x)
        let maxX = max(start.x, end.x)
        let minY = min(start.y, end.y)
        let maxY = max(start.y, end.y)
        let box = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return box.insetBy(dx: -(lineWidth / 2), dy: -(lineWidth / 2))
    }

    public func draw(in context: CGContext) {
        context.saveGState()
        context.setAlpha(opacity)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
        context.restoreGState()
    }

    public func hitTest(point: CGPoint, threshold: CGFloat) -> Bool {
        lineSegmentHitTest(point: point, start: start, end: end, threshold: threshold)
    }
}
