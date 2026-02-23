import Foundation

struct AppConfig: Codable, Sendable {
    var pollIntervalSeconds: Int = 30
}
