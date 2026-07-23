import AppKit

@MainActor
final class StatusBarController: NSObject {
    private let onCapture: () -> Void
    private let onSettings: () -> Void
    private let onQuit: () -> Void
    private var statusItem: NSStatusItem?
    private var captureItem: NSMenuItem?
    private var launchHintPopover: NSPopover?
    private var launchHintTask: Task<Void, Never>?

    init(onCapture: @escaping () -> Void, onSettings: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.onCapture = onCapture
        self.onSettings = onSettings
        self.onQuit = onQuit
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let statusIcon = ToolbarIconProvider.image(
            named: "status-viewfinder-bolt",
            accessibilityDescription: "轻截"
        )
        statusIcon?.size = CGSize(width: 18, height: 18)
        item.button?.image = statusIcon
        item.button?.toolTip = "轻截"

        let menu = NSMenu()
        let captureItem = NSMenuItem(title: "开始截图", action: #selector(capture), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(settings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let feedbackItem = NSMenuItem(title: "反馈", action: #selector(feedback), keyEquivalent: "")
        feedbackItem.target = self
        menu.addItem(feedbackItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出轻截", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        self.captureItem = captureItem
        statusItem = item
    }

    func setShortcut(_ shortcut: String) {
        captureItem?.title = "开始截图（\(shortcut)）"
    }

    func showLaunchHint(shortcut: String) {
        dismissLaunchHint()
        launchHintTask = Task { @MainActor [weak self] in
            try? await Task<Never, Never>.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, let self, let button = statusItem?.button else { return }

            let content = LaunchHintViewController(shortcut: shortcut) { [weak self] in
                self?.dismissLaunchHint()
                self?.onCapture()
            }
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = true
            popover.contentSize = CGSize(width: 300, height: 132)
            popover.contentViewController = content
            launchHintPopover = popover
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            try? await Task<Never, Never>.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            popover.performClose(nil)
            if launchHintPopover === popover {
                launchHintPopover = nil
            }
        }
    }

    func dismissLaunchHint() {
        launchHintTask?.cancel()
        launchHintTask = nil
        launchHintPopover?.performClose(nil)
        launchHintPopover = nil
    }

    func showError(_ message: String?) {
        guard let message else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "快捷键不可用"
        alert.informativeText = message
        alert.runModal()
    }

    @objc private func capture() {
        dismissLaunchHint()
        onCapture()
    }
    @objc private func settings() { onSettings() }
    @objc private func feedback() {
        guard let url = URL(string: "https://my.feishu.cn/share/base/form/shrcn4PO31W5r1nKbtg4xmMuw7f") else { return }
        NSWorkspace.shared.open(url)
    }
    @objc private func quit() { onQuit() }
}
