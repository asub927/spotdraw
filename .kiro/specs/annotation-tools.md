# Spec: Annotation Tools

## Requirements

1. Freehand pen tool with smooth stroke rendering (Catmull-Rom interpolation)
2. Shape tools: Arrow, Rectangle, Circle, Line
3. Highlighter tool (semi-transparent, wider strokes)
4. Eraser tool (removes strokes it intersects)
5. All tools support configurable color and stroke width
6. Hold Shift to constrain shapes (square, circle, 45° angles)
7. Undo/redo support for all drawing operations
8. Auto-fade mode: annotations disappear after configurable duration
9. Whiteboard/blackboard mode: opaque background for drawing
10. Clear all annotations with a single action

## Design

### DrawingItem (Protocol)
```swift
protocol DrawingItem {
    var id: UUID { get }
    var color: NSColor { get }
    var lineWidth: CGFloat { get }
    var createdAt: Date { get }
    var opacity: CGFloat { get set }
    func draw(in context: CGContext)
    func hitTest(point: CGPoint, threshold: CGFloat) -> Bool
}
```

### Concrete Types
- `FreehandStroke`: Array of CGPoints with smoothed CGPath
- `ArrowShape`: Start/end points with arrowhead
- `RectangleShape`: Origin + size, optional corner radius
- `CircleShape`: Center + radius (or bounding rect)
- `LineShape`: Start/end points
- `HighlighterStroke`: Like FreehandStroke but with alpha blending

### DrawingTool (Protocol)
```swift
protocol DrawingTool {
    var toolType: ToolType { get }
    func begin(at point: CGPoint, context: DrawingContext)
    func update(to point: CGPoint, context: DrawingContext)
    func end(at point: CGPoint, context: DrawingContext) -> DrawingItem?
}
```

### DrawingState
- `items: [DrawingItem]` — all committed items
- `currentItem: DrawingItem?` — item being drawn (live preview)
- `undoStack: [DrawingItem]` — for redo
- `activeTool: DrawingTool`
- `activeColor: NSColor`
- `activeLineWidth: CGFloat`
- `fadeMode: Bool`
- `fadeDuration: TimeInterval`

### Rendering
- Two-pass rendering in OverlayView.draw():
  1. Draw all committed items
  2. Draw current in-progress item (live preview)
- For fade mode: check each item's age, apply opacity animation, remove when fully faded

## Tasks

- [ ] Define DrawingItem protocol and concrete stroke/shape types
- [ ] Define DrawingTool protocol with begin/update/end lifecycle
- [ ] Implement PenTool with Catmull-Rom smoothing
- [ ] Implement ArrowTool, RectangleTool, CircleTool, LineTool
- [ ] Implement HighlighterTool (alpha-blended wide strokes)
- [ ] Implement EraserTool with hit-testing
- [ ] Implement DrawingState with undo/redo stack
- [ ] Implement Shift-constrain logic for shapes
- [ ] Implement auto-fade timer and opacity animation
- [ ] Implement whiteboard/blackboard background toggle
- [ ] Wire tool switching to keyboard shortcuts (P, A, R, O, L, H, E)
- [ ] Integrate with OverlayView rendering
