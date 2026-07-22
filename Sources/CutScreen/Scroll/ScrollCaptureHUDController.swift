import AppKit

@MainActor
final class ScrollCaptureHUDController {
    private let onFinish: () -> Void
    private let borderWindow: NSPanel
    private let controlWindow: NSPanel
    private let previewWindow: NSPanel
    private let label = NSTextField(labelWithString: "向下滚动页面，结束后复制长图")
    private let previewHeightLabel = NSTextField(labelWithString: "正在获取起始画面…")
    private let previewScrollView = NSScrollView()
    private let previewImageView = FlippedPreviewImageView()
    private var didRequestFinish = false

    init(selection: Selection, onFinish: @escaping () -> Void) {
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
            contentRect: CGRect(x: 0, y: 0, width: 300, height: 46),
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

        let finish = NSButton(title: "完成并复制", target: nil, action: nil)
        finish.toolTip = "结束滚动截图并复制到剪贴板"
        let stack = NSStackView(views: [label, finish])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
        stack.wantsLayer = true
        stack.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        stack.layer?.cornerRadius = 8
        finish.target = self
        finish.action = #selector(finishCapture)
        controlWindow.contentView = stack

        buildPreview(in: previewContent)

        let desiredX = min(selection.globalRect.maxX - 300, selection.screenFrame.maxX - 308)
        var desiredY = selection.globalRect.maxY + 8
        if desiredY + 46 > selection.screenFrame.maxY { desiredY = selection.globalRect.minY - 54 }
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

    func update(result: StitchAppendResult, totalHeight: Int, preview: CGImage?) {
        if let preview { updatePreviewImage(preview, totalHeight: totalHeight) }
        switch result {
        case .noMatch:
            label.stringValue = "未识别到连续内容，请放慢滚动"
            label.textColor = .systemOrange
        case .limitReached:
            label.stringValue = "已达到长图上限，正在完成"
            label.textColor = .systemOrange
            requestFinishOnce()
        case .duplicate:
            label.stringValue = "等待页面向下滚动 · 已捕获 \(formatted(totalHeight)) px"
            label.textColor = .secondaryLabelColor
        case .firstFrame:
            label.stringValue = "已捕获起始画面，请向下滚动页面"
            label.textColor = .labelColor
        case .appended(let added, _):
            label.stringValue = "新增 \(formatted(added)) px · 累计 \(formatted(totalHeight)) px"
            label.textColor = .labelColor
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

        previewHeightLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        previewHeightLabel.textColor = .secondaryLabelColor
        previewHeightLabel.alignment = .right

        let header = NSStackView(views: [title, NSView(), previewHeightLabel])
        header.orientation = .horizontal
        header.alignment = .centerY

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

        let stack = NSStackView(views: [header, previewScrollView])
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
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            previewScrollView.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func updatePreviewImage(_ image: CGImage, totalHeight: Int) {
        let contentWidth = max(1, previewScrollView.contentSize.width)
        let displayHeight = max(
            previewScrollView.contentSize.height,
            contentWidth * CGFloat(image.height) / CGFloat(image.width)
        )
        previewImageView.image = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
        previewImageView.frame = CGRect(x: 0, y: 0, width: contentWidth, height: displayHeight)
        previewHeightLabel.stringValue = "\(formatted(totalHeight)) px"
        previewScrollView.layoutSubtreeIfNeeded()
        previewScrollView.contentView.scroll(to: CGPoint(
            x: 0,
            y: max(0, displayHeight - previewScrollView.contentSize.height)
        ))
        previewScrollView.reflectScrolledClipView(previewScrollView.contentView)
    }

    private func requestFinishOnce() {
        guard !didRequestFinish else { return }
        didRequestFinish = true
        onFinish()
    }

    private func formatted(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    @objc private func finishCapture() { requestFinishOnce() }
}

private final class FlippedPreviewImageView: NSImageView {
    override var isFlipped: Bool { true }
}
