import Foundation
import ServiceManagement

@MainActor
final class AppSettings {
    private enum Keys {
        static let hotKey = "hotKey"
    }

    private let defaults: UserDefaults
    var hotKeyError: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hotKey: HotKey {
        get {
            guard let data = defaults.data(forKey: Keys.hotKey),
                  let value = try? JSONDecoder().decode(HotKey.self, from: data) else {
                return .default
            }
            return value
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.hotKey)
            }
        }
    }

    var launchesAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchesAtLogin(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }
}
