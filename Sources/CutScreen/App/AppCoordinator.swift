import AppKit
import OSLog

@MainActor
final class AppCoordinator {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CutScreen", category: "App")
    private let settings = AppSettings()
    private let hotKeyManager = GlobalHotKeyManager()
    private lazy var captureCoordinator = CaptureCoordinator()
    private lazy var statusBarController = StatusBarController(
        onCapture: { [weak self] in self?.handleCaptureShortcut() },
        onSettings: { [weak self] in self?.showSettings() },
        onQuit: { NSApplication.shared.terminate(nil) }
    )
    private lazy var settingsController = SettingsWindowController(settings: settings) { [weak self] shortcut in
        self?.updateHotKey(shortcut) ?? false
    }

    func start() {
        TemporaryFileStore.cleanupStaleSessions()
        statusBarController.install()
        hotKeyManager.onPressed = { [weak self] in
            self?.handleCaptureShortcut()
        }
        registerSavedHotKey()
    }

    func stop() {
        captureCoordinator.cancel()
        hotKeyManager.unregister()
    }

    private func registerSavedHotKey() {
        do {
            try hotKeyManager.register(settings.hotKey)
            statusBarController.setShortcut(settings.hotKey.displayName)
            settings.hotKeyError = nil
        } catch {
            settings.hotKeyError = "快捷键 \(settings.hotKey.displayName) 已被占用，请在设置中修改。"
            statusBarController.showError(settings.hotKeyError)
            logger.error("Failed to register hot key: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func updateHotKey(_ shortcut: HotKey) -> Bool {
        guard shortcut.isValid else {
            settings.hotKeyError = "快捷键至少需要包含 Control、Option 或 Command。"
            return false
        }

        let oldShortcut = settings.hotKey
        hotKeyManager.unregister()
        do {
            try hotKeyManager.register(shortcut)
            settings.hotKey = shortcut
            settings.hotKeyError = nil
            statusBarController.setShortcut(shortcut.displayName)
            return true
        } catch {
            try? hotKeyManager.register(oldShortcut)
            settings.hotKeyError = "快捷键 \(shortcut.displayName) 已被其他应用占用。"
            return false
        }
    }

    private func handleCaptureShortcut() {
        if captureCoordinator.state == .scrolling {
            Task { await captureCoordinator.finishScrolling() }
            return
        }
        captureCoordinator.begin()
    }

    private func showSettings() {
        settingsController.showWindow(nil)
        settingsController.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
