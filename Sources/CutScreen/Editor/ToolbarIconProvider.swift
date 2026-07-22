import AppKit

@MainActor
enum ToolbarIconProvider {
    static func image(named name: String, accessibilityDescription: String) -> NSImage? {
        guard let url = iconURL(named: name), let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.size = CGSize(width: 20, height: 20)
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }

    private static func iconURL(named name: String) -> URL? {
        if let bundled = Bundle.main.url(
            forResource: name,
            withExtension: "svg",
            subdirectory: "ToolbarIcons"
        ) {
            return bundled
        }

        // `swift run` has no .app Resources directory. Keep a source-tree fallback
        // so the same vector assets are used during local development.
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sourceRoot
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("ToolbarIcons", isDirectory: true)
            .appendingPathComponent("\(name).svg")
        return FileManager.default.fileExists(atPath: sourceURL.path) ? sourceURL : nil
    }
}
