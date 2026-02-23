import Foundation

/// Thread-safe cache for channel and user display names.
/// Names rarely change, so we cache indefinitely within an app session.
final class NameCache: @unchecked Sendable {
    private var channelNames: [String: String] = [:]
    private var userNames: [String: String] = [:]
    private var dmUsers: [String: String] = [:]  // channelId -> userId
    private let lock = NSLock()

    func channelName(for id: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return channelNames[id]
    }

    func setChannelName(_ name: String, for id: String) {
        lock.lock()
        defer { lock.unlock() }
        channelNames[id] = name
    }

    func userName(for id: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return userNames[id]
    }

    func setUserName(_ name: String, for id: String) {
        lock.lock()
        defer { lock.unlock() }
        userNames[id] = name
    }

    func dmUser(for channelId: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return dmUsers[channelId]
    }

    func setDMUser(_ userId: String, for channelId: String) {
        lock.lock()
        defer { lock.unlock() }
        dmUsers[channelId] = userId
    }
}
