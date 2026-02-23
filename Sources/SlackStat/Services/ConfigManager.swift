import Foundation

final class ConfigManager: Sendable {
    let configURL: URL

    init(directory: URL? = nil) {
        let dir = directory ?? {
            let home = FileManager.default.homeDirectoryForCurrentUser
            return home.appendingPathComponent(".config/slackstat")
        }()
        self.configURL = dir.appendingPathComponent("config.json")
    }

    func load() -> AppConfig {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return AppConfig()
        }
        do {
            let data = try Data(contentsOf: configURL)
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            print("Warning: Failed to load config: \(error). Using defaults.")
            return AppConfig()
        }
    }

    func save(_ config: AppConfig) throws {
        let dir = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configURL, options: .atomic)
    }
}
