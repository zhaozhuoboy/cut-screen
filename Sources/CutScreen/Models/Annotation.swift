import AppKit

enum EditorTool: String, CaseIterable {
    case none
    case rectangle
    case ellipse
    case pencil
    case arrow
    case serial
    case mosaic
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

enum AnnotationKind: Equatable {
    case rectangle(CGRect)
    case ellipse(CGRect)
    case pencil([CGPoint])
    case arrow(start: CGPoint, end: CGPoint)
    case serial(center: CGPoint, number: Int)
    case mosaic([CGPoint])

    var bounds: CGRect {
        switch self {
        case .rectangle(let rect), .ellipse(let rect):
            return rect.standardized
        case .pencil(let points), .mosaic(let points):
            guard let first = points.first else { return .zero }
            return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { partial, point in
                partial.union(CGRect(origin: point, size: .zero))
            }
        case .arrow(let start, let end):
            return CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
        case .serial(let center, _):
            return CGRect(x: center.x - 14, y: center.y - 14, width: 28, height: 28)
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
        case .serial(let center, let number): return .serial(center: move(center), number: number)
        case .mosaic(let points): return .mosaic(points.map(move))
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
