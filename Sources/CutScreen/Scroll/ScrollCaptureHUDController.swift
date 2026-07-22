import AppKit

@MainActor
final class ScrollCaptureHUDController {
    private let onSave: () -> Void
    private let onCancel: () -> Void
    private let onFinish: () -> Void
    private let borderWindow: NSPanel
    private let controlWindow: NSPanel
    private let previewWindow: NSPanel
    private let previewScrollView = NSScrollView()
    private let previewImageView = FlippedPreviewImageView()
    private var didRequestAction = false

    init(
        selection: Selection,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onFinish: @escaping () -> Void
    ) {
        self.onSave = onSave
        self.onCancel = onCancel
        self.onFinish = onFinish
        borderWindow = NSPanel(
            contentRect: selection.globalRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        borderWindow.level = .screenSaver
        borderWindow.isOpaque = false
        borderWindow.backgroundColor = .clear
        borderWindow.hidesOnDeactivate = false
        borderWindow.ignoresMouseEvents = true
        borderWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        borderWindow.contentView?.wantsLayer = true
        borderWindow.contentView?.layer?.borderWidth = 2
        borderWindow.contentView?.layer?.borderColor = NSColor.systemGreen.cgColor

        controlWindow = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 122, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        controlWindow.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        controlWindow.isOpaque = false
        controlWindow.backgroundColor = .clear
        controlWindow.hasShadow = true
        controlWindow.hidesOnDeactivate = false
        controlWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let controlContent = GlassToolbarComponents.configure(controlWindow, cornerRadius: 12)

        let previewHeight = min(520, max(280, selection.screenFrame.height - 96))
        previewWindow = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 244, height: previewHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        previewWindow.ignoresMouseEvents = true
        previewWindow.hidesOnDeactivate = false
        let previewContent = GlassToolbarComponents.configure(previewWindow, cornerRadius: 13)

        let save = actionButton(icon: "save", tooltip: "保存长截图", action: #selector(saveCapture))
        let cancel = actionButton(icon: "cancel", tooltip: "取消长截图", action: #selector(cancelCapture))
        let finish = actionButton(icon: "confirm", tooltip: "完成并复制", action: #selector(finishCapture))
        finish.isPrimaryAction = true
        let stack = NSStackView(views: [save, cancel, finish])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        controlContent.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: controlContent.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: controlContent.centerYAnchor)
        ])

        buildPreview(in: previewContent)

        let desiredX = min(
            selection.globalRect.maxX - controlWindow.frame.width,
            selection.screenFrame.maxX - controlWindow.frame.width - 8
        )
        var desiredY = selection.globalRect.maxY + 8
        if desiredY + controlWindow.frame.height > selection.screenFrame.maxY {
            desiredY = selection.globalRect.minY - controlWindow.frame.height - 8
        }
        controlWindow.setFrameOrigin(CGPoint(x: max(selection.screenFrame.minX + 8, desiredX), y: max(selection.screenFrame.minY + 8, desiredY)))

        let previewMargin: CGFloat = 12
        let preferredPreviewX = selection.globalRect.maxX + previewMargin
        let previewX: CGFloat
        if preferredPreviewX + previewWindow.frame.width <= selection.screenFrame.maxX - 8 {
            previewX = preferredPreviewX
        } else if selection.globalRect.minX - previewMargin - previewWindow.frame.width >= selection.screenFrame.minX + 8 {
            previewX = selection.globalRect.minX - previewMargin - previewWindow.frame.width
        } else {
            previewX = selection.screenFrame.maxX - previewWindow.frame.width - 8
        }
        let previewY = min(
            max(selection.globalRect.midY - previewWindow.frame.height / 2, selection.screenFrame.minY + 8),
            selection.screenFrame.maxY - previewWindow.frame.height - 8
        )
        previewWindow.setFrameOrigin(CGPoint(x: previewX, y: previewY))
    }

    func show() {
        borderWindow.orderFrontRegardless()
        controlWindow.orderFrontRegardless()
        previewWindow.orderFrontRegardless()
    }

    func update(result: StitchAppendResult, totalHeight _: Int, preview: CGImage?) {
        if let preview { updatePreviewImage(preview) }
        switch result {
        case .noMatch:
            borderWindow.contentView?.layer?.borderColor = NSColor.systemOrange.cgColor
        case .firstFrame, .duplicate, .appended:
            borderWindow.contentView?.layer?.borderColor = NSColor.systemGreen.cgColor
        case .limitReached:
            requestFinishOnce()
        }
    }

    func close() {
        borderWindow.orderOut(nil)
        controlWindow.orderOut(nil)
        previewWindow.orderOut(nil)
    }

    private func buildPreview(in contentView: NSView) {
        let title = NSTextField(labelWithString: "长截图实时预览")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor

        // The first frame is usually much shorter than the preview viewport.
        // Preserve its aspect ratio and leave the remaining area empty instead
        // of stretching the frame vertically to fill the panel.
        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.imageAlignment = .alignTop
        previewImageView.wantsLayer = true
        previewImageView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        previewScrollView.documentView = previewImageView
        previewScrollView.hasVerticalScroller = false
        previewScrollView.hasHorizontalScroller = false
        previewScrollView.drawsBackground = true
        previewScrollView.backgroundColor = .controlBackgroundColor
        previewScrollView.borderType = .noBorder
        previewScrollView.wantsLayer = true
        previewScrollView.layer?.cornerRadius = 8
        previewScrollView.layer?.cornerCurve = .continuous
        previewScrollView.layer?.masksToBounds = true

        let stack = NSStackView(views: [title, previewScrollView])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            previewScrollView.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func updatePreviewImage(_ image: CGImage) {
        let contentWidth = max(1, previewScrollView.contentSize.width)
        let displayHeight = max(
            previewScrollView.contentSize.height,
            contentWidth * CGFloat(image.height) / CGFloat(image.width)
        )
        previewImageView.image = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
        previewImageView.frame = CGRect(x: 0, y: 0, width: contentWidth, height: displayHeight)
        previewScrollView.layoutSubtreeIfNeeded()
        previewScrollView.contentView.scroll(to: CGPoint(
            x: 0,
            y: max(0, displayHeight - previewScrollView.contentSize.height)
        ))
        previewScrollView.reflectScrolledClipView(previewScrollView.contentView)
    }

    private func requestFinishOnce() {
        guard !didRequestAction else { return }
        didRequestAction = true
        onFinish()
    }

    private func actionButton(icon: String, tooltip: String, action: Selector) -> GlassToolbarButton {
        let button = GlassToolbarButton()
        button.image = ToolbarIconProvider.image(named: icon, accessibilityDescription: tooltip)
        button.imagePosition = .imageOnly
        button.target = self
        button.action = action
        button.toolTip = tooltip
        button.widthAnchor.constraint(equalToConstant: 30).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return button
    }

    @objc private func saveCapture() {
        guard !didRequestAction else { return }
        didRequestAction = true
        onSave()
    }

    @objc private func cancelCapture() {
        guard !didRequestAction else { return }
        didRequestAction = true
        onCancel()
    }

    @objc private func finishCapture() { requestFinishOnce() }
}

private final class FlippedPreviewImageView: NSImageView {
    override var isFlipped: Bool { true }
}
