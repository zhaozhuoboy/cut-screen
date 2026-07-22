import AppKit

@MainActor
enum GlassToolbarComponents {
    @discardableResult
    static func configure(_ panel: NSPanel, cornerRadius: CGFloat = 14) -> NSView {
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let container = RoundedGlassContainerView(
            frame: panel.contentView?.bounds ?? .zero,
            cornerRadius: cornerRadius
        )
        let effectView = NSVisualEffectView(frame: container.bounds)
        effectView.autoresizingMask = [.width, .height]
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.isEmphasized = true
        effectView.wantsLayer = true
        effectView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.18).cgColor
        container.addSubview(effectView, positioned: .below, relativeTo: nil)
        container.layer?.borderWidth = 0.75
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.24).cgColor
        panel.contentView = container
        panel.invalidateShadow()
        return container
    }
}

@MainActor
private final class RoundedGlassContainerView: NSView {
    private let glassCornerRadius: CGFloat
    private let shapeMask = CAShapeLayer()

    init(frame frameRect: NSRect, cornerRadius: CGFloat) {
        glassCornerRadius = cornerRadius
        super.init(frame: frameRect)
        autoresizingMask = [.width, .height]
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.mask = shapeMask
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        shapeMask.frame = bounds
        shapeMask.path = CGPath(
            roundedRect: shapeMask.bounds,
            cornerWidth: glassCornerRadius,
            cornerHeight: glassCornerRadius,
            transform: nil
        )
        window?.invalidateShadow()
    }
}

@MainActor
final class GlassToolbarButton: NSButton {
    var showsSelection = false { didSet { updateAppearance() } }
    var isPrimaryAction = false { didSet { updateAppearance() } }

    private var tracking: NSTrackingArea?
    private var isHovered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        bezelStyle = .regularSquare
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) { nil }

    override var isEnabled: Bool {
        didSet { updateAppearance() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
        if let toolTip, !toolTip.isEmpty {
            ScreenshotToolTipPresenter.shared.schedule(toolTip, for: self)
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
        ScreenshotToolTipPresenter.shared.hide(for: self)
    }

    override func mouseDown(with event: NSEvent) {
        ScreenshotToolTipPresenter.shared.hide(for: self)
        super.mouseDown(with: event)
    }

    private func updateAppearance() {
        alphaValue = isEnabled ? 1 : 0.38
        if isPrimaryAction {
            contentTintColor = .white
            layer?.backgroundColor = (isHovered
                ? NSColor.systemGreen.blended(withFraction: 0.12, of: .white) ?? .systemGreen
                : NSColor.systemGreen).cgColor
        } else if showsSelection {
            contentTintColor = .systemGreen
            layer?.backgroundColor = NSColor.clear.cgColor
        } else {
            contentTintColor = .labelColor
            layer?.backgroundColor = (isHovered
                ? NSColor.labelColor.withAlphaComponent(0.10)
                : NSColor.clear).cgColor
        }
    }
}

@MainActor
final class ScreenshotToolTipPresenter: NSObject {
    static let shared = ScreenshotToolTipPresenter()

    private weak var sourceView: NSView?
    private var pendingText = ""
    private var timer: Timer?
    private var panel: NSPanel?

    func schedule(_ text: String, for view: NSView) {
        hide()
        sourceView = view
        pendingText = text
        timer = Timer.scheduledTimer(
            timeInterval: 0.45,
            target: self,
            selector: #selector(showPendingToolTip),
            userInfo: nil,
            repeats: false
        )
    }

    func hide(for view: NSView) {
        guard sourceView == nil || sourceView === view else { return }
        hide()
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        sourceView = nil
        pendingText = ""
    }

    @objc private func showPendingToolTip() {
        timer = nil
        guard let sourceView,
              let sourceWindow = sourceView.window,
              !pendingText.isEmpty else { return }

        let label = NSTextField(labelWithString: pendingText)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.sizeToFit()
        let size = CGSize(width: label.frame.width + 18, height: max(28, label.frame.height + 10))

        let toolTipPanel = NSPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        toolTipPanel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 4)
        toolTipPanel.isOpaque = false
        toolTipPanel.backgroundColor = .clear
        toolTipPanel.hasShadow = true
        toolTipPanel.ignoresMouseEvents = true
        toolTipPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let container = NSView(frame: CGRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.cornerRadius = 7
        container.layer?.cornerCurve = .continuous
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        toolTipPanel.contentView = container

        let sourceRect = sourceWindow.convertToScreen(sourceView.convert(sourceView.bounds, to: nil))
        let visible = (sourceWindow.screen?.visibleFrame ?? sourceWindow.frame).insetBy(dx: 6, dy: 6)
        var x = sourceRect.midX - size.width / 2
        x = min(max(x, visible.minX), visible.maxX - size.width)
        var y = sourceRect.minY - size.height - 7
        if y < visible.minY { y = sourceRect.maxY + 7 }
        y = min(max(y, visible.minY), visible.maxY - size.height)
        toolTipPanel.setFrameOrigin(CGPoint(x: x, y: y))
        panel = toolTipPanel
        toolTipPanel.orderFrontRegardless()
    }
}
