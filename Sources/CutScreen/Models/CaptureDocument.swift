import AppKit

@MainActor
final class CaptureDocument {
    private(set) var baseImage: CGImage
    private(set) var pointSize: CGSize
    private(set) var scale: CGFloat
    private(set) var annotations: [Annotation] = []
    private(set) var redoAnnotations: [Annotation] = []

    init(frame: CapturedFrame) {
        baseImage = frame.image
        pointSize = frame.pointSize
        scale = frame.scale
    }

    var canUndo: Bool { !annotations.isEmpty }
    var canRedo: Bool { !redoAnnotations.isEmpty }
    var hasAnnotations: Bool { !annotations.isEmpty }
    var nextSerialNumber: Int {
        let numbers = annotations.compactMap { annotation -> Int? in
            if case .serial(_, let number) = annotation.kind { return number }
            return nil
        }
        return (numbers.max() ?? 0) + 1
    }

    func add(_ annotation: Annotation) {
        annotations.append(annotation)
        redoAnnotations.removeAll()
    }

    func replace(_ annotation: Annotation) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        annotations[index] = annotation
        redoAnnotations.removeAll()
    }

    func remove(id: UUID) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        redoAnnotations.removeAll()
        redoAnnotations.append(annotations.remove(at: index))
    }

    func undo() {
        guard let annotation = annotations.popLast() else { return }
        redoAnnotations.append(annotation)
    }

    func redo() {
        guard let annotation = redoAnnotations.popLast() else { return }
        annotations.append(annotation)
    }

    func replaceBase(with frame: CapturedFrame) {
        baseImage = frame.image
        pointSize = frame.pointSize
        scale = frame.scale
        annotations.removeAll()
        redoAnnotations.removeAll()
    }
}
