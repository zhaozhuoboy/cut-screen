import AppKit

enum ScreenshotFileName {
    static func make(date: Date = Date(), extension fileExtension: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "轻截 \(formatter.string(from: date)).\(fileExtension)"
    }
}

@MainActor
enum ErrorPresenter {
    static func show(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        alert.runModal()
    }

    static func show(title: String, error: any Error) {
        show(title: title, message: error.localizedDescription)
    }
}
