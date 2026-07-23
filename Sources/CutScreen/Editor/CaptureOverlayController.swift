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
        onSelectionAdjustmentStateChanged: @escaping (Bool) -> Void,
        onDocumentChanged: @escaping () -> Void,
        onConfirm: @escaping () -> Void,
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
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.acceptsMouseMovedEvents = true
        panel.contentView = overlayView

        super.init(window: panel)
        overlayView.onSelection = { rect in onSelection(display, rect) }
        overlayView.onSelectionAdjusted = onSelectionAdjusted
        overlayView.onSelectionAdjustmentStateChanged = onSelectionAdjustmentStateChanged
        overlayView.onDocumentChanged = onDocumentChanged
        overlayView.onConfirm = onConfirm
        overlayView.onCancel = onCancel
    }

    required init?(coder: NSCoder) { nil }

    func beginEditing(document: CaptureDocument, selectionRect: CGRect) {
        window?.ignoresMouseEvents = false
        window?.isOpaque = true
        window?.backgroundColor = .black
        overlayView.beginEditing(document: document, selectionRect: selectionRect)
        window?.makeKeyAndOrderFront(nil)
    }

    func beginScrollingMask(selectionRect: CGRect) {
        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.ignoresMouseEvents = true
        overlayView.beginScrollingMask(selectionRect: selectionRect)
        window?.orderFrontRegardless()
    }
}

private final class CaptureOverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class CaptureOverlayView: NSView, NSTextFieldDelegate {
    var onSelection: ((CGRect) -> Void)?
    var onSelectionAdjusted: ((CGRect) -> Void)?
    var onSelectionAdjustmentStateChanged: ((Bool) -> Void)?
    var onDocumentChanged: (() -> Void)?
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?

    private enum Mode { case selecting, editing, scrolling }
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
    private var mosaicConfiguration = MosaicConfiguration()
    private var scrollOffsetFromTop: CGFloat = 0
    private var obscuredPreviewImages: [MosaicPreviewKey: NSImage] = [:]
    private var serialTextField: NSTextField?
    private var editingSerialID: UUID?
    private var textAnnotationField: NSTextField?
    private var editingTextAnnotationID: UUID?
    private var selectionAdjustmentIsActive = false
    private var precisionPoint: CGPoint?
    private var precisionColor: CapturedPixelColor?
    private var copiedColorHex: String?
    private var precisionTrackingArea: NSTrackingArea?
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    init(display: CapturedDisplay) {
        self.display = display
        fullImage = NSImage(cgImage: display.image, size: display.pointSize)
        super.init(frame: CGRect(origin: .zero, size: display.pointSize))
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let precisionTrackingArea {
            removeTrackingArea(precisionTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved, .enabledDuringMouseDrag],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        precisionTrackingArea = trackingArea
    }

    var currentSelectionRect: CGRect? { selectionRect }
    var currentDocument: CaptureDocument? { document }

    func beginEditing(document: CaptureDocument, selectionRect: CGRect) {
        dismissInlineTextFields()
        self.document = document
        self.selectionRect = selectionRect
        mode = .editing
        interaction = .none
        hoveredWindowRect = nil
        precisionPoint = nil
        precisionColor = nil
        copiedColorHex = nil
        scrollOffsetFromTop = 0
        obscuredPreviewImages.removeAll()
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    func beginScrollingMask(selectionRect: CGRect) {
        dismissInlineTextFields()
        self.selectionRect = selectionRect
        mode = .scrolling
        interaction = .none
        selectedAnnotationID = nil
        previewAnnotation = nil
        precisionPoint = nil
        precisionColor = nil
        copiedColorHex = nil
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    func setTool(_ tool: EditorTool) {
        commitInlineTextEditing()
        self.tool = tool
        selectedAnnotationID = nil
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    func setStyle(_ style: AnnotationStyle) {
        self.style = style
        guard tool == .text,
              let id = editingTextAnnotationID,
              var annotation = document?.annotations.first(where: { $0.id == id }),
              case .text(let origin, let content, _) = annotation.kind else { return }
        let fontSize = TextAnnotationMetrics.fontSize(lineWidth: style.lineWidth)
        annotation.kind = .text(origin: origin, content: content, fontSize: fontSize)
        annotation.style = style
        document?.replace(annotation)
        updateTextAnnotationFieldAppearance(annotation)
        notifyDocumentChanged()
    }

    func setMosaicConfiguration(_ configuration: MosaicConfiguration) {
        mosaicConfiguration = configuration
    }

    func refreshAppearance() {
        needsDisplay = true
    }

    func undo() {
        commitInlineTextEditing()
        document?.undo()
        selectedAnnotationID = nil
        notifyDocumentChanged()
    }

    func redo() {
        commitInlineTextEditing()
        document?.redo()
        notifyDocumentChanged()
    }

    func deleteSelection() {
        guard let selectedAnnotationID else { return }
        if editingSerialID == selectedAnnotationID { dismissSerialTextField() }
        if editingTextAnnotationID == selectedAnnotationID { dismissTextAnnotationField() }
        document?.remove(id: selectedAnnotationID)
        self.selectedAnnotationID = nil
        notifyDocumentChanged()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if mode == .scrolling {
            drawScrollingMask()
            return
        }

        fullImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)

        NSColor.black.withAlphaComponent(0.52).setFill()
        bounds.fill()

        let focusRect = selectionRect ?? hoveredWindowRect
        guard let focusRect else {
            drawHint("拖拽选择区域，或单击选中窗口")
            drawPrecisionLoupeIfNeeded()
            return
        }

        let cornerRadius = min(
            (mode == .editing ? document?.appearance.cornerRadius ?? 0 : 0) * displayScale,
            min(focusRect.width, focusRect.height) / 2
        )
        let focusPath = cornerRadius > 0
            ? NSBezierPath(roundedRect: focusRect.pixelAligned, xRadius: cornerRadius, yRadius: cornerRadius)
            : NSBezierPath(rect: focusRect.pixelAligned)

        if mode == .editing, let appearance = document?.appearance, appearance.hasShadow {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(appearance.previewShadowOpacity)
            shadow.shadowBlurRadius = appearance.shadowBlurRadius
            shadow.shadowOffset = CGSize(width: 0, height: appearance.shadowOffsetY)
            shadow.set()
            NSColor.black.withAlphaComponent(appearance.previewShadowFillOpacity).setFill()
            focusPath.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        NSGraphicsContext.saveGraphicsState()
        focusPath.addClip()
        if mode == .editing, document != nil {
            if isAdjustingSelection, document?.hasAnnotations == false {
                drawFrozenScreenPreview(in: focusRect)
            } else {
                drawDocument(in: focusRect)
            }
        } else {
            fullImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        }
        NSGraphicsContext.restoreGraphicsState()

        focusPath.lineWidth = selectionRect == nil ? 3 : 2.5
        NSColor.systemGreen.setStroke()
        focusPath.stroke()

        if selectionRect != nil {
            drawSizeLabel(for: focusRect)
            drawSelectionHandles(for: focusRect)
        }
        drawPrecisionLoupeIfNeeded()
    }

    override func mouseEntered(with event: NSEvent) {
        guard mode == .selecting else { return }
        updatePrecisionSelection(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        guard mode == .selecting else { return }
        let point = convert(event.locationInWindow, from: nil)
        updatePrecisionSelection(at: point)
    }

    override func mouseExited(with event: NSEvent) {
        guard shouldShowPrecisionLoupe else { return }
        precisionPoint = nil
        precisionColor = nil
        copiedColorHex = nil
        if mode == .selecting {
            hoveredWindowRect = nil
        }
        needsDisplay = true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if mode == .selecting {
            addCursorRect(bounds, cursor: .crosshair)
            return
        }
        guard mode == .editing, let document, let selectionRect else { return }

        if canAdjustSelection(document: document, selectionRect: selectionRect) {
            for handle in ResizeHandle.allCases {
                addCursorRect(
                    handleRect(handle, selection: selectionRect).insetBy(dx: -5, dy: -5),
                    cursor: resizeCursor(for: handle)
                )
            }
        }

        if let selectedAnnotationID,
           let annotation = document.annotations.first(where: { $0.id == selectedAnnotationID }),
           isResizableAnnotation(annotation) {
            let bounds = annotation.kind.bounds
            let first = documentToView(bounds.origin)
            let second = documentToView(CGPoint(x: bounds.maxX, y: bounds.maxY))
            let viewBounds = CGRect(
                x: min(first.x, second.x),
                y: min(first.y, second.y),
                width: abs(second.x - first.x),
                height: abs(second.y - first.y)
            )
            for handle in ResizeHandle.allCases {
                addCursorRect(
                    handleRect(handle, selection: viewBounds).insetBy(dx: -4, dy: -4),
                    cursor: resizeCursor(for: handle)
                )
            }
        }
    }

    private func drawScrollingMask() {
        guard let selectionRect,
              let context = NSGraphicsContext.current?.cgContext else { return }

        // Keep the original frozen screen outside the selection, exactly like
        // regular capture mode, then punch a transparent hole through which the
        // live source application can scroll. The window ignores mouse events,
        // so trackpad and wheel input reaches the application underneath.
        context.clear(bounds)
        fullImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        NSColor.black.withAlphaComponent(0.52).setFill()
        bounds.fill()

        context.saveGState()
        context.setBlendMode(.clear)
        context.fill(selectionRect.pixelAligned)
        context.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if mode == .editing, event.clickCount == 2, selectionRect?.contains(point) == true {
            commitInlineTextEditing()
            onConfirm?()
            return
        }

        window?.makeFirstResponder(self)

        switch mode {
        case .selecting:
            interaction = .selecting(start: point)
            selectionRect = CGRect(origin: point, size: .zero)
        case .editing:
            beginEditingInteraction(at: point)
        case .scrolling:
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if mode == .selecting {
            updatePrecisionPoint(at: point)
        }
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
            setSelectionAdjustmentActive(true)
            let delta = CGPoint(x: point.x - start.x, y: point.y - start.y)
            var moved = original.offsetBy(dx: delta.x, dy: delta.y)
            if moved.minX < bounds.minX { moved.origin.x = bounds.minX }
            if moved.maxX > bounds.maxX { moved.origin.x = bounds.maxX - moved.width }
            if moved.minY < bounds.minY { moved.origin.y = bounds.minY }
            if moved.maxY > bounds.maxY { moved.origin.y = bounds.maxY - moved.height }
            selectionRect = moved
        case .resizingSelection(let handle, let original, let start):
            setSelectionAdjustmentActive(true)
            updatePrecisionPoint(at: point)
            selectionRect = resizedSelection(original, handle: handle, delta: CGPoint(x: point.x - start.x, y: point.y - start.y))
        case .none:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        defer {
            setSelectionAdjustmentActive(false)
            interaction = .none
            previewAnnotation = nil
            if mode == .editing {
                precisionPoint = nil
                precisionColor = nil
                copiedColorHex = nil
            }
            needsDisplay = true
        }

        switch interaction {
        case .selecting(let start):
            let dragged = hypot(point.x - start.x, point.y - start.y) >= 4
            let selected = dragged
                ? rect(from: start, to: point).intersection(bounds)
                : (hoveredWindowRect ?? display.localCaptureRegion(at: point))
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
        case .movingAnnotation(let id, _, let start):
            let current = viewToDocument(point) ?? start
            if hypot(current.x - start.x, current.y - start.y) < 2,
               let annotation = document?.annotations.first(where: { $0.id == id }) {
                switch annotation.kind {
                case .serial:
                    beginSerialTextEditing(annotation)
                case .text:
                    beginTextAnnotationEditing(annotation)
                default:
                    notifyDocumentChanged()
                }
            } else {
                notifyDocumentChanged()
            }
        case .resizingAnnotation:
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
        if mode == .selecting,
           event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "c" {
            copyCurrentColor()
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

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === serialTextField {
            commitSerialTextEditing()
        } else if field === textAnnotationField {
            commitTextAnnotationEditing()
        }
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:))
            || commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            commitInlineTextEditing()
            return true
        }
        return false
    }

    private func beginSerialTextEditing(_ annotation: Annotation) {
        commitInlineTextEditing()
        guard case .serial(let center, _, let text) = annotation.kind,
              let selectionRect else { return }

        let viewCenter = documentToView(center)
        let markerRadius = SerialAnnotationMetrics.radius(lineWidth: annotation.style.lineWidth) * displayScale
        let fontSize = SerialAnnotationMetrics.noteFontSize(lineWidth: annotation.style.lineWidth) * displayScale
        let height = max(28, fontSize + 9)
        var x = viewCenter.x + markerRadius + SerialAnnotationMetrics.noteGap * displayScale
        var width = min(240, selectionRect.maxX - x - 8)
        if width < 110 {
            x = max(selectionRect.minX + 8, viewCenter.x - 250)
            width = min(220, selectionRect.maxX - x - 8)
        }
        width = max(90, width)
        let minimumY = selectionRect.minY + 6
        let maximumY = max(minimumY, selectionRect.maxY - height - 6)
        let y = min(max(
            minimumY,
            viewCenter.y - height / 2 + SerialAnnotationMetrics.editorVerticalOffset * displayScale
        ), maximumY)

        let field = NSTextField(frame: CGRect(x: x, y: y, width: width, height: height))
        field.stringValue = text
        field.font = .systemFont(
            ofSize: fontSize,
            weight: .medium
        )
        field.textColor = annotation.style.color.nsColor
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.maximumNumberOfLines = 1
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = self
        field.target = self
        field.action = #selector(commitSerialTextFromField(_:))

        serialTextField = field
        editingSerialID = annotation.id
        addSubview(field)
        window?.makeFirstResponder(field)
        if let editor = field.currentEditor() as? NSTextView {
            editor.drawsBackground = false
            editor.backgroundColor = .clear
            editor.insertionPointColor = annotation.style.color.nsColor
            editor.selectedRange = NSRange(location: text.count, length: 0)
        }
    }

    @objc private func commitSerialTextFromField(_ sender: NSTextField) {
        commitSerialTextEditing()
    }

    private func commitSerialTextEditing() {
        guard let field = serialTextField, let id = editingSerialID else { return }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = String(trimmed.prefix(60))
        dismissSerialTextField()

        guard var annotation = document?.annotations.first(where: { $0.id == id }),
              case .serial(let center, let number, _) = annotation.kind else { return }
        annotation.kind = .serial(center: center, number: number, text: text)
        document?.replace(annotation)
        selectedAnnotationID = id
        notifyDocumentChanged()
        window?.makeFirstResponder(self)
    }

    private func dismissSerialTextField() {
        serialTextField?.delegate = nil
        serialTextField?.removeFromSuperview()
        serialTextField = nil
        editingSerialID = nil
    }

    private func beginTextAnnotationEditing(_ annotation: Annotation) {
        commitInlineTextEditing()
        guard case .text(let origin, let content, _) = annotation.kind,
              let selectionRect else { return }

        let viewOrigin = documentToView(origin)
        let fontSize = TextAnnotationMetrics.fontSize(lineWidth: annotation.style.lineWidth) * displayScale
        let height = max(28, fontSize + 10)
        let x = max(selectionRect.minX + 4, viewOrigin.x)
        let width = max(80, min(360, selectionRect.maxX - x - 6))
        let y = min(
            max(selectionRect.minY + 2, viewOrigin.y - (height - fontSize) / 2),
            max(selectionRect.minY + 2, selectionRect.maxY - height - 2)
        )

        let field = NSTextField(frame: CGRect(x: x, y: y, width: width, height: height))
        field.stringValue = content
        field.font = .systemFont(ofSize: fontSize, weight: .medium)
        field.textColor = annotation.style.color.nsColor
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.maximumNumberOfLines = 1
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = self
        field.target = self
        field.action = #selector(commitTextAnnotationFromField(_:))

        textAnnotationField = field
        editingTextAnnotationID = annotation.id
        addSubview(field)
        window?.makeFirstResponder(field)
        if let editor = field.currentEditor() as? NSTextView {
            editor.drawsBackground = false
            editor.backgroundColor = .clear
            editor.insertionPointColor = annotation.style.color.nsColor
            editor.selectedRange = NSRange(location: (content as NSString).length, length: 0)
        }
    }

    @objc private func commitTextAnnotationFromField(_ sender: NSTextField) {
        commitTextAnnotationEditing()
    }

    private func commitTextAnnotationEditing() {
        guard let field = textAnnotationField, let id = editingTextAnnotationID else { return }
        let content = String(
            field.stringValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(120)
        )
        dismissTextAnnotationField()

        guard var annotation = document?.annotations.first(where: { $0.id == id }),
              case .text(let origin, _, let fontSize) = annotation.kind else { return }
        guard !content.isEmpty else {
            document?.discard(id: id)
            selectedAnnotationID = nil
            notifyDocumentChanged()
            window?.makeFirstResponder(self)
            return
        }
        annotation.kind = .text(origin: origin, content: content, fontSize: fontSize)
        document?.replace(annotation)
        selectedAnnotationID = id
        notifyDocumentChanged()
        window?.makeFirstResponder(self)
    }

    private func dismissTextAnnotationField() {
        textAnnotationField?.delegate = nil
        textAnnotationField?.removeFromSuperview()
        textAnnotationField = nil
        editingTextAnnotationID = nil
    }

    private func dismissInlineTextFields() {
        dismissSerialTextField()
        dismissTextAnnotationField()
    }

    private func commitInlineTextEditing() {
        commitSerialTextEditing()
        commitTextAnnotationEditing()
    }

    private func updateTextAnnotationFieldAppearance(_ annotation: Annotation) {
        guard let field = textAnnotationField,
              case .text(let origin, _, _) = annotation.kind,
              let selectionRect else { return }
        let fontSize = TextAnnotationMetrics.fontSize(lineWidth: annotation.style.lineWidth) * displayScale
        let height = max(28, fontSize + 10)
        let viewOrigin = documentToView(origin)
        var frame = field.frame
        frame.size.height = height
        frame.origin.y = min(
            max(selectionRect.minY + 2, viewOrigin.y - (height - fontSize) / 2),
            max(selectionRect.minY + 2, selectionRect.maxY - height - 2)
        )
        field.frame = frame
        field.font = .systemFont(ofSize: fontSize, weight: .medium)
        field.textColor = annotation.style.color.nsColor
        if let editor = field.currentEditor() as? NSTextView {
            editor.insertionPointColor = annotation.style.color.nsColor
        }
    }

    private func beginEditingInteraction(at viewPoint: CGPoint) {
        guard let document, let selectionRect else { return }
        let canAdjustSelection = canAdjustSelection(document: document, selectionRect: selectionRect)

        // Selection handles straddle the border, so they must be tested before
        // requiring the pointer to be inside the selection. They also take
        // priority over the active drawing tool while no annotation exists.
        if canAdjustSelection, let handle = selectionHandle(at: viewPoint) {
            selectedAnnotationID = nil
            interaction = .resizingSelection(handle: handle, original: selectionRect, start: viewPoint)
            updatePrecisionPoint(at: viewPoint)
            resizeCursor(for: handle).set()
            needsDisplay = true
            return
        }

        guard selectionRect.contains(viewPoint), let documentPoint = viewToDocument(viewPoint) else { return }

        if let selectedAnnotationID,
           let selected = document.annotations.first(where: { $0.id == selectedAnnotationID }),
           let handle = annotationHandle(at: viewPoint, annotation: selected) {
            interaction = .resizingAnnotation(id: selected.id, original: selected, handle: handle, start: documentPoint)
            resizeCursor(for: handle).set()
            return
        }

        if let annotation = document.annotations.reversed().first(where: {
            AnnotationPainter.hitTest($0, point: documentPoint)
        }) {
            selectedAnnotationID = annotation.id
            interaction = .movingAnnotation(id: annotation.id, original: annotation, start: documentPoint)
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
            return
        }

        if tool == .none {
            if canAdjustSelection {
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
                kind: .serial(center: documentPoint, number: document.nextSerialNumber, text: ""),
                style: style
            )
            document.add(annotation)
            selectedAnnotationID = annotation.id
            notifyDocumentChanged()
            beginSerialTextEditing(annotation)
            return
        }

        if tool == .text {
            let annotation = Annotation(
                kind: .text(
                    origin: documentPoint,
                    content: "",
                    fontSize: TextAnnotationMetrics.fontSize(lineWidth: style.lineWidth)
                ),
                style: style
            )
            document.add(annotation)
            selectedAnnotationID = annotation.id
            notifyDocumentChanged()
            beginTextAnnotationEditing(annotation)
            return
        }

        interaction = .drawing(start: documentPoint, points: [documentPoint])
        updatePreview(start: documentPoint, current: documentPoint, points: [documentPoint])
    }

    private func drawFrozenScreenPreview(in rect: CGRect) {
        fullImage.draw(
            in: rect,
            from: rect,
            operation: .copy,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.none]
        )
    }

    private func updatePreview(start: CGPoint, current: CGPoint, points: [CGPoint]) {
        let kind: AnnotationKind
        switch tool {
        case .rectangle: kind = .rectangle(rect(from: start, to: current))
        case .ellipse: kind = .ellipse(rect(from: start, to: current))
        case .pencil: kind = .pencil(points)
        case .arrow: kind = .arrow(start: start, end: current)
        case .magnifier:
            kind = .magnifier(rect: rect(from: start, to: current), zoom: 2)
        case .mosaic:
            let shape: MosaicShape = mosaicConfiguration.drawingMode == .brush
                ? .brush(points)
                : .rectangle(rect(from: start, to: current))
            kind = .mosaic(MosaicAnnotation(effect: mosaicConfiguration.effect, shape: shape))
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
        image.draw(in: rect, from: source, operation: .copy, fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.none])

        if document.annotations.contains(where: { if case .mosaic = $0.kind { return true }; return false }) || (previewAnnotation.map { if case .mosaic = $0.kind { return true }; return false } ?? false) {
            drawMosaicAnnotations(document.annotations + [previewAnnotation].compactMap { $0 }, in: rect, source: source)
        }

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let transform: AnnotationPainter.PointTransform = { [weak self] point in
            self?.documentToView(point) ?? .zero
        }
        for annotation in document.annotations where !self.isMosaic(annotation) {
            let displayedAnnotation = annotationForDisplay(annotation)
            if isMagnifier(displayedAnnotation) {
                drawMagnifier(displayedAnnotation, in: context)
            }
            AnnotationPainter.draw(displayedAnnotation, in: context, transform: transform, scale: displayScale)
        }
        if let previewAnnotation, !isMosaic(previewAnnotation) {
            if isMagnifier(previewAnnotation) {
                drawMagnifier(previewAnnotation, in: context)
            }
            AnnotationPainter.draw(previewAnnotation, in: context, transform: transform, scale: displayScale)
        }

        if let selectedAnnotationID,
           editingSerialID != selectedAnnotationID,
           editingTextAnnotationID != selectedAnnotationID,
           let selected = document.annotations.first(where: { $0.id == selectedAnnotationID }) {
            drawAnnotationSelection(selected)
        }
    }

    private func drawMagnifier(
        _ annotation: Annotation,
        in context: CGContext
    ) {
        guard case .magnifier(let lensRect, let zoom) = annotation.kind,
              let document else { return }
        let first = documentToView(lensRect.origin)
        let second = documentToView(CGPoint(x: lensRect.maxX, y: lensRect.maxY))
        let lens = CGRect(
            x: min(first.x, second.x),
            y: min(first.y, second.y),
            width: abs(second.x - first.x),
            height: abs(second.y - first.y)
        )
        let sourcePixelRect = MagnifierGeometry.sourcePixelRect(
            lensRect: lensRect,
            zoom: zoom,
            documentPointSize: document.pointSize,
            imagePixelSize: CGSize(width: document.baseImage.width, height: document.baseImage.height)
        )
        guard lens.width > 1,
              lens.height > 1,
              let magnified = MagnifierImageRenderer.render(
                source: document.baseImage,
                sourcePixelRect: sourcePixelRect,
                targetPixelSize: CGSize(
                    width: lens.width * (window?.backingScaleFactor ?? display.scale),
                    height: lens.height * (window?.backingScaleFactor ?? display.scale)
                ),
                context: ciContext
              ) else { return }
        let magnifiedImage = NSImage(cgImage: magnified, size: lens.size)

        context.saveGState()
        context.addEllipse(in: lens)
        context.clip()
        magnifiedImage.draw(
            in: lens,
            from: .zero,
            operation: .copy,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        context.restoreGState()
    }

    private func drawMosaicAnnotations(_ annotations: [Annotation], in rect: CGRect, source: CGRect) {
        guard let document, let context = NSGraphicsContext.current?.cgContext else { return }
        let transform: AnnotationPainter.PointTransform = { [weak self] point in self?.documentToView(point) ?? .zero }
        for annotation in annotations where isMosaic(annotation) {
            guard case .mosaic(let mosaic) = annotation.kind,
                  let obscuredImage = obscuredPreviewImage(
                    effect: mosaic.effect,
                    lineWidth: annotation.style.lineWidth,
                    document: document
                  ) else { continue }
            context.saveGState()
            AnnotationPainter.mosaicClipPath(for: annotation, in: context, transform: transform, scale: displayScale)
            obscuredImage.draw(
                in: rect,
                from: source,
                operation: .copy,
                fraction: 1,
                respectFlipped: false,
                hints: [.interpolation: mosaic.effect == .pixelate ? NSImageInterpolation.none : .high]
            )
            context.restoreGState()
        }
    }

    private func obscuredPreviewImage(
        effect: MosaicEffect,
        lineWidth: CGFloat,
        document: CaptureDocument
    ) -> NSImage? {
        let key = MosaicPreviewKey(effect: effect, lineWidth: Int(lineWidth.rounded()))
        if let cached = obscuredPreviewImages[key] { return cached }

        let input = CIImage(cgImage: document.baseImage)
        let multiplier: CGFloat = lineWidth <= 2 ? 0.8 : (lineWidth >= 8 ? 1.8 : 1.2)
        let baseAmount = max(6, min(input.extent.width, input.extent.height) / 120)
        let output: CIImage?
        switch effect {
        case .pixelate:
            output = CIFilter(
                name: "CIPixellate",
                parameters: [kCIInputImageKey: input, kCIInputScaleKey: baseAmount * multiplier]
            )?.outputImage?.cropped(to: input.extent)
        case .blur:
            output = CIFilter(
                name: "CIGaussianBlur",
                parameters: [
                    kCIInputImageKey: input.clampedToExtent(),
                    kCIInputRadiusKey: baseAmount * multiplier
                ]
            )?.outputImage?.cropped(to: input.extent)
        }
        guard let output,
              let cgImage = ciContext.createCGImage(output, from: input.extent) else { return nil }
        let image = NSImage(cgImage: cgImage, size: document.pointSize)
        obscuredPreviewImages[key] = image
        return image
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
        if isResizableAnnotation(annotation) {
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

    private func selectionHandle(at point: CGPoint) -> ResizeHandle? {
        guard let selectionRect else { return nil }
        return ResizeHandle.allCases.first { handleRect($0, selection: selectionRect).insetBy(dx: -5, dy: -5).contains(point) }
    }

    private func resizeCursor(for handle: ResizeHandle) -> NSCursor {
        switch handle {
        case .left, .right:
            return .resizeLeftRight
        case .top, .bottom:
            return .resizeUpDown
        case .bottomLeft, .topRight:
            return ResizeHandleCursor.diagonalAscending
        case .bottomRight, .topLeft:
            return ResizeHandleCursor.diagonalDescending
        }
    }

    private func annotationHandle(at point: CGPoint, annotation: Annotation) -> ResizeHandle? {
        if isResizableAnnotation(annotation) {
            let bounds = annotation.kind.bounds
            let first = documentToView(bounds.origin)
            let second = documentToView(CGPoint(x: bounds.maxX, y: bounds.maxY))
            let viewBounds = CGRect(
                x: min(first.x, second.x), y: min(first.y, second.y),
                width: abs(second.x - first.x), height: abs(second.y - first.y)
            )
            return ResizeHandle.allCases.first { handleRect($0, selection: viewBounds).insetBy(dx: -4, dy: -4).contains(point) }
        }
        return nil
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
        case .magnifier(_, let zoom):
            changed.kind = .magnifier(rect: resizedBounds, zoom: zoom)
        case .mosaic(var mosaic):
            if case .rectangle = mosaic.shape {
                mosaic.shape = .rectangle(resizedBounds)
                changed.kind = .mosaic(mosaic)
            }
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
        NSColor.systemGreen.setStroke()
        for handle in ResizeHandle.allCases {
            let rect = handleRect(handle, selection: selection)
            let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            path.fill()
            path.lineWidth = 1.5
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
        return CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
    }

    private func updatePrecisionSelection(at point: CGPoint) {
        guard bounds.contains(point) else {
            precisionPoint = nil
            precisionColor = nil
            copiedColorHex = nil
            hoveredWindowRect = nil
            needsDisplay = true
            return
        }
        if window?.isKeyWindow == false {
            window?.makeKey()
        }
        window?.makeFirstResponder(self)
        hoveredWindowRect = display.localCaptureRegion(at: point)
        updatePrecisionPoint(at: point)
    }

    private func updatePrecisionPoint(at point: CGPoint) {
        let clampedPoint = CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
        let color = display.pixelColor(at: clampedPoint)
        if copiedColorHex != color?.hexString {
            copiedColorHex = nil
        }
        precisionPoint = clampedPoint
        precisionColor = color
        needsDisplay = true
    }

    private func copyCurrentColor() {
        guard let color = precisionColor else { return }
        if PasteboardService().writeString(color.hexString) {
            copiedColorHex = color.hexString
            needsDisplay = true
        }
    }

    private func drawPrecisionLoupeIfNeeded() {
        guard shouldShowPrecisionLoupe,
              let point = precisionPoint,
              let color = precisionColor else { return }

        let cardSize = CGSize(width: 132, height: 110)
        let cardFrame = precisionLoupeFrame(near: point, size: cardSize)
        let cardPath = NSBezierPath(roundedRect: cardFrame, xRadius: 10, yRadius: 10)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.34)
        shadow.shadowBlurRadius = 12
        shadow.shadowOffset = CGSize(width: 0, height: -3)
        shadow.set()
        NSColor(calibratedWhite: 0.98, alpha: 0.97).setFill()
        cardPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.systemGreen.withAlphaComponent(0.88).setStroke()
        cardPath.lineWidth = 1.5
        cardPath.stroke()

        let imageRect = CGRect(
            x: cardFrame.minX + 6,
            y: cardFrame.minY + 32,
            width: 120,
            height: 72
        )
        let sample = precisionSampleGeometry(around: point)
        let imagePath = NSBezierPath(roundedRect: imageRect, xRadius: 6, yRadius: 6)

        NSGraphicsContext.saveGraphicsState()
        imagePath.addClip()
        fullImage.draw(
            in: imageRect,
            from: sample.sourceRect,
            operation: .copy,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.none]
        )
        drawPrecisionGrid(in: imageRect, sample: sample)
        NSGraphicsContext.restoreGraphicsState()

        NSColor.black.withAlphaComponent(0.22).setStroke()
        imagePath.lineWidth = 0.75
        imagePath.stroke()

        let swatch = CGRect(x: cardFrame.minX + 9, y: cardFrame.minY + 9, width: 14, height: 14)
        color.nsColor.setFill()
        NSBezierPath(roundedRect: swatch, xRadius: 3, yRadius: 3).fill()
        NSColor.black.withAlphaComponent(0.22).setStroke()
        let swatchBorder = NSBezierPath(roundedRect: swatch, xRadius: 3, yRadius: 3)
        swatchBorder.lineWidth = 0.75
        swatchBorder.stroke()

        let hexAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.black.withAlphaComponent(0.84)
        ]
        color.hexString.draw(
            at: CGPoint(x: swatch.maxX + 6, y: cardFrame.minY + 8),
            withAttributes: hexAttributes
        )

        let action = copiedColorHex == color.hexString ? "已复制" : "⌘C"
        let actionAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10.5, weight: .medium),
            .foregroundColor: copiedColorHex == color.hexString
                ? NSColor.systemGreen
                : NSColor.black.withAlphaComponent(0.48)
        ]
        let actionSize = action.size(withAttributes: actionAttributes)
        action.draw(
            at: CGPoint(x: cardFrame.maxX - actionSize.width - 9, y: cardFrame.minY + 9),
            withAttributes: actionAttributes
        )
    }

    private func precisionLoupeFrame(near point: CGPoint, size: CGSize) -> CGRect {
        let margin: CGFloat = 10
        let pointerGap: CGFloat = 20
        var x = point.x + pointerGap
        var y = point.y - size.height - pointerGap
        if x + size.width > bounds.maxX - margin {
            x = point.x - size.width - pointerGap
        }
        if y < bounds.minY + margin {
            y = point.y + pointerGap
        }
        x = min(max(bounds.minX + margin, x), max(bounds.minX + margin, bounds.maxX - size.width - margin))
        y = min(max(bounds.minY + margin, y), max(bounds.minY + margin, bounds.maxY - size.height - margin))
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private func precisionSampleGeometry(around point: CGPoint) -> PrecisionSampleGeometry {
        let columns = min(15, max(1, display.image.width))
        let rows = min(9, max(1, display.image.height))
        let scale = max(display.scale, 0.001)
        let pixelX = min(max(0, Int(floor(point.x * scale))), display.image.width - 1)
        let pixelY = min(max(0, Int(floor(point.y * scale))), display.image.height - 1)
        let minimumPixelX = min(max(0, pixelX - columns / 2), display.image.width - columns)
        let minimumPixelY = min(max(0, pixelY - rows / 2), display.image.height - rows)
        return PrecisionSampleGeometry(
            sourceRect: CGRect(
                x: CGFloat(minimumPixelX) / scale,
                y: CGFloat(minimumPixelY) / scale,
                width: CGFloat(columns) / scale,
                height: CGFloat(rows) / scale
            ),
            columns: columns,
            rows: rows,
            selectedColumn: pixelX - minimumPixelX,
            selectedRow: pixelY - minimumPixelY
        )
    }

    private func drawPrecisionGrid(in rect: CGRect, sample: PrecisionSampleGeometry) {
        let columnWidth = rect.width / CGFloat(sample.columns)
        let rowHeight = rect.height / CGFloat(sample.rows)
        let grid = NSBezierPath()
        for column in 1..<sample.columns {
            let x = rect.minX + CGFloat(column) * columnWidth
            grid.move(to: CGPoint(x: x, y: rect.minY))
            grid.line(to: CGPoint(x: x, y: rect.maxY))
        }
        for row in 1..<sample.rows {
            let y = rect.minY + CGFloat(row) * rowHeight
            grid.move(to: CGPoint(x: rect.minX, y: y))
            grid.line(to: CGPoint(x: rect.maxX, y: y))
        }
        NSColor.black.withAlphaComponent(0.13).setStroke()
        grid.lineWidth = 0.5
        grid.stroke()

        let center = CGPoint(
            x: rect.minX + (CGFloat(sample.selectedColumn) + 0.5) * columnWidth,
            y: rect.minY + (CGFloat(sample.selectedRow) + 0.5) * rowHeight
        )
        let marker = NSBezierPath()
        marker.move(to: CGPoint(x: rect.minX, y: center.y))
        marker.line(to: CGPoint(x: rect.maxX, y: center.y))
        marker.move(to: CGPoint(x: center.x, y: rect.minY))
        marker.line(to: CGPoint(x: center.x, y: rect.maxY))
        marker.lineCapStyle = .square
        NSColor.white.withAlphaComponent(0.82).setStroke()
        marker.lineWidth = 1.5
        marker.stroke()
        NSColor.systemGreen.setStroke()
        marker.lineWidth = 0.75
        marker.stroke()
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
        let below = rect.minY - 18
        let y = below >= bounds.minY + 4 ? below : min(bounds.maxY - 18, rect.maxY + 4)
        size.draw(at: CGPoint(x: rect.minX, y: y), withAttributes: attributes)
    }

    private func notifyDocumentChanged() {
        obscuredPreviewImages.removeAll()
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        onDocumentChanged?()
    }

    private func isResizableAnnotation(_ annotation: Annotation) -> Bool {
        switch annotation.kind {
        case .rectangle, .ellipse, .magnifier:
            return true
        case .mosaic(let mosaic):
            if case .rectangle = mosaic.shape { return true }
            return false
        default:
            return false
        }
    }

    private var isAdjustingSelection: Bool {
        switch interaction {
        case .movingSelection, .resizingSelection:
            return true
        default:
            return false
        }
    }

    private var shouldShowPrecisionLoupe: Bool {
        if mode == .selecting { return true }
        if case .resizingSelection = interaction { return true }
        return false
    }

    private func setSelectionAdjustmentActive(_ active: Bool) {
        guard selectionAdjustmentIsActive != active else { return }
        selectionAdjustmentIsActive = active
        onSelectionAdjustmentStateChanged?(active)
    }

    private func canAdjustSelection(document: CaptureDocument, selectionRect: CGRect) -> Bool {
        !document.hasAnnotations
            && abs(document.pointSize.width - selectionRect.width) < 1
            && abs(document.pointSize.height - selectionRect.height) < 1
    }

    private func isMosaic(_ annotation: Annotation) -> Bool {
        if case .mosaic = annotation.kind { return true }
        return false
    }

    private func annotationForDisplay(_ annotation: Annotation) -> Annotation {
        if editingSerialID == annotation.id,
           case .serial(let center, let number, _) = annotation.kind {
            var displayed = annotation
            displayed.kind = .serial(center: center, number: number, text: "")
            return displayed
        }
        if editingTextAnnotationID == annotation.id,
           case .text(let origin, _, let fontSize) = annotation.kind {
            var displayed = annotation
            displayed.kind = .text(origin: origin, content: "", fontSize: fontSize)
            return displayed
        }
        return annotation
    }

    private func isMagnifier(_ annotation: Annotation) -> Bool {
        if case .magnifier = annotation.kind { return true }
        return false
    }

    private func rect(from first: CGPoint, to second: CGPoint) -> CGRect {
        CGRect(
            x: min(first.x, second.x), y: min(first.y, second.y),
            width: abs(second.x - first.x), height: abs(second.y - first.y)
        )
    }
}

private struct PrecisionSampleGeometry {
    let sourceRect: CGRect
    let columns: Int
    let rows: Int
    let selectedColumn: Int
    let selectedRow: Int
}

private struct MosaicPreviewKey: Hashable {
    let effect: MosaicEffect
    let lineWidth: Int
}

@MainActor
private enum ResizeHandleCursor {
    static let diagonalAscending = makeDiagonalCursor(ascending: true)
    static let diagonalDescending = makeDiagonalCursor(ascending: false)

    private static func makeDiagonalCursor(ascending: Bool) -> NSCursor {
        let image = NSImage(size: CGSize(width: 24, height: 24), flipped: false) { _ in
            let path = NSBezierPath()
            if ascending {
                path.move(to: CGPoint(x: 5, y: 5))
                path.line(to: CGPoint(x: 19, y: 19))
                path.move(to: CGPoint(x: 5, y: 5))
                path.line(to: CGPoint(x: 5, y: 10))
                path.move(to: CGPoint(x: 5, y: 5))
                path.line(to: CGPoint(x: 10, y: 5))
                path.move(to: CGPoint(x: 19, y: 19))
                path.line(to: CGPoint(x: 14, y: 19))
                path.move(to: CGPoint(x: 19, y: 19))
                path.line(to: CGPoint(x: 19, y: 14))
            } else {
                path.move(to: CGPoint(x: 5, y: 19))
                path.line(to: CGPoint(x: 19, y: 5))
                path.move(to: CGPoint(x: 5, y: 19))
                path.line(to: CGPoint(x: 5, y: 14))
                path.move(to: CGPoint(x: 5, y: 19))
                path.line(to: CGPoint(x: 10, y: 19))
                path.move(to: CGPoint(x: 19, y: 5))
                path.line(to: CGPoint(x: 14, y: 5))
                path.move(to: CGPoint(x: 19, y: 5))
                path.line(to: CGPoint(x: 19, y: 10))
            }
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.white.withAlphaComponent(0.96).setStroke()
            path.lineWidth = 4
            path.stroke()
            NSColor.black.withAlphaComponent(0.92).setStroke()
            path.lineWidth = 2
            path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: CGPoint(x: 12, y: 12))
    }
}

private extension CGRect {
    var pixelAligned: CGRect {
        // Align every edge independently. Deriving the far edge from a rounded
        // origin plus a rounded size can make a fixed edge jump by one pixel
        // while the opposite edge is being dragged.
        let alignedMinX = floor(minX) + 0.5
        let alignedMinY = floor(minY) + 0.5
        let alignedMaxX = floor(maxX) + 0.5
        let alignedMaxY = floor(maxY) + 0.5
        return CGRect(
            x: alignedMinX,
            y: alignedMinY,
            width: max(0, alignedMaxX - alignedMinX),
            height: max(0, alignedMaxY - alignedMinY)
        )
    }
}
