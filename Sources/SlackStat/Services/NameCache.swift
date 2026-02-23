import Foundation

/// Thread-safe cache for channel and user display names.
/// Names rarely change, so we cache indefinitely within an app session.
final class NameCache: @unchecked Sendable {
    private var channelNames: [String: String] = [:]
    private var channelPrivate: [String: Bool] = [:]  // channelId -> isPrivate
    private var channelExtShared: [String: Bool] = [:]  // channelId -> isExtShared
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

    func isChannelPrivate(for id: String) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return channelPrivate[id]
    }

    func setChannelPrivate(_ isPrivate: Bool, for id: String) {
        lock.lock()
        defer { lock.unlock() }
        channelPrivate[id] = isPrivate
    }

    func isChannelExtShared(for id: String) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return channelExtShared[id]
    }

    func setChannelExtShared(_ isExtShared: Bool, for id: String) {
        lock.lock()
        defer { lock.unlock() }
        channelExtShared[id] = isExtShared
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
