import AppKit
import CoreImage

@MainActor
final class CaptureOverlayController: NSWindowController {
    let display: CapturedDisplay
    let overlayView: CaptureOverlayView

    init(
        display: CapturedDisplay,
        onSelection: @escaping (CapturedDisplay, CGRect) -> Void,
        onSelectionAdjusted: @escaping (CGRect) -> Void,
        onDocumentChanged: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.display = display
        overlayView = CaptureOverlayView(display: display)
        let panel = CaptureOverlayWindow(
            contentRect: CGRect(origin: .zero, size: display.screenFrame.size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.setFrame(display.screenFrame, display: false)
        panel.level = .screenSaver
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.acceptsMouseMovedEvents = true
        panel.contentView = overlayView

        super.init(window: panel)
        overlayView.onSelection = { rect in onSelection(display, rect) }
        overlayView.onSelectionAdjusted = onSelectionAdjusted
        overlayView.onDocumentChanged = onDocumentChanged
        overlayView.onCancel = onCancel
    }

    required init?(coder: NSCoder) { nil }

    func beginEditing(document: CaptureDocument, selectionRect: CGRect) {
        overlayView.beginEditing(document: document, selectionRect: selectionRect)
        window?.makeKeyAndOrderFront(nil)
    }
}

private final class CaptureOverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class CaptureOverlayView: NSView {
    var onSelection: ((CGRect) -> Void)?
    var onSelectionAdjusted: ((CGRect) -> Void)?
    var onDocumentChanged: (() -> Void)?
    var onCancel: (() -> Void)?

    private enum Mode { case selecting, editing }
    private enum ResizeHandle: CaseIterable { case bottomLeft, bottom, bottomRight, right, topRight, top, topLeft, left }
    private enum Interaction {
        case none
        case selecting(start: CGPoint)
        case drawing(start: CGPoint, points: [CGPoint])
        case movingAnnotation(id: UUID, original: Annotation, start: CGPoint)
        case resizingAnnotation(id: UUID, original: Annotation, handle: ResizeHandle, start: CGPoint)
        case movingSelection(original: CGRect, start: CGPoint)
        case resizingSelection(handle: ResizeHandle, original: CGRect, start: CGPoint)
    }

    private let display: CapturedDisplay
    private let fullImage: NSImage
    private var mode: Mode = .selecting
    private var interaction: Interaction = .none
    private var selectionRect: CGRect?
    private var hoveredWindowRect: CGRect?
    private var document: CaptureDocument?
    private var selectedAnnotationID: UUID?
    private var previewAnnotation: Annotation?
    private var tool: EditorTool = .none
    private var style = AnnotationStyle()
    private var scrollOffsetFromTop: CGFloat = 0
    private var pixelatedImage: NSImage?
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    init(display: CapturedDisplay) {
        self.display = display
        fullImage = NSImage(cgImage: display.image, size: display.pointSize)
        super.init(frame: CGRect(origin: .zero, size: display.pointSize))
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }

    var currentSelectionRect: CGRect? { selectionRect }
    var currentDocument: CaptureDocument? { document }

    func beginEditing(document: CaptureDocument, selectionRect: CGRect) {
        self.document = document
        self.selectionRect = selectionRect
        mode = .editing
        interaction = .none
        hoveredWindowRect = nil
        scrollOffsetFromTop = 0
        pixelatedImage = nil
        needsDisplay = true
    }

    func setTool(_ tool: EditorTool) {
        self.tool = tool
        selectedAnnotationID = nil
        needsDisplay = true
    }

    func setStyle(_ style: AnnotationStyle) {
        self.style = style
    }

    func undo() {
        document?.undo()
        selectedAnnotationID = nil
        notifyDocumentChanged()
    }

    func redo() {
        document?.redo()
        notifyDocumentChanged()
    }

    func deleteSelection() {
        guard let selectedAnnotationID else { return }
        document?.remove(id: selectedAnnotationID)
        self.selectedAnnotationID = nil
        notifyDocumentChanged()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        fullImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)

        NSColor.black.withAlphaComponent(0.52).setFill()
        bounds.fill()

        let focusRect = selectionRect ?? hoveredWindowRect
        guard let focusRect else {
            drawHint("拖拽选择区域，或单击选中窗口")
            return
        }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: focusRect).addClip()
        if mode == .editing, document != nil {
            drawDocument(in: focusRect)
        } else {
            fullImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        }
        NSGraphicsContext.restoreGraphicsState()

        let border = NSBezierPath(rect: focusRect.pixelAligned)
        border.lineWidth = 1
        NSColor.systemBlue.setStroke()
        border.stroke()

        if selectionRect != nil {
            drawSizeLabel(for: focusRect)
            drawSelectionHandles(for: focusRect)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        guard mode == .selecting else { return }
        let point = convert(event.locationInWindow, from: nil)
        hoveredWindowRect = localWindowRect(at: point)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)

        switch mode {
        case .selecting:
            interaction = .selecting(start: point)
            selectionRect = CGRect(origin: point, size: .zero)
        case .editing:
            beginEditingInteraction(at: point)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch interaction {
        case .selecting(let start):
            selectionRect = rect(from: start, to: point).intersection(bounds)
        case .drawing(let start, var points):
            guard let documentPoint = viewToDocument(point) else { return }
            points.append(documentPoint)
            interaction = .drawing(start: start, points: points)
            updatePreview(start: start, current: documentPoint, points: points)
        case .movingAnnotation(let id, let original, let start):
            guard let current = viewToDocument(point) else { return }
            let delta = CGPoint(x: current.x - start.x, y: current.y - start.y)
            var changed = original
            changed.kind = original.kind.translated(by: delta)
            document?.replace(changed)
            selectedAnnotationID = id
        case .resizingAnnotation(let id, let original, let handle, let start):
            guard let current = viewToDocument(point), let document else { return }
            let delta = CGPoint(x: current.x - start.x, y: current.y - start.y)
            let resized = resizedAnnotation(original, handle: handle, delta: delta, documentSize: document.pointSize)
            self.document?.replace(resized)
            selectedAnnotationID = id
        case .movingSelection(let original, let start):
            let delta = CGPoint(x: point.x - start.x, y: point.y - start.y)
            var moved = original.offsetBy(dx: delta.x, dy: delta.y)
            if moved.minX < bounds.minX { moved.origin.x = bounds.minX }
            if moved.maxX > bounds.maxX { moved.origin.x = bounds.maxX - moved.width }
            if moved.minY < bounds.minY { moved.origin.y = bounds.minY }
            if moved.maxY > bounds.maxY { moved.origin.y = bounds.maxY - moved.height }
            selectionRect = moved
        case .resizingSelection(let handle, let original, let start):
            selectionRect = resizedSelection(original, handle: handle, delta: CGPoint(x: point.x - start.x, y: point.y - start.y))
        case .none:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        defer {
            interaction = .none
            previewAnnotation = nil
            needsDisplay = true
        }

        switch interaction {
        case .selecting(let start):
            let dragged = hypot(point.x - start.x, point.y - start.y) >= 4
            let selected = dragged ? rect(from: start, to: point).intersection(bounds) : (hoveredWindowRect ?? CGRect(x: point.x, y: point.y, width: 1, height: 1))
            guard selected.width >= 4, selected.height >= 4 else {
                selectionRect = nil
                return
            }
            selectionRect = selected
            onSelection?(selected)
        case .drawing:
            if let previewAnnotation, previewAnnotation.kind.bounds.width + previewAnnotation.kind.bounds.height >= 3 {
                document?.add(previewAnnotation)
                selectedAnnotationID = previewAnnotation.id
                notifyDocumentChanged()
            }
        case .movingSelection, .resizingSelection:
            if let selectionRect, selectionRect.width >= 8, selectionRect.height >= 8 {
                onSelectionAdjusted?(selectionRect)
            }
        case .movingAnnotation, .resizingAnnotation:
            notifyDocumentChanged()
        case .none:
            break
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard let document, selectionRect != nil, document.pointSize.height > visibleDocumentHeight else {
            super.scrollWheel(with: event)
            return
        }
        let maximum = document.pointSize.height - visibleDocumentHeight
        scrollOffsetFromTop = min(max(0, scrollOffsetFromTop - event.scrollingDeltaY * 2), maximum)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "z" {
            event.modifierFlags.contains(.shift) ? redo() : undo()
            return
        }
        if event.keyCode == 51 || event.keyCode == 117 {
            deleteSelection()
            return
        }
        super.keyDown(with: event)
    }

    private func beginEditingInteraction(at viewPoint: CGPoint) {
        guard let document, let selectionRect, selectionRect.contains(viewPoint), let documentPoint = viewToDocument(viewPoint) else { return }

        if tool == .none {
            if let selectedAnnotationID,
               let selected = document.annotations.first(where: { $0.id == selectedAnnotationID }),
               let handle = annotationHandle(at: viewPoint, annotation: selected) {
                interaction = .resizingAnnotation(id: selected.id, original: selected, handle: handle, start: documentPoint)
                return
            }
            if let annotation = document.annotations.reversed().first(where: { AnnotationPainter.hitTest($0, point: documentPoint) }) {
                selectedAnnotationID = annotation.id
                interaction = .movingAnnotation(id: annotation.id, original: annotation, start: documentPoint)
            } else if !document.hasAnnotations, let handle = selectionHandle(at: viewPoint) {
                interaction = .resizingSelection(handle: handle, original: selectionRect, start: viewPoint)
            } else if !document.hasAnnotations {
                selectedAnnotationID = nil
                interaction = .movingSelection(original: selectionRect, start: viewPoint)
            } else {
                selectedAnnotationID = nil
            }
            needsDisplay = true
            return
        }

        if tool == .serial {
            let annotation = Annotation(
                kind: .serial(center: documentPoint, number: document.nextSerialNumber),
                style: style
            )
            document.add(annotation)
            selectedAnnotationID = annotation.id
            notifyDocumentChanged()
            return
        }

        interaction = .drawing(start: documentPoint, points: [documentPoint])
        updatePreview(start: documentPoint, current: documentPoint, points: [documentPoint])
    }

    private func updatePreview(start: CGPoint, current: CGPoint, points: [CGPoint]) {
        let kind: AnnotationKind
        switch tool {
        case .rectangle: kind = .rectangle(rect(from: start, to: current))
        case .ellipse: kind = .ellipse(rect(from: start, to: current))
        case .pencil: kind = .pencil(points)
        case .arrow: kind = .arrow(start: start, end: current)
        case .mosaic: kind = .mosaic(points)
        default: return
        }
        if let previewAnnotation {
            self.previewAnnotation = Annotation(id: previewAnnotation.id, kind: kind, style: style)
        } else {
            previewAnnotation = Annotation(kind: kind, style: style)
        }
    }

    private func drawDocument(in rect: CGRect) {
        guard let document else { return }
        let source = visibleSourceRect
        let image = NSImage(cgImage: document.baseImage, size: document.pointSize)
        image.draw(in: rect, from: source, operation: .copy, fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])

        if document.annotations.contains(where: { if case .mosaic = $0.kind { return true }; return false }) || (previewAnnotation.map { if case .mosaic = $0.kind { return true }; return false } ?? false) {
            drawMosaicAnnotations(document.annotations + [previewAnnotation].compactMap { $0 }, in: rect, source: source)
        }

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let transform: AnnotationPainter.PointTransform = { [weak self] point in
            self?.documentToView(point) ?? .zero
        }
        for annotation in document.annotations where !self.isMosaic(annotation) {
            AnnotationPainter.draw(annotation, in: context, transform: transform, scale: displayScale)
        }
        if let previewAnnotation, !isMosaic(previewAnnotation) {
            AnnotationPainter.draw(previewAnnotation, in: context, transform: transform, scale: displayScale)
        }

        if let selectedAnnotationID,
           let selected = document.annotations.first(where: { $0.id == selectedAnnotationID }) {
            drawAnnotationSelection(selected)
        }
    }

    private func drawMosaicAnnotations(_ annotations: [Annotation], in rect: CGRect, source: CGRect) {
        guard let document, let context = NSGraphicsContext.current?.cgContext else { return }
        if pixelatedImage == nil {
            let input = CIImage(cgImage: document.baseImage)
            let amount = max(8, min(input.extent.width, input.extent.height) / 120)
            if let output = CIFilter(name: "CIPixellate", parameters: [kCIInputImageKey: input, kCIInputScaleKey: amount])?.outputImage,
               let image = ciContext.createCGImage(output, from: input.extent) {
                pixelatedImage = NSImage(cgImage: image, size: document.pointSize)
            }
        }
        guard let pixelatedImage else { return }
        let transform: AnnotationPainter.PointTransform = { [weak self] point in self?.documentToView(point) ?? .zero }
        for annotation in annotations where isMosaic(annotation) {
            context.saveGState()
            AnnotationPainter.mosaicClipPath(for: annotation, in: context, transform: transform, scale: displayScale)
            pixelatedImage.draw(in: rect, from: source, operation: .copy, fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.none])
            context.restoreGState()
        }
    }

    private func drawAnnotationSelection(_ annotation: Annotation) {
        let bounds = annotation.kind.bounds
        let first = documentToView(bounds.origin)
        let second = documentToView(CGPoint(x: bounds.maxX, y: bounds.maxY))
        let viewBounds = CGRect(
            x: min(first.x, second.x), y: min(first.y, second.y),
            width: abs(second.x - first.x), height: abs(second.y - first.y)
        ).insetBy(dx: -4, dy: -4)
        let path = NSBezierPath(rect: viewBounds)
        path.setLineDash([4, 3], count: 2, phase: 0)
        path.lineWidth = 1
        NSColor.controlAccentColor.setStroke()
        path.stroke()
        if case .rectangle = annotation.kind {
            drawAnnotationHandles(for: viewBounds)
        } else if case .ellipse = annotation.kind {
            drawAnnotationHandles(for: viewBounds)
        }
    }

    private var displayScale: CGFloat {
        guard let selectionRect, let document, document.pointSize.width > 0 else { return 1 }
        return selectionRect.width / document.pointSize.width
    }

    private var visibleDocumentHeight: CGFloat {
        guard let selectionRect else { return 0 }
        return selectionRect.height / max(displayScale, 0.001)
    }

    private var visibleSourceRect: CGRect {
        guard let document else { return .zero }
        let height = min(document.pointSize.height, visibleDocumentHeight)
        let y = max(0, document.pointSize.height - height - scrollOffsetFromTop)
        return CGRect(x: 0, y: y, width: document.pointSize.width, height: height)
    }

    private func viewToDocument(_ point: CGPoint) -> CGPoint? {
        guard let selectionRect, selectionRect.contains(point) else { return nil }
        let source = visibleSourceRect
        return CGPoint(
            x: (point.x - selectionRect.minX) / displayScale,
            y: source.minY + (point.y - selectionRect.minY) / displayScale
        )
    }

    private func documentToView(_ point: CGPoint) -> CGPoint {
        guard let selectionRect else { return .zero }
        let source = visibleSourceRect
        return CGPoint(
            x: selectionRect.minX + point.x * displayScale,
            y: selectionRect.minY + (point.y - source.minY) * displayScale
        )
    }

    private func localWindowRect(at point: CGPoint) -> CGRect? {
        display.windows.first { window in
            let local = window.frame.offsetBy(dx: -display.screenFrame.minX, dy: -display.screenFrame.minY)
            return local.contains(point)
        }.map { $0.frame.offsetBy(dx: -display.screenFrame.minX, dy: -display.screenFrame.minY).intersection(bounds) }
    }

    private func selectionHandle(at point: CGPoint) -> ResizeHandle? {
        guard let selectionRect else { return nil }
        return ResizeHandle.allCases.first { handleRect($0, selection: selectionRect).insetBy(dx: -3, dy: -3).contains(point) }
    }

    private func annotationHandle(at point: CGPoint, annotation: Annotation) -> ResizeHandle? {
        switch annotation.kind {
        case .rectangle, .ellipse:
            let bounds = annotation.kind.bounds
            let first = documentToView(bounds.origin)
            let second = documentToView(CGPoint(x: bounds.maxX, y: bounds.maxY))
            let viewBounds = CGRect(
                x: min(first.x, second.x), y: min(first.y, second.y),
                width: abs(second.x - first.x), height: abs(second.y - first.y)
            )
            return ResizeHandle.allCases.first { handleRect($0, selection: viewBounds).insetBy(dx: -4, dy: -4).contains(point) }
        default:
            return nil
        }
    }

    private func resizedAnnotation(_ annotation: Annotation, handle: ResizeHandle, delta: CGPoint, documentSize: CGSize) -> Annotation {
        let originalBounds = annotation.kind.bounds
        let resizedBounds = resizedRect(originalBounds, handle: handle, delta: delta)
            .intersection(CGRect(origin: .zero, size: documentSize))
        var changed = annotation
        switch annotation.kind {
        case .rectangle:
            changed.kind = .rectangle(resizedBounds)
        case .ellipse:
            changed.kind = .ellipse(resizedBounds)
        default:
            break
        }
        return changed
    }

    private func resizedSelection(_ original: CGRect, handle: ResizeHandle, delta: CGPoint) -> CGRect {
        resizedRect(original, handle: handle, delta: delta).intersection(bounds)
    }

    private func resizedRect(_ original: CGRect, handle: ResizeHandle, delta: CGPoint) -> CGRect {
        var minX = original.minX
        var maxX = original.maxX
        var minY = original.minY
        var maxY = original.maxY
        if [.bottomLeft, .left, .topLeft].contains(handle) { minX += delta.x }
        if [.bottomRight, .right, .topRight].contains(handle) { maxX += delta.x }
        if [.bottomLeft, .bottom, .bottomRight].contains(handle) { minY += delta.y }
        if [.topLeft, .top, .topRight].contains(handle) { maxY += delta.y }
        if maxX - minX < 8 { handle == .left || handle == .topLeft || handle == .bottomLeft ? (minX = maxX - 8) : (maxX = minX + 8) }
        if maxY - minY < 8 { handle == .bottom || handle == .bottomLeft || handle == .bottomRight ? (minY = maxY - 8) : (maxY = minY + 8) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func drawSelectionHandles(for selection: CGRect) {
        NSColor.white.setFill()
        NSColor.systemBlue.setStroke()
        for handle in ResizeHandle.allCases {
            let rect = handleRect(handle, selection: selection)
            let path = NSBezierPath(rect: rect)
            path.fill()
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func drawAnnotationHandles(for selection: CGRect) {
        NSColor.white.setFill()
        NSColor.controlAccentColor.setStroke()
        for handle in ResizeHandle.allCases {
            let rect = handleRect(handle, selection: selection)
            let path = NSBezierPath(ovalIn: rect)
            path.fill()
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func handleRect(_ handle: ResizeHandle, selection: CGRect) -> CGRect {
        let point: CGPoint
        switch handle {
        case .bottomLeft: point = CGPoint(x: selection.minX, y: selection.minY)
        case .bottom: point = CGPoint(x: selection.midX, y: selection.minY)
        case .bottomRight: point = CGPoint(x: selection.maxX, y: selection.minY)
        case .right: point = CGPoint(x: selection.maxX, y: selection.midY)
        case .topRight: point = CGPoint(x: selection.maxX, y: selection.maxY)
        case .top: point = CGPoint(x: selection.midX, y: selection.maxY)
        case .topLeft: point = CGPoint(x: selection.minX, y: selection.maxY)
        case .left: point = CGPoint(x: selection.minX, y: selection.midY)
        }
        return CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)
    }

    private func drawHint(_ text: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }

    private func drawSizeLabel(for rect: CGRect) {
        let size = "\(Int(rect.width * display.scale)) × \(Int(rect.height * display.scale))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.65)
        ]
        size.draw(at: CGPoint(x: rect.minX, y: min(bounds.maxY - 18, rect.maxY + 4)), withAttributes: attributes)
    }

    private func notifyDocumentChanged() {
        pixelatedImage = nil
        needsDisplay = true
        onDocumentChanged?()
    }

    private func isMosaic(_ annotation: Annotation) -> Bool {
        if case .mosaic = annotation.kind { return true }
        return false
    }

    private func rect(from first: CGPoint, to second: CGPoint) -> CGRect {
        CGRect(
            x: min(first.x, second.x), y: min(first.y, second.y),
            width: abs(second.x - first.x), height: abs(second.y - first.y)
        )
    }
}

private extension CGRect {
    var pixelAligned: CGRect {
        CGRect(x: floor(minX) + 0.5, y: floor(minY) + 0.5, width: floor(width), height: floor(height))
    }
}
