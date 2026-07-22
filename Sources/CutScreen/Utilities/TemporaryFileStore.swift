import Foundation

enum TemporaryFileStore {
    private static var root: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CutScreen", isDirectory: true)
    }

    static func createSessionDirectory() throws -> URL {
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func cleanupStaleSessions(olderThan age: TimeInterval = 24 * 60 * 60) {
        let manager = FileManager.default
        guard let urls = try? manager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-age)
        for url in urls {
            let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if date == nil || date! < cutoff {
                try? manager.removeItem(at: url)
            }
        }
    }
}
