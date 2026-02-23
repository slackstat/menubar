import Foundation
import SwiftUI

// MARK: - View Models

enum ConversationType: Sendable {
    case dm
    case mention  // channel with @mentions
    case channel
    case mpim
}

struct ConversationItem: Identifiable, Sendable {
    let id: String
    let name: String
    let type: ConversationType
    let teamId: String  // Slack team ID, used for API routing and deep links
    var hasUnreads: Bool
    var mentionCount: Int
    var latestTimestamp: Date?
    var userId: String?  // For DMs, the other user's ID

    init(
        id: String, name: String, type: ConversationType, teamId: String,
        hasUnreads: Bool, mentionCount: Int, latestTimestamp: Date?, userId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.teamId = teamId
        self.hasUnreads = hasUnreads
        self.mentionCount = mentionCount
        self.latestTimestamp = latestTimestamp
        self.userId = userId
    }

    init(
        from count: ConversationCount, name: String, type: ConversationType,
        teamId: String, userId: String? = nil
    ) {
        self.id = count.id
        self.name = name
        self.type = type
        self.teamId = teamId
        self.hasUnreads = count.hasUnreads
        self.mentionCount = count.mentionCount
        self.latestTimestamp = count.latestDate
        self.userId = userId
    }

}

struct AggregatedCounts: Sendable {
    let totalDMs: Int
    let totalMentions: Int
    let totalChannels: Int
    let mostRecentDM: Date?
    let mostRecentMention: Date?
    let mostRecentChannel: Date?

    var hasActivity: Bool {
        totalDMs > 0 || totalMentions > 0 || totalChannels > 0
    }

    init(from items: [ConversationItem]) {
        let dms = items.filter { $0.type == .dm || $0.type == .mpim }
        let mentions = items.filter { $0.type == .mention }
        let channels = items.filter { $0.type == .channel }

        self.totalDMs = dms.count
        self.totalMentions = mentions.count
        self.totalChannels = channels.count
        self.mostRecentDM = dms.compactMap(\.latestTimestamp).max()
        self.mostRecentMention = mentions.compactMap(\.latestTimestamp).max()
        self.mostRecentChannel = channels.compactMap(\.latestTimestamp).max()
    }

    init(totalDMs: Int = 0, totalMentions: Int = 0, totalChannels: Int = 0,
         mostRecentDM: Date? = nil, mostRecentMention: Date? = nil, mostRecentChannel: Date? = nil) {
        self.totalDMs = totalDMs
        self.totalMentions = totalMentions
        self.totalChannels = totalChannels
        self.mostRecentDM = mostRecentDM
        self.mostRecentMention = mostRecentMention
        self.mostRecentChannel = mostRecentChannel
    }
}

enum ConnectionStatus: Sendable {
    case connected
    case reconnecting
    case error(String)
    case offline
}

// MARK: - Relative Time

enum RelativeTime {
    static func format(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        return "\(days)d"
    }
}

// MARK: - Grouped Sections

struct GroupedSection {
    let section: ChannelSection
    let items: [ConversationItem]
}

// MARK: - State Store

@MainActor
final class StateStore: ObservableObject {
    @Published var items: [ConversationItem] = []
    @Published var aggregated = AggregatedCounts()
    @Published var connectionStatus: ConnectionStatus = .reconnecting
    @Published var config: AppConfig
    @Published var sidebarSections: [ChannelSection] = []

    private var nameCache = NameCache()
    private var pollTimer: Timer?
    private var sectionTimer: Timer?
    private var cachedCookie: String?  // cached xoxd cookie
    private var workspace: WorkspaceMetadata?
    private var cachedToken: String?

    init(config: AppConfig = AppConfig()) {
        self.config = config
    }

    // MARK: - Polling

    func startPolling() {
        Task { await poll() }

        let interval = TimeInterval(config.pollIntervalSeconds)
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.poll()
            }
        }

        // Section polling uses a slower 5-minute timer.
        // The first section poll is triggered from poll() after credentials are set,
        // to avoid racing with the async credential extraction.
        sectionTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.pollSections()
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        sectionTimer?.invalidate()
        sectionTimer = nil
    }

    func pollSections() async {
        guard let cookie = cachedCookie, let token = cachedToken else { return }

        do {
            let domain = workspace?.domain ?? "slack"
            let teamId = workspace?.id ?? "default"
            let client = SlackAPIClient(token: token, cookie: cookie, domain: domain)
            let response = try await client.fetchUserBoot(teamId: teamId)
            self.sidebarSections = response.channelSections
        } catch {
            // Silently keep cached sections on failure
        }
    }

    func poll() async {
        do {
            // 1. Get credentials
            let token: String
            let cookie: String
            if let cached = cachedCookie, let cachedTok = cachedToken {
                token = cachedTok
                cookie = cached
            } else {
                let result = try TokenExtractor.extractCredentials()
                token = result.token
                cookie = result.cookie
                workspace = result.workspace
                cachedCookie = cookie
                cachedToken = token
            }

            let domain = workspace?.domain ?? "slack"
            let teamId = workspace?.id ?? "default"
            let client = SlackAPIClient(token: token, cookie: cookie, domain: domain)

            if let (newItems, _) = await pollWorkspace(client: client, teamId: teamId) {
                let sorted = newItems.sorted {
                    ($0.latestTimestamp ?? .distantPast) > ($1.latestTimestamp ?? .distantPast)
                }
                self.items = sorted
                self.aggregated = AggregatedCounts(from: sorted)
                self.connectionStatus = .connected

                if sidebarSections.isEmpty {
                    await pollSections()
                }
            }

        } catch let apiError as SlackAPIError {
            switch apiError {
            case .authError:
                self.connectionStatus = .reconnecting
                self.cachedCookie = nil
                self.cachedToken = nil
            case .rateLimited:
                break
            case .networkError:
                self.connectionStatus = .offline
            default:
                self.connectionStatus = .error(apiError.localizedDescription)
            }
        } catch {
            self.connectionStatus = .error(error.localizedDescription)
            self.cachedCookie = nil
            self.cachedToken = nil
        }
    }

    private func pollWorkspace(client: SlackAPIClient, teamId: String) async -> ([ConversationItem], ChannelBadges)? {
        do {
            // Fetch counts and muted channels in parallel
            async let countsTask = client.fetchCounts(teamId: teamId)
            async let prefsTask = client.fetchUserPrefs(teamId: teamId)

            let counts = try await countsTask
            // Muted channels from user prefs — fall back to empty set if prefs fetch fails
            let mutedIds: Set<String>
            if let prefs = try? await prefsTask {
                mutedIds = prefs.prefs?.mutedChannelIds ?? []
            } else {
                mutedIds = []
            }

            var items: [ConversationItem] = []
            let badges = counts.channelBadges

            // Channels with @mentions (show even if muted — mentions are important)
            for ch in counts.channels where ch.mentionCount > 0 {
                let name = await resolveChannelName(ch.id, client: client, teamId: teamId)
                items.append(ConversationItem(from: ch, name: name, type: .mention, teamId: teamId))
            }

            // Channels with unreads (no mentions) — skip muted channels
            for ch in counts.channels where ch.hasUnreads && ch.mentionCount == 0 && !mutedIds.contains(ch.id) {
                let name = await resolveChannelName(ch.id, client: client, teamId: teamId)
                items.append(ConversationItem(from: ch, name: name, type: .channel, teamId: teamId))
            }

            for im in counts.ims where im.hasUnreads || im.mentionCount > 0 {
                let (name, userId) = await resolveDMName(im.id, client: client, teamId: teamId)
                items.append(ConversationItem(from: im, name: name, type: .dm, teamId: teamId, userId: userId))
            }

            for mpim in counts.mpims where mpim.hasUnreads || mpim.mentionCount > 0 {
                let name = await resolveChannelName(mpim.id, client: client, teamId: teamId)
                items.append(ConversationItem(from: mpim, name: name, type: .dm, teamId: teamId))
            }

            return (items, badges)
        } catch {
            return nil
        }
    }

    // MARK: - Name Resolution

    private func resolveChannelName(_ channelId: String, client: SlackAPIClient, teamId: String? = nil) async -> String {
        if let cached = nameCache.channelName(for: channelId) {
            return cached
        }

        do {
            let info = try await client.fetchConversationInfo(channelId: channelId, teamId: teamId)
            let name = info.channel.name ?? channelId
            nameCache.setChannelName(name, for: channelId)
            if info.channel.isIm == true, let userId = info.channel.user {
                nameCache.setDMUser(userId, for: channelId)
            }
            return name
        } catch {
            return channelId
        }
    }

    private func resolveDMName(_ channelId: String, client: SlackAPIClient, teamId: String? = nil) async -> (
        String, String?
    ) {
        var userId = nameCache.dmUser(for: channelId)

        if userId == nil {
            if let info = try? await client.fetchConversationInfo(channelId: channelId, teamId: teamId),
                info.channel.isIm == true
            {
                userId = info.channel.user
                if let uid = userId {
                    nameCache.setDMUser(uid, for: channelId)
                }
            }
        }

        guard let uid = userId else {
            return (channelId, nil)
        }

        if let cached = nameCache.userName(for: uid) {
            return (cached, uid)
        }

        do {
            let userInfo = try await client.fetchUserInfo(userId: uid, teamId: teamId)
            let displayName = userInfo.user.displayLabel
            nameCache.setUserName(displayName, for: uid)
            return (displayName, uid)
        } catch {
            return (uid, uid)
        }
    }

    // MARK: - Section Grouping

    nonisolated static func groupBySections(items: [ConversationItem], sections: [ChannelSection]) -> [GroupedSection] {
        guard !sections.isEmpty else {
            return fallbackGrouping(items: items)
        }

        var result: [GroupedSection] = []
        var assigned: Set<String> = []

        for section in sections {
            let sectionChannelIds = Set(section.channelIds)
            let matching = items.filter { sectionChannelIds.contains($0.id) && !assigned.contains($0.id) }
                .sorted { ($0.latestTimestamp ?? .distantPast) > ($1.latestTimestamp ?? .distantPast) }
            if !matching.isEmpty {
                result.append(GroupedSection(section: section, items: matching))
                matching.forEach { assigned.insert($0.id) }
            }
        }

        // Uncategorized: items not in any section
        let uncategorized = items.filter { !assigned.contains($0.id) }
            .sorted { ($0.latestTimestamp ?? .distantPast) > ($1.latestTimestamp ?? .distantPast) }
        if !uncategorized.isEmpty {
            let uncatSection = ChannelSection(id: "uncategorized", name: "Uncategorized", type: "uncategorized", channelIds: [])
            result.append(GroupedSection(section: uncatSection, items: uncategorized))
        }

        return result
    }

    private nonisolated static func fallbackGrouping(items: [ConversationItem]) -> [GroupedSection] {
        var result: [GroupedSection] = []

        let dms = items.filter { $0.type == .dm || $0.type == .mpim }
            .sorted { ($0.latestTimestamp ?? .distantPast) > ($1.latestTimestamp ?? .distantPast) }
        if !dms.isEmpty {
            result.append(GroupedSection(
                section: ChannelSection(id: "fallback-dms", name: "Direct Messages", type: "default_dms", channelIds: []),
                items: dms))
        }

        let mentions = items.filter { $0.type == .mention }
            .sorted { ($0.latestTimestamp ?? .distantPast) > ($1.latestTimestamp ?? .distantPast) }
        if !mentions.isEmpty {
            result.append(GroupedSection(
                section: ChannelSection(id: "fallback-mentions", name: "Mentions", type: "mentions", channelIds: []),
                items: mentions))
        }

        let channels = items.filter { $0.type == .channel }
            .sorted { ($0.latestTimestamp ?? .distantPast) > ($1.latestTimestamp ?? .distantPast) }
        if !channels.isEmpty {
            result.append(GroupedSection(
                section: ChannelSection(id: "fallback-channels", name: "Channels", type: "default_channels", channelIds: []),
                items: channels))
        }

        return result
    }
}
