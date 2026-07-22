import AppKit

@MainActor
final class PinManager {
    private var controllers: [UUID: PinWindowController] = [:]

    func pin(_ image: CGImage, pointSize: CGSize) {
        let id = UUID()
        let controller = PinWindowController(id: id, image: image, pointSize: pointSize) { [weak self] id in
            self?.controllers.removeValue(forKey: id)
        }
        controllers[id] = controller
        controller.show()
    }
}

@MainActor
private final class PinWindowController: NSWindowController, NSWindowDelegate {
    private let id: UUID
    private let image: CGImage
    private let pointSize: CGSize
    private let onClose: (UUID) -> Void

    init(id: UUID, image: CGImage, pointSize: CGSize, onClose: @escaping (UUID) -> Void) {
        self.id = id
        self.image = image
        self.pointSize = pointSize
        self.onClose = onClose

        let visible = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1200, height: 800)
        let scale = min(1, min(visible.width * 0.65 / pointSize.width, visible.height * 0.65 / pointSize.height))
        let imageSize = CGSize(width: max(100, pointSize.width * scale), height: max(60, pointSize.height * scale))
        let size = PinWindowMetrics.windowSize(for: imageSize)
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.title = "轻截贴图"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = PinWindowMetrics.windowSize(for: CGSize(width: 100, height: 60))
        panel.contentView = PinnedImageContainerView(image: image)

        super.init(window: panel)
        panel.delegate = self
        (panel.contentView as? PinnedImageContainerView)?.controller = self
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        window?.center()
        window?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        onClose(id)
    }

    func copyImage() {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        _ = PasteboardService().writePNG(data)
    }

    func saveImage() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = ScreenshotFileName.make(extension: "png")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let format: NSBitmapImageRep.FileType = ["jpg", "jpeg"].contains(url.pathExtension.lowercased()) ? .jpeg : .png
        let properties: [NSBitmapImageRep.PropertyKey: Any] = format == .jpeg ? [.compressionFactor: 0.92] : [:]
        if let data = NSBitmapImageRep(cgImage: image).representation(using: format, properties: properties) {
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                ErrorPresenter.show(title: "保存失败", error: error)
            }
        }
    }

    func zoom(by factor: CGFloat) {
        guard let window, let screen = window.screen else { return }
        let current = (window.contentView as? PinnedImageContainerView)?.imageDisplaySize ?? pointSize
        let maximum = screen.visibleFrame.size
        var proposed = CGSize(width: current.width * factor, height: current.height * factor)
        proposed.width = min(max(proposed.width, 100), maximum.width * 0.95)
        proposed.height = proposed.width * pointSize.height / pointSize.width
        if proposed.height + PinWindowMetrics.verticalChrome > maximum.height * 0.95 {
            proposed.height = max(60, maximum.height * 0.95 - PinWindowMetrics.verticalChrome)
            proposed.width = proposed.height * pointSize.width / pointSize.height
        }
        let newFrameSize = PinWindowMetrics.windowSize(for: proposed)
        var frame = window.frame
        frame.origin.x -= (newFrameSize.width - frame.width) / 2
        frame.origin.y -= (newFrameSize.height - frame.height) / 2
        frame.size = newFrameSize
        window.setFrame(frame, display: true, animate: false)
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let imageWidth = max(100, frameSize.width - PinWindowMetrics.horizontalChrome)
        let imageHeight = max(60, imageWidth * pointSize.height / pointSize.width)
        return PinWindowMetrics.windowSize(for: CGSize(width: imageWidth, height: imageHeight))
    }

    func closePin() { window?.close() }
}

private enum PinWindowMetrics {
    static let horizontalChrome: CGFloat = 12
    static let verticalChrome: CGFloat = 48

    static func windowSize(for imageSize: CGSize) -> CGSize {
        CGSize(
            width: imageSize.width + horizontalChrome,
            height: imageSize.height + verticalChrome
        )
    }
}

@MainActor
private final class PinnedImageContainerView: NSView {
    weak var controller: PinWindowController? {
        didSet { imageView.controller = controller }
    }

    private let imageView: PinnedImageView
    var imageDisplaySize: CGSize { imageView.bounds.size }

    init(image: CGImage) {
        imageView = PinnedImageView(image: image)
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("pinnedImageContainer")
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 0.75
        layer?.borderColor = NSColor.white.withAlphaComponent(0.42).cgColor
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor

        let header = NSVisualEffectView()
        header.identifier = NSUserInterfaceItemIdentifier("pinnedImageHeader")
        header.material = .headerView
        header.blendingMode = .behindWindow
        header.state = .active

        let pinIcon = NSImageView()
        pinIcon.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "贴图")
        pinIcon.contentTintColor = .systemGreen
        pinIcon.widthAnchor.constraint(equalToConstant: 15).isActive = true
        pinIcon.heightAnchor.constraint(equalToConstant: 15).isActive = true

        let title = NSTextField(labelWithString: "轻截贴图")
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .labelColor

        let titleStack = NSStackView(views: [pinIcon, title])
        titleStack.orientation = .horizontal
        titleStack.alignment = .centerY
        titleStack.spacing = 6

        let copy = actionButton(
            symbol: "doc.on.doc",
            tooltip: "复制贴图",
            action: #selector(copyImage)
        )
        let save = actionButton(
            symbol: "square.and.arrow.down",
            tooltip: "保存贴图",
            action: #selector(saveImage)
        )
        let close = actionButton(
            symbol: "xmark",
            tooltip: "关闭贴图",
            action: #selector(closePin)
        )
        let actions = NSStackView(views: [copy, save, close])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 2

        header.translatesAutoresizingMaskIntoConstraints = false
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        actions.translatesAutoresizingMaskIntoConstraints = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.identifier = NSUserInterfaceItemIdentifier("pinnedImage")
        addSubview(header)
        header.addSubview(titleStack)
        header.addSubview(actions)
        addSubview(imageView)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.topAnchor.constraint(equalTo: topAnchor),
            header.heightAnchor.constraint(equalToConstant: 36),
            titleStack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 10),
            titleStack.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            actions.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -6),
            actions.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            imageView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    required init?(coder: NSCoder) { nil }

    private func actionButton(symbol: String, tooltip: String, action: Selector) -> GlassToolbarButton {
        let button = GlassToolbarButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.imagePosition = .imageOnly
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.widthAnchor.constraint(equalToConstant: 27).isActive = true
        button.heightAnchor.constraint(equalToConstant: 27).isActive = true
        return button
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    @objc private func copyImage() { controller?.copyImage() }
    @objc private func saveImage() { controller?.saveImage() }
    @objc private func closePin() { controller?.closePin() }
}

@MainActor
private final class PinnedImageView: NSView {
    weak var controller: PinWindowController?
    private let image: NSImage

    init(image: CGImage) {
        self.image = NSImage(cgImage: image, size: .zero)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 0.75
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let copy = NSMenuItem(title: "复制", action: #selector(copyImage), keyEquivalent: "")
        copy.target = self
        menu.addItem(copy)
        let save = NSMenuItem(title: "保存…", action: #selector(saveImage), keyEquivalent: "")
        save.target = self
        menu.addItem(save)
        menu.addItem(.separator())
        let close = NSMenuItem(title: "关闭贴图", action: #selector(closeWindow), keyEquivalent: "")
        close.target = self
        menu.addItem(close)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func scrollWheel(with event: NSEvent) {
        controller?.zoom(by: event.scrollingDeltaY > 0 ? 1.08 : 0.92)
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    @objc private func copyImage() { controller?.copyImage() }
    @objc private func saveImage() { controller?.saveImage() }
    @objc private func closeWindow() { window?.close() }
}
