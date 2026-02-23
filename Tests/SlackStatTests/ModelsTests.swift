import Testing
import Foundation
@testable import SlackStat

@Test func testClientCountsDecoding() throws {
    let json = """
    {
        "ok": true,
        "channels": [
            {"id": "C00TEST01", "last_read": "1770999657.289449", "latest": "1771625714.453859",
             "updated": "1771693796.022900", "history_invalid": "1770306140.004900",
             "mention_count": 2, "has_unreads": true}
        ],
        "ims": [
            {"id": "D00TEST01", "last_read": "1771728116.697349", "latest": "1771466036.904419",
             "updated": "1771596535.000500", "history_invalid": "1771776367.000100",
             "mention_count": 1, "has_unreads": true}
        ],
        "mpims": [
            {"id": "C00TEST02", "last_read": "1771618558.143129", "latest": "1771618558.143129",
             "updated": "1771616830.001300", "history_invalid": "1771435153.000100",
             "mention_count": 0, "has_unreads": false}
        ],
        "threads": {"has_unreads": false, "mention_count": 0},
        "channel_badges": {"channels": 1, "dms": 2, "app_dms": 0, "thread_mentions": 0, "thread_unreads": 0}
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(ClientCountsResponse.self, from: json)
    #expect(response.ok == true)
    #expect(response.channels.count == 1)
    #expect(response.channels[0].id == "C00TEST01")
    #expect(response.channels[0].mentionCount == 2)
    #expect(response.channels[0].hasUnreads == true)
    #expect(response.ims.count == 1)
    #expect(response.ims[0].id == "D00TEST01")
    #expect(response.mpims.count == 1)
    #expect(response.threads.mentionCount == 0)
    #expect(response.channelBadges.dms == 2)
}

@Test func testConversationInfoDecoding() throws {
    let json = """
    {
        "ok": true,
        "channel": {
            "id": "C00TEST01",
            "name": "general",
            "is_channel": true,
            "is_im": false,
            "is_mpim": false,
            "user": ""
        }
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(ConversationInfoResponse.self, from: json)
    #expect(response.ok == true)
    #expect(response.channel.name == "general")
    #expect(response.channel.isChannel == true)
}

@Test func testUserInfoDecoding() throws {
    let json = """
    {
        "ok": true,
        "user": {
            "id": "U00TEST01",
            "name": "testuser",
            "real_name": "Test User",
            "profile": {
                "display_name": "Test User",
                "image_32": "https://example.com/avatar.png"
            },
            "is_bot": false
        }
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(UserInfoResponse.self, from: json)
    #expect(response.ok == true)
    #expect(response.user.realName == "Test User")
    #expect(response.user.profile.displayName == "Test User")
    #expect(response.user.isBot == false)
}

@Test func testAppConfigDefaults() throws {
    let config = AppConfig()
    #expect(config.pollIntervalSeconds == 30)
}

@Test func testAppConfigRoundTrip() throws {
    let config = AppConfig(pollIntervalSeconds: 60)
    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
    #expect(decoded.pollIntervalSeconds == 60)
}

@Test func testUserPrefsDecoding() throws {
    // Legacy format: muted_channels as comma-separated string
    let json = """
    {
        "ok": true,
        "prefs": {
            "muted_channels": "C00TEST01,C00TEST02,C00TEST03"
        }
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(UserPrefsResponse.self, from: json)
    #expect(response.ok == true)
    #expect(response.prefs?.mutedChannelIds == Set(["C00TEST01", "C00TEST02", "C00TEST03"]))
}

@Test func testUserPrefsEnterpriseFormat() throws {
    // Enterprise/unified client format: all_notifications_prefs JSON string
    let notifPrefs = """
    {"channels":{"C00TEST01":{"muted":true,"desktop":"default"},"C00TEST02":{"muted":true},"C00TEST03":{"muted":false},"C00TEST04":{"muted":true}},"global":{}}
    """
    let json = """
    {
        "ok": true,
        "prefs": {
            "all_notifications_prefs": \(String(data: try JSONEncoder().encode(notifPrefs), encoding: .utf8)!)
        }
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(UserPrefsResponse.self, from: json)
    #expect(response.ok == true)
    let muted = response.prefs?.mutedChannelIds ?? []
    #expect(muted.contains("C00TEST01"))
    #expect(muted.contains("C00TEST02"))
    #expect(muted.contains("C00TEST04"))
    #expect(!muted.contains("C00TEST03"))  // muted: false
    #expect(muted.count == 3)
}

@Test func testUserPrefsEmptyMuted() throws {
    let json = """
    {
        "ok": true,
        "prefs": {
            "muted_channels": ""
        }
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(UserPrefsResponse.self, from: json)
    #expect(response.prefs?.mutedChannelIds.isEmpty == true)
}

@Test func testUserPrefsNilMuted() throws {
    let json = """
    {
        "ok": true,
        "prefs": {}
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(UserPrefsResponse.self, from: json)
    #expect(response.prefs?.mutedChannelIds.isEmpty == true)
}

@Test func testUserBootSidebarSectionDecoding() throws {
    let json = """
    {
        "ok": true,
        "channel_sections": [
            {
                "channel_section_id": "S1",
                "name": "Starred",
                "type": "starred",
                "channel_ids_page": { "channel_ids": ["C123", "C456"] },
                "style": "starred"
            },
            {
                "channel_section_id": "S2",
                "name": "Channels",
                "type": "default_channels",
                "channel_ids_page": { "channel_ids": ["C789"] },
                "style": "default"
            },
            {
                "channel_section_id": "S3",
                "name": "Direct Messages",
                "type": "default_dms",
                "channel_ids_page": { "channel_ids": ["D001", "D002"] },
                "style": "default"
            }
        ]
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(UserBootSectionsResponse.self, from: json)
    #expect(response.channelSections.count == 3)
    #expect(response.channelSections[0].id == "S1")
    #expect(response.channelSections[0].name == "Starred")
    #expect(response.channelSections[0].type == "starred")
    #expect(response.channelSections[0].channelIds == ["C123", "C456"])
    #expect(response.channelSections[2].channelIds == ["D001", "D002"])
}
