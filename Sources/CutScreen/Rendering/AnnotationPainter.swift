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
        case .magnifier(let rect, _):
            context.setShadow(
                offset: CGSize(width: 0, height: -1 * scale),
                blur: 3 * scale,
                color: NSColor.black.withAlphaComponent(0.35).cgColor
            )
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.94).cgColor)
            context.setLineWidth(2 * scale)
            context.strokeEllipse(in: transformed(rect, transform: transform))
        case .pencil(let points):
            stroke(points, context: context, transform: transform)
        case .arrow(let start, let end):
            drawArrow(start: transform(start), end: transform(end), context: context, width: lineWidth)
        case .serial(let center, let number, let text):
            drawSerial(
                center: transform(center),
                number: number,
                note: text,
                context: context,
                color: annotation.style.color.nsColor,
                lineWidth: annotation.style.lineWidth,
                scale: scale
            )
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
        guard case .mosaic(let mosaic) = annotation.kind else { return }
        switch mosaic.shape {
        case .brush(let points):
            guard let first = points.first else { return }
            context.beginPath()
            context.move(to: transform(first))
            for point in points.dropFirst() { context.addLine(to: transform(point)) }
            context.setLineWidth(max(12, annotation.style.lineWidth * 5) * scale)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.replacePathWithStrokedPath()
            context.clip()
        case .rectangle(let rect):
            context.addRect(transformed(rect, transform: transform))
            context.clip()
        }
    }

    static func hitTest(_ annotation: Annotation, point: CGPoint, tolerance: CGFloat = 8) -> Bool {
        let width = annotation.style.lineWidth / 2 + tolerance
        switch annotation.kind {
        case .rectangle(let rect):
            return rect.standardized.insetBy(dx: -width, dy: -width).contains(point)
        case .ellipse(let rect), .magnifier(let rect, _):
            let rect = rect.standardized
            guard rect.width > 0, rect.height > 0 else { return false }
            let rx = rect.width / 2
            let ry = rect.height / 2
            let normalized = hypot((point.x - rect.midX) / rx, (point.y - rect.midY) / ry)
            return normalized <= 1 + width / min(rx, ry)
        case .pencil(let points):
            return path(points, contains: point, tolerance: width)
        case .arrow(let start, let end):
            return distance(from: point, toSegmentFrom: start, to: end) <= width
                || hypot(point.x - end.x, point.y - end.y) <= max(12, annotation.style.lineWidth * 4) + tolerance
        case .serial:
            return annotation.kind.bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .mosaic(let mosaic):
            switch mosaic.shape {
            case .brush(let points):
                return path(points, contains: point, tolerance: max(12, annotation.style.lineWidth * 5) / 2 + tolerance)
            case .rectangle(let rect):
                return rect.standardized.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
            }
        }
    }

    static func transformed(_ rect: CGRect, transform: PointTransform) -> CGRect {
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

    private static func path(_ points: [CGPoint], contains point: CGPoint, tolerance: CGFloat) -> Bool {
        guard let first = points.first else { return false }
        if points.count == 1 { return hypot(point.x - first.x, point.y - first.y) <= tolerance }
        return zip(points, points.dropFirst()).contains { start, end in
            distance(from: point, toSegmentFrom: start, to: end) <= tolerance
        }
    }

    private static func distance(from point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let projection = min(1, max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let closest = CGPoint(x: start.x + projection * dx, y: start.y + projection * dy)
        return hypot(point.x - closest.x, point.y - closest.y)
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
        note: String,
        context: CGContext,
        color: NSColor,
        lineWidth: CGFloat,
        scale: CGFloat
    ) {
        let radius = SerialAnnotationMetrics.radius(lineWidth: lineWidth) * scale
        let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fillEllipse(in: circle)

        let numberText = NSAttributedString(
            string: String(number),
            attributes: [
                .font: NSFont.systemFont(
                    ofSize: SerialAnnotationMetrics.numberFontSize(lineWidth: lineWidth) * scale,
                    weight: .bold
                ),
                .foregroundColor: color == .white ? NSColor.black : NSColor.white
            ]
        )
        let numberSize = numberText.size()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        numberText.draw(at: CGPoint(x: center.x - numberSize.width / 2, y: center.y - numberSize.height / 2))

        if !note.isEmpty {
            let noteText = NSAttributedString(
                string: note,
                attributes: [
                    .font: NSFont.systemFont(
                        ofSize: SerialAnnotationMetrics.noteFontSize(lineWidth: lineWidth) * scale,
                        weight: .medium
                    ),
                    .foregroundColor: color
                ]
            )
            let noteSize = noteText.size()
            noteText.draw(at: CGPoint(
                x: center.x + radius + SerialAnnotationMetrics.noteGap * scale,
                y: center.y - noteSize.height / 2 + SerialAnnotationMetrics.renderedNoteVerticalOffset * scale
            ))
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
