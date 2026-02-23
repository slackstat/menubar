import Foundation

// MARK: - client.counts response

struct ClientCountsResponse: Codable, Sendable {
    let ok: Bool
    let channels: [ConversationCount]
    let ims: [ConversationCount]
    let mpims: [ConversationCount]
    let threads: ThreadCount
    let channelBadges: ChannelBadges

    enum CodingKeys: String, CodingKey {
        case ok, channels, ims, mpims, threads
        case channelBadges = "channel_badges"
    }
}

struct ConversationCount: Codable, Sendable, Identifiable {
    let id: String
    let lastRead: String?
    let latest: String?
    let updated: String?
    let historyInvalid: String?
    let mentionCount: Int
    let hasUnreads: Bool
    let isMuted: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case lastRead = "last_read"
        case latest, updated
        case historyInvalid = "history_invalid"
        case mentionCount = "mention_count"
        case hasUnreads = "has_unreads"
        case isMuted = "is_muted"
    }

    /// Parse the `latest` Slack timestamp (e.g., "1771625714.453859") into a Date
    var latestDate: Date? {
        guard let latest, let seconds = Double(latest.split(separator: ".").first ?? "") else {
            return nil
        }
        return Date(timeIntervalSince1970: seconds)
    }
}

struct ThreadCount: Codable, Sendable {
    let hasUnreads: Bool
    let mentionCount: Int

    enum CodingKeys: String, CodingKey {
        case hasUnreads = "has_unreads"
        case mentionCount = "mention_count"
    }
}

struct ChannelBadges: Codable, Sendable {
    let channels: Int
    let dms: Int
    let appDms: Int
    let threadMentions: Int
    let threadUnreads: Int

    enum CodingKeys: String, CodingKey {
        case channels, dms
        case appDms = "app_dms"
        case threadMentions = "thread_mentions"
        case threadUnreads = "thread_unreads"
    }
}

// MARK: - conversations.info response

struct ConversationInfoResponse: Codable, Sendable {
    let ok: Bool
    let channel: ConversationInfo
}

struct ConversationInfo: Codable, Sendable {
    let id: String
    let name: String?
    let isChannel: Bool?
    let isIm: Bool?
    let isMpim: Bool?
    let user: String?

    enum CodingKeys: String, CodingKey {
        case id, name, user
        case isChannel = "is_channel"
        case isIm = "is_im"
        case isMpim = "is_mpim"
    }
}

// MARK: - users.info response

struct UserInfoResponse: Codable, Sendable {
    let ok: Bool
    let user: UserInfo
}

struct UserInfo: Codable, Sendable {
    let id: String
    let name: String
    let realName: String?
    let profile: UserProfile
    let isBot: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, profile
        case realName = "real_name"
        case isBot = "is_bot"
    }

    var displayLabel: String {
        profile.displayName.isEmpty == false ? profile.displayName : (realName ?? name)
    }
}

struct UserProfile: Codable, Sendable {
    let displayName: String
    let image32: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case image32 = "image_32"
    }
}

// MARK: - auth.test response

struct AuthTestResponse: Codable, Sendable {
    let ok: Bool
    let teamId: String?
    let userId: String?
    let enterpriseId: String?
    let team: String?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case teamId = "team_id"
        case userId = "user_id"
        case enterpriseId = "enterprise_id"
        case team
        case url
    }
}

// MARK: - Slack API error response

struct SlackErrorResponse: Codable, Sendable {
    let ok: Bool
    let error: String?
}

// MARK: - users.prefs.get response (for muted channels)

struct UserPrefsResponse: Codable, Sendable {
    let ok: Bool
    let prefs: UserPrefs?
}

struct UserPrefs: Codable, Sendable {
    /// Legacy comma-separated muted channel IDs (older Slack workspaces)
    let mutedChannels: String?
    /// JSON string containing per-channel notification prefs including mute state
    /// (enterprise/unified client format)
    let allNotificationsPrefs: String?

    enum CodingKeys: String, CodingKey {
        case mutedChannels = "muted_channels"
        case allNotificationsPrefs = "all_notifications_prefs"
    }

    /// Parse muted channel IDs from whichever format is available.
    /// Enterprise/unified clients use `all_notifications_prefs` (JSON string with per-channel
    /// `{"muted": true}`). Older workspaces may use `muted_channels` (comma-separated IDs).
    var mutedChannelIds: Set<String> {
        // Try all_notifications_prefs first (enterprise/unified client)
        if let raw = allNotificationsPrefs, !raw.isEmpty,
           let data = raw.data(using: .utf8),
           let parsed = try? JSONDecoder().decode(AllNotificationsPrefs.self, from: data) {
            let muted = parsed.channels.filter { $0.value.muted == true }.map(\.key)
            if !muted.isEmpty {
                return Set(muted)
            }
        }

        // Fall back to legacy muted_channels (comma-separated)
        if let raw = mutedChannels, !raw.isEmpty {
            return Set(raw.split(separator: ",").map(String.init))
        }

        return []
    }
}

/// Internal structure for parsing the `all_notifications_prefs` JSON string
private struct AllNotificationsPrefs: Codable {
    let channels: [String: ChannelNotificationPref]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.channels = (try? container.decode([String: ChannelNotificationPref].self, forKey: .channels)) ?? [:]
    }

    enum CodingKeys: String, CodingKey {
        case channels
    }
}

private struct ChannelNotificationPref: Codable {
    let muted: Bool?
}

// MARK: - Workspace metadata from root-state.json

struct WorkspaceMetadata: Codable, Sendable {
    let id: String
    let domain: String
    let name: String
    let url: String
    let icon: WorkspaceIcon?
    let order: Int?
}

struct WorkspaceIcon: Codable, Sendable {
    let image34: String?
    let image44: String?
    let image68: String?

    enum CodingKeys: String, CodingKey {
        case image34 = "image_34"
        case image44 = "image_44"
        case image68 = "image_68"
    }

    var bestURL: String? {
        image44 ?? image34 ?? image68
    }
}

// MARK: - Sidebar Sections (from client.userBoot)

struct UserBootSectionsResponse: Codable, Sendable {
    let ok: Bool
    let channelSections: [ChannelSection]

    enum CodingKeys: String, CodingKey {
        case ok
        case channelSections = "channel_sections"
    }
}

struct ChannelSection: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let type: String
    let channelIds: [String]

    enum CodingKeys: String, CodingKey {
        case id = "channel_section_id"
        case name
        case type
        case channelIdsPage = "channel_ids_page"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.type = try container.decode(String.self, forKey: .type)
        let page = try container.decode(ChannelIdsPage.self, forKey: .channelIdsPage)
        self.channelIds = page.channelIds
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(ChannelIdsPage(channelIds: channelIds), forKey: .channelIdsPage)
    }

    /// For programmatic construction (tests, fallback)
    init(id: String, name: String, type: String, channelIds: [String]) {
        self.id = id
        self.name = name
        self.type = type
        self.channelIds = channelIds
    }
}

struct ChannelIdsPage: Codable, Sendable {
    let channelIds: [String]

    enum CodingKeys: String, CodingKey {
        case channelIds = "channel_ids"
    }
}
