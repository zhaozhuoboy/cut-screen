import AppKit

enum EditorTool: String, CaseIterable {
    case none
    case rectangle
    case ellipse
    case pencil
    case arrow
    case text
    case serial
    case mosaic
    case magnifier
}

enum AnnotationColor: String, CaseIterable, Codable {
    case red
    case yellow
    case green
    case blue
    case black
    case white

    var nsColor: NSColor {
        switch self {
        case .red: return .systemRed
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .black: return .black
        case .white: return .white
        }
    }
}

struct AnnotationStyle: Equatable, Codable {
    var color: AnnotationColor = .red
    var lineWidth: CGFloat = 4
}

enum SerialAnnotationMetrics {
    static let noteGap: CGFloat = 6
    // AppKit text glyphs are optically lower than their measured bounding box.
    // Keep display and editor offsets separate so the finished note aligns with
    // the marker without moving the inline editor back toward the top edge.
    static let renderedNoteVerticalOffset: CGFloat = 1
    static let editorVerticalOffset: CGFloat = -2

    static func radius(lineWidth: CGFloat) -> CGFloat {
        max(10, 8 + lineWidth * 0.75)
    }

    static func numberFontSize(lineWidth: CGFloat) -> CGFloat {
        max(10, 8 + lineWidth * 0.75)
    }

    static func noteFontSize(lineWidth: CGFloat) -> CGFloat {
        max(14, 12 + lineWidth / 2)
    }
}

enum TextAnnotationMetrics {
    static func fontSize(lineWidth: CGFloat) -> CGFloat {
        if lineWidth <= 2 { return 16 }
        if lineWidth >= 8 { return 36 }
        return 24
    }

    static func size(for text: String, fontSize: CGFloat) -> CGSize {
        let measuredText = text.isEmpty ? " " : text
        let size = (measuredText as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium)
        ])
        return CGSize(width: max(2, ceil(size.width)), height: ceil(size.height))
    }
}

enum MagnifierGeometry {
    static func sourcePixelRect(
        lensRect: CGRect,
        zoom: CGFloat,
        documentPointSize: CGSize,
        imagePixelSize: CGSize
    ) -> CGRect {
        guard zoom > 0,
              documentPointSize.width > 0,
              documentPointSize.height > 0,
              imagePixelSize.width > 0,
              imagePixelSize.height > 0 else { return .zero }

        let lens = lensRect.standardized
        let scaleX = imagePixelSize.width / documentPointSize.width
        let scaleY = imagePixelSize.height / documentPointSize.height
        let sourceWidth = max(1, (lens.width / zoom * scaleX).rounded())
        let sourceHeight = max(1, (lens.height / zoom * scaleY).rounded())
        let centerX = lens.midX * scaleX
        let centerY = (documentPointSize.height - lens.midY) * scaleY
        let maximumX = max(0, imagePixelSize.width - sourceWidth)
        let maximumY = max(0, imagePixelSize.height - sourceHeight)
        let x = min(max(0, (centerX - sourceWidth / 2).rounded()), maximumX)
        let y = min(max(0, (centerY - sourceHeight / 2).rounded()), maximumY)
        return CGRect(x: x, y: y, width: sourceWidth, height: sourceHeight)
    }
}

enum MosaicEffect: String, CaseIterable, Equatable, Hashable {
    case pixelate
    case blur
}

enum MosaicDrawingMode: String, CaseIterable, Equatable {
    case brush
    case rectangle
}

struct MosaicConfiguration: Equatable {
    var effect: MosaicEffect = .pixelate
    var drawingMode: MosaicDrawingMode = .brush
}

enum MosaicShape: Equatable {
    case brush([CGPoint])
    case rectangle(CGRect)

    var bounds: CGRect {
        switch self {
        case .brush(let points):
            guard let first = points.first else { return .zero }
            return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { partial, point in
                partial.union(CGRect(origin: point, size: .zero))
            }
        case .rectangle(let rect):
            return rect.standardized
        }
    }

    func translated(by delta: CGPoint) -> MosaicShape {
        switch self {
        case .brush(let points):
            return .brush(points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) })
        case .rectangle(let rect):
            return .rectangle(rect.offsetBy(dx: delta.x, dy: delta.y))
        }
    }
}

struct MosaicAnnotation: Equatable {
    var effect: MosaicEffect
    var shape: MosaicShape
}

enum AnnotationKind: Equatable {
    case rectangle(CGRect)
    case ellipse(CGRect)
    case pencil([CGPoint])
    case arrow(start: CGPoint, end: CGPoint)
    case text(origin: CGPoint, content: String, fontSize: CGFloat)
    case serial(center: CGPoint, number: Int, text: String)
    case mosaic(MosaicAnnotation)
    case magnifier(rect: CGRect, zoom: CGFloat)

    var bounds: CGRect {
        switch self {
        case .rectangle(let rect), .ellipse(let rect), .magnifier(let rect, _):
            return rect.standardized
        case .pencil(let points):
            guard let first = points.first else { return .zero }
            return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { partial, point in
                partial.union(CGRect(origin: point, size: .zero))
            }
        case .mosaic(let mosaic):
            return mosaic.shape.bounds
        case .arrow(let start, let end):
            return CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
        case .text(let origin, let content, let fontSize):
            return CGRect(origin: origin, size: TextAnnotationMetrics.size(for: content, fontSize: fontSize))
        case .serial(let center, _, let text):
            let marker = CGRect(x: center.x - 12, y: center.y - 12, width: 24, height: 24)
            guard !text.isEmpty else { return marker }
            let noteWidth = min(340, max(46, CGFloat(text.count) * 14 + 18))
            let note = CGRect(
                x: center.x + 18,
                y: center.y - 16 + SerialAnnotationMetrics.renderedNoteVerticalOffset,
                width: noteWidth,
                height: 32
            )
            return marker.union(note)
        }
    }

    func translated(by delta: CGPoint) -> AnnotationKind {
        func move(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x + delta.x, y: point.y + delta.y)
        }
        switch self {
        case .rectangle(let rect): return .rectangle(rect.offsetBy(dx: delta.x, dy: delta.y))
        case .ellipse(let rect): return .ellipse(rect.offsetBy(dx: delta.x, dy: delta.y))
        case .pencil(let points): return .pencil(points.map(move))
        case .arrow(let start, let end): return .arrow(start: move(start), end: move(end))
        case .text(let origin, let content, let fontSize):
            return .text(origin: move(origin), content: content, fontSize: fontSize)
        case .serial(let center, let number, let text):
            return .serial(center: move(center), number: number, text: text)
        case .mosaic(var mosaic):
            mosaic.shape = mosaic.shape.translated(by: delta)
            return .mosaic(mosaic)
        case .magnifier(let rect, let zoom):
            return .magnifier(rect: rect.offsetBy(dx: delta.x, dy: delta.y), zoom: zoom)
        }
    }
}

struct Annotation: Identifiable, Equatable {
    let id: UUID
    var kind: AnnotationKind
    var style: AnnotationStyle

    init(id: UUID = UUID(), kind: AnnotationKind, style: AnnotationStyle) {
        self.id = id
        self.kind = kind
        self.style = style
    }
}
