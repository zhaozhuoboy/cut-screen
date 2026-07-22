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
        let size = CGSize(width: max(80, pointSize.width * scale), height: max(60, pointSize.height * scale))
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
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = CGSize(width: 80, height: 60)
        panel.contentAspectRatio = pointSize
        panel.contentView = PinnedImageView(image: image)

        super.init(window: panel)
        panel.delegate = self
        (panel.contentView as? PinnedImageView)?.controller = self
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
        let current = window.frame.size
        let maximum = screen.visibleFrame.size
        var proposed = CGSize(width: current.width * factor, height: current.height * factor)
        proposed.width = min(max(proposed.width, 80), maximum.width * 0.95)
        proposed.height = proposed.width * pointSize.height / pointSize.width
        if proposed.height > maximum.height * 0.95 {
            proposed.height = maximum.height * 0.95
            proposed.width = proposed.height * pointSize.width / pointSize.height
        }
        var frame = window.frame
        frame.origin.x -= (proposed.width - frame.width) / 2
        frame.origin.y -= (proposed.height - frame.height) / 2
        frame.size = proposed
        window.setFrame(frame, display: true, animate: false)
    }
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
        layer?.borderWidth = 1
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

    @objc private func copyImage() { controller?.copyImage() }
    @objc private func saveImage() { controller?.saveImage() }
    @objc private func closeWindow() { window?.close() }
}
