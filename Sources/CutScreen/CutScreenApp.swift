import AppKit

@main
@MainActor
final class CutScreenApp: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    static func main() {
        let application = NSApplication.shared
        let delegate = CutScreenApp()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = AppCoordinator()
        coordinator?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }
}
