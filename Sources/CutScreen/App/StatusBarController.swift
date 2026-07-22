import AppKit

@MainActor
final class StatusBarController: NSObject {
    private let onCapture: () -> Void
    private let onSettings: () -> Void
    private let onQuit: () -> Void
    private var statusItem: NSStatusItem?
    private var captureItem: NSMenuItem?

    init(onCapture: @escaping () -> Void, onSettings: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.onCapture = onCapture
        self.onSettings = onSettings
        self.onQuit = onQuit
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "轻截")
        item.button?.toolTip = "轻截"

        let menu = NSMenu()
        let captureItem = NSMenuItem(title: "开始截图", action: #selector(capture), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(settings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

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

    func showError(_ message: String?) {
        guard let message else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "快捷键不可用"
        alert.informativeText = message
        alert.runModal()
    }

    @objc private func capture() { onCapture() }
    @objc private func settings() { onSettings() }
    @objc private func quit() { onQuit() }
}
