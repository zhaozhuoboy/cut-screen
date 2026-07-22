import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    private let settings: AppSettings
    private let onShortcutChange: (HotKey) -> Bool
    private let shortcutButton = NSButton(title: "", target: nil, action: nil)
    private let loginCheckbox = NSButton(checkboxWithTitle: "登录时启动", target: nil, action: nil)
    private let messageLabel = NSTextField(labelWithString: "")
    private var eventMonitor: Any?

    init(settings: AppSettings, onShortcutChange: @escaping (HotKey) -> Bool) {
        self.settings = settings
        self.onShortcutChange = onShortcutChange

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "轻截设置"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent()
    }

    required init?(coder: NSCoder) { nil }

    override func showWindow(_ sender: Any?) {
        shortcutButton.title = settings.hotKey.displayName
        loginCheckbox.state = settings.launchesAtLogin ? .on : .off
        messageLabel.stringValue = settings.hotKeyError ?? "点击快捷键按钮后，按下新的组合键。"
        super.showWindow(sender)
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        let title = NSTextField(labelWithString: "全局截图快捷键")
        title.font = .systemFont(ofSize: 14, weight: .medium)
        shortcutButton.bezelStyle = .rounded
        shortcutButton.toolTip = "修改全局截图快捷键"
        shortcutButton.target = self
        shortcutButton.action = #selector(recordShortcut)
        shortcutButton.widthAnchor.constraint(equalToConstant: 110).isActive = true

        let shortcutRow = NSStackView(views: [title, NSView(), shortcutButton])
        shortcutRow.orientation = .horizontal
        shortcutRow.alignment = .centerY

        loginCheckbox.target = self
        loginCheckbox.action = #selector(toggleLoginItem)
        loginCheckbox.toolTip = "设置轻截是否随登录自动启动"

        messageLabel.textColor = .secondaryLabelColor
        messageLabel.maximumNumberOfLines = 2
        messageLabel.lineBreakMode = .byWordWrapping

        let stack = NSStackView(views: [shortcutRow, loginCheckbox, messageLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 32)
        ])
    }

    @objc private func recordShortcut() {
        shortcutButton.title = "请按快捷键…"
        shortcutButton.highlight(true)
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            self.finishRecording(event)
            return nil
        }
    }

    private func finishRecording(_ event: NSEvent) {
        defer {
            if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
            eventMonitor = nil
            shortcutButton.highlight(false)
        }

        guard event.keyCode != 53, let shortcut = HotKey(event: event), shortcut.isValid else {
            shortcutButton.title = settings.hotKey.displayName
            messageLabel.stringValue = "无效快捷键，请至少包含 Control、Option 或 Command。"
            return
        }

        if onShortcutChange(shortcut) {
            shortcutButton.title = shortcut.displayName
            messageLabel.stringValue = "快捷键已更新。"
        } else {
            shortcutButton.title = settings.hotKey.displayName
            messageLabel.stringValue = settings.hotKeyError ?? "快捷键不可用。"
        }
    }

    @objc private func toggleLoginItem() {
        do {
            try settings.setLaunchesAtLogin(loginCheckbox.state == .on)
            messageLabel.stringValue = loginCheckbox.state == .on ? "已开启登录时启动。" : "已关闭登录时启动。"
        } catch {
            loginCheckbox.state = settings.launchesAtLogin ? .on : .off
            messageLabel.stringValue = "无法修改登录项：\(error.localizedDescription)"
        }
    }
}
