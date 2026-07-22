import AppKit

enum AnnotationPainter {
    typealias PointTransform = (CGPoint) -> CGPoint

    static func draw(
        _ annotation: Annotation,
        in context: CGContext,
        transform: PointTransform,
        scale: CGFloat = 1
    ) {
        let color = annotation.style.color.nsColor.cgColor
        let lineWidth = annotation.style.lineWidth * scale
        context.saveGState()
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch annotation.kind {
        case .rectangle(let rect):
            context.stroke(transformed(rect, transform: transform), width: lineWidth)
        case .ellipse(let rect):
            context.strokeEllipse(in: transformed(rect, transform: transform))
        case .pencil(let points):
            stroke(points, context: context, transform: transform)
        case .arrow(let start, let end):
            drawArrow(start: transform(start), end: transform(end), context: context, width: lineWidth)
        case .serial(let center, let number):
            drawSerial(center: transform(center), number: number, context: context, color: annotation.style.color.nsColor, scale: scale)
        case .mosaic:
            break
        }
        context.restoreGState()
    }

    static func mosaicClipPath(
        for annotation: Annotation,
        in context: CGContext,
        transform: PointTransform,
        scale: CGFloat = 1
    ) {
        guard case .mosaic(let points) = annotation.kind, let first = points.first else { return }
        context.beginPath()
        context.move(to: transform(first))
        for point in points.dropFirst() { context.addLine(to: transform(point)) }
        context.setLineWidth(max(12, annotation.style.lineWidth * 5) * scale)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.replacePathWithStrokedPath()
        context.clip()
    }

    static func hitTest(_ annotation: Annotation, point: CGPoint, tolerance: CGFloat = 8) -> Bool {
        annotation.kind.bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
    }

    private static func transformed(_ rect: CGRect, transform: PointTransform) -> CGRect {
        let first = transform(rect.origin)
        let second = transform(CGPoint(x: rect.maxX, y: rect.maxY))
        return CGRect(
            x: min(first.x, second.x),
            y: min(first.y, second.y),
            width: abs(second.x - first.x),
            height: abs(second.y - first.y)
        )
    }

    private static func stroke(_ points: [CGPoint], context: CGContext, transform: PointTransform) {
        guard let first = points.first else { return }
        context.beginPath()
        context.move(to: transform(first))
        for point in points.dropFirst() { context.addLine(to: transform(point)) }
        context.strokePath()
    }

    private static func drawArrow(start: CGPoint, end: CGPoint, context: CGContext, width: CGFloat) {
        context.beginPath()
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = max(12, width * 4)
        let spread = CGFloat.pi / 7
        let left = CGPoint(x: end.x - length * cos(angle - spread), y: end.y - length * sin(angle - spread))
        let right = CGPoint(x: end.x - length * cos(angle + spread), y: end.y - length * sin(angle + spread))
        context.beginPath()
        context.move(to: left)
        context.addLine(to: end)
        context.addLine(to: right)
        context.strokePath()
    }

    private static func drawSerial(
        center: CGPoint,
        number: Int,
        context: CGContext,
        color: NSColor,
        scale: CGFloat
    ) {
        let radius = 14 * scale
        let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fillEllipse(in: circle)

        let text = NSAttributedString(
            string: String(number),
            attributes: [
                .font: NSFont.systemFont(ofSize: 14 * scale, weight: .bold),
                .foregroundColor: color == .white ? NSColor.black : NSColor.white
            ]
        )
        let size = text.size()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        text.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
        NSGraphicsContext.restoreGraphicsState()
    }
}
