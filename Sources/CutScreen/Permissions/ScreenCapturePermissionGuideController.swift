import AppKit

@MainActor
final class ScreenCapturePermissionGuideController: NSWindowController, NSWindowDelegate {
    private let hasPermission: () -> Bool
    private let requestPermission: () -> Bool
    private let openSettings: () -> Void
    private let statusLabel = NSTextField(labelWithString: "")

    init(
        hasPermission: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
        requestPermission: @escaping () -> Bool = { CGRequestScreenCaptureAccess() },
        openSettings: @escaping () -> Void = {
            guard let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            ) else { return }
            NSWorkspace.shared.open(url)
        }
    ) {
        self.hasPermission = hasPermission
        self.requestPermission = requestPermission
        self.openSettings = openSettings

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "轻截权限引导"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        buildContent()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) { nil }

    func presentIfNeeded() {
        guard !hasPermission() else {
            close()
            return
        }
        statusLabel.stringValue = "当前尚未授权，轻截无法读取屏幕画面。"
        statusLabel.textColor = .systemOrange
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        let icon = NSImageView()
        icon.image = NSImage(named: NSImage.applicationIconName)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 70).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 70).isActive = true

        let title = NSTextField(labelWithString: "允许轻截读取屏幕内容")
        title.font = .systemFont(ofSize: 21, weight: .bold)
        title.alignment = .center

        let detail = NSTextField(wrappingLabelWithString: "截图、窗口识别和滚动长截图需要 macOS 的“屏幕与系统音频录制”权限。画面只在本机处理，不会上传。")
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .center
        detail.maximumNumberOfLines = 3

        let steps = NSStackView(views: [
            guideRow(number: "1", text: "点击下方按钮发起系统授权。"),
            guideRow(number: "2", text: "在系统设置中打开“轻截”开关。"),
            guideRow(number: "3", text: "按系统提示重新打开轻截即可截图。")
        ])
        steps.orientation = .vertical
        steps.alignment = .leading
        steps.spacing = 8
        steps.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        steps.wantsLayer = true
        steps.layer?.cornerRadius = 10
        steps.layer?.cornerCurve = .continuous
        steps.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.72).cgColor

        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.alignment = .center

        let requestButton = NSButton(
            title: "请求并打开授权设置",
            target: self,
            action: #selector(requestAndOpenSettings)
        )
        requestButton.identifier = NSUserInterfaceItemIdentifier("requestScreenCapturePermission")
        requestButton.bezelStyle = .rounded
        requestButton.controlSize = .large
        requestButton.keyEquivalent = "\r"
        requestButton.toolTip = "请求屏幕录制权限并打开对应系统设置"

        let settingsButton = NSButton(
            title: "直接打开系统设置",
            target: self,
            action: #selector(openPermissionSettings)
        )
        settingsButton.identifier = NSUserInterfaceItemIdentifier("openScreenCaptureSettings")
        settingsButton.bezelStyle = .rounded
        settingsButton.controlSize = .large
        settingsButton.toolTip = "打开屏幕与系统音频录制设置"

        let laterButton = NSButton(title: "稍后", target: self, action: #selector(closeGuide))
        laterButton.bezelStyle = .inline
        laterButton.toolTip = "暂时关闭权限引导"

        let buttons = NSStackView(views: [requestButton, settingsButton, laterButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 10

        let stack = NSStackView(views: [icon, title, detail, steps, statusLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 34),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -34),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -22),
            detail.widthAnchor.constraint(equalToConstant: 430),
            steps.widthAnchor.constraint(equalToConstant: 430),
            statusLabel.widthAnchor.constraint(equalToConstant: 430)
        ])
    }

    private func guideRow(number: String, text: String) -> NSView {
        let badge = NSTextField(labelWithString: number)
        badge.font = .systemFont(ofSize: 11, weight: .bold)
        badge.textColor = .white
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 9
        badge.layer?.backgroundColor = NSColor.systemGreen.cgColor
        badge.widthAnchor.constraint(equalToConstant: 18).isActive = true
        badge.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        let row = NSStackView(views: [badge, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 9
        return row
    }

    private func refreshPermissionState() {
        guard window?.isVisible == true else { return }
        if hasPermission() {
            statusLabel.stringValue = "已获得屏幕录制权限。"
            statusLabel.textColor = .systemGreen
            close()
        }
    }

    @objc private func requestAndOpenSettings() {
        if requestPermission() || hasPermission() {
            statusLabel.stringValue = "授权成功，可以开始截图。"
            statusLabel.textColor = .systemGreen
            close()
            return
        }
        statusLabel.stringValue = "请在系统设置中打开“轻截”，然后重新启动应用。"
        statusLabel.textColor = .systemOrange
        openSettings()
    }

    @objc private func openPermissionSettings() {
        openSettings()
    }

    @objc private func closeGuide() {
        close()
    }

    @objc private func applicationDidBecomeActive() {
        refreshPermissionState()
    }
}
