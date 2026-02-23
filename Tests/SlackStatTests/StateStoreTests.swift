import Testing
import Foundation
@testable import SlackStat

@Test func testConversationItemFromCount() {
    let count = ConversationCount(
        id: "C123", lastRead: nil, latest: "1771625714.453859",
        updated: nil, historyInvalid: nil, mentionCount: 2, hasUnreads: true,
        isMuted: nil
    )
    let item = ConversationItem(from: count, name: "general", type: .channel, teamId: "T01")

    #expect(item.id == "C123")
    #expect(item.name == "general")
    #expect(item.mentionCount == 2)
    #expect(item.hasUnreads == true)
    #expect(item.type == .channel)
}

@Test func testAggregatedCounts() {
    let items = [
        ConversationItem(
            id: "D1", name: "Alice", type: .dm, teamId: "T01",
            hasUnreads: true, mentionCount: 1,
            latestTimestamp: Date(timeIntervalSince1970: 1_771_625_714)),
        ConversationItem(
            id: "C1", name: "general", type: .channel, teamId: "T01",
            hasUnreads: true, mentionCount: 0,
            latestTimestamp: Date(timeIntervalSince1970: 1_771_625_700)),
        ConversationItem(
            id: "C2", name: "engineering", type: .mention, teamId: "T01",
            hasUnreads: true, mentionCount: 3,
            latestTimestamp: Date(timeIntervalSince1970: 1_771_625_710)),
    ]

    let agg = AggregatedCounts(from: items)
    #expect(agg.totalDMs == 1)
    #expect(agg.totalMentions == 1)
    #expect(agg.totalChannels == 1)
    #expect(agg.mostRecentDM == Date(timeIntervalSince1970: 1_771_625_714))
    #expect(agg.mostRecentMention == Date(timeIntervalSince1970: 1_771_625_710))
    #expect(agg.mostRecentChannel == Date(timeIntervalSince1970: 1_771_625_700))
}

@Test func testAggregatedCountsPerCategoryTimestamps() throws {
    let now = Date()
    let items = [
        ConversationItem(id: "C1", name: "#general", type: .dm,
                         teamId: "W1", hasUnreads: true, mentionCount: 0,
                         latestTimestamp: now.addingTimeInterval(-180)),
        ConversationItem(id: "C2", name: "#random", type: .mention,
                         teamId: "W1", hasUnreads: true, mentionCount: 2,
                         latestTimestamp: now.addingTimeInterval(-3600)),
        ConversationItem(id: "C3", name: "#eng", type: .channel,
                         teamId: "W1", hasUnreads: true, mentionCount: 0,
                         latestTimestamp: now.addingTimeInterval(-60)),
        ConversationItem(id: "C4", name: "@bob", type: .dm,
                         teamId: "W1", hasUnreads: true, mentionCount: 0,
                         latestTimestamp: now.addingTimeInterval(-600)),
    ]
    let agg = AggregatedCounts(from: items)
    #expect(agg.totalDMs == 2)
    #expect(agg.totalMentions == 1)
    #expect(agg.totalChannels == 1)
    // mostRecentDM should be 180s ago (the more recent DM)
    let dmTs = try #require(agg.mostRecentDM)
    #expect(abs(dmTs.timeIntervalSince1970 - now.addingTimeInterval(-180).timeIntervalSince1970) < 1.0)
    // mostRecentMention should be 3600s ago
    let mentionTs = try #require(agg.mostRecentMention)
    #expect(abs(mentionTs.timeIntervalSince1970 - now.addingTimeInterval(-3600).timeIntervalSince1970) < 1.0)
    // mostRecentChannel should be 60s ago
    let channelTs = try #require(agg.mostRecentChannel)
    #expect(abs(channelTs.timeIntervalSince1970 - now.addingTimeInterval(-60).timeIntervalSince1970) < 1.0)
}

@Test func testRelativeTimeFormatting() {
    let now = Date()
    #expect(RelativeTime.format(now.addingTimeInterval(-30)) == "30s")
    #expect(RelativeTime.format(now.addingTimeInterval(-90)) == "1m")
    #expect(RelativeTime.format(now.addingTimeInterval(-3600)) == "1h")
    #expect(RelativeTime.format(now.addingTimeInterval(-7200)) == "2h")
    #expect(RelativeTime.format(now.addingTimeInterval(-86400)) == "1d")
}

@Test func testSectionMapping() {
    let sections = [
        ChannelSection(id: "S1", name: "Starred", type: "starred", channelIds: ["C1", "C3"]),
        ChannelSection(id: "S2", name: "Engineering", type: "custom", channelIds: ["C2"]),
        ChannelSection(id: "S3", name: "DMs", type: "default_dms", channelIds: ["D1"]),
    ]
    let items = [
        ConversationItem(id: "C1", name: "#general", type: .channel,
                         teamId: "W1", hasUnreads: true, mentionCount: 0,
                         latestTimestamp: Date()),
        ConversationItem(id: "C2", name: "#eng", type: .mention,
                         teamId: "W1", hasUnreads: true, mentionCount: 3,
                         latestTimestamp: Date()),
        ConversationItem(id: "D1", name: "@alice", type: .dm,
                         teamId: "W1", hasUnreads: true, mentionCount: 1,
                         latestTimestamp: Date()),
        ConversationItem(id: "C99", name: "#orphan", type: .channel,
                         teamId: "W1", hasUnreads: true, mentionCount: 0,
                         latestTimestamp: Date()),
    ]

    let grouped = StateStore.groupBySections(items: items, sections: sections)
    // C2 is a mention — goes to dedicated Mentions section first
    #expect(grouped[0].section.name == "Mentions")
    #expect(grouped[0].items.count == 1)
    #expect(grouped[0].items[0].id == "C2")
    // C1 is in Starred (C3 not in items so doesn't appear)
    #expect(grouped[1].section.name == "Starred")
    #expect(grouped[1].items.count == 1)
    #expect(grouped[1].items[0].id == "C1")
    // D1 is in DMs
    #expect(grouped[2].section.name == "DMs")
    #expect(grouped[2].items.count == 1)
    // C99 is in Uncategorized
    #expect(grouped[3].section.name == "Uncategorized")
    #expect(grouped[3].items.count == 1)
}

@Test func testSectionMappingEmptySectionsHidden() {
    let sections = [
        ChannelSection(id: "S1", name: "Starred", type: "starred", channelIds: ["C1"]),
        ChannelSection(id: "S2", name: "Empty", type: "custom", channelIds: ["C999"]),
    ]
    let items = [
        ConversationItem(id: "C1", name: "#general", type: .channel,
                         teamId: "W1", hasUnreads: true, mentionCount: 0,
                         latestTimestamp: Date()),
    ]

    let grouped = StateStore.groupBySections(items: items, sections: sections)
    #expect(grouped.count == 1)
    #expect(grouped[0].section.name == "Starred")
}

// MARK: - MenuBarTitle Tests

@Test func testMenuBarTitleAllCategories() {
    let now = Date()
    let agg = AggregatedCounts(
        totalDMs: 4, totalMentions: 2, totalChannels: 15,
        mostRecentDM: now.addingTimeInterval(-180),
        mostRecentMention: now.addingTimeInterval(-3600),
        mostRecentChannel: now.addingTimeInterval(-2700)
    )
    let title = MenuBarTitle.format(aggregated: agg, now: now)
    #expect(title.contains("4"))
    #expect(title.contains("3m"))
    #expect(title.contains("2"))
    #expect(title.contains("1h"))
    #expect(title.contains("15"))
    #expect(title.contains("45m"))
}

@Test func testMenuBarTitleHidesZeroCategories() {
    let now = Date()
    let agg = AggregatedCounts(
        totalDMs: 3,
        mostRecentDM: now.addingTimeInterval(-60)
    )
    let title = MenuBarTitle.format(aggregated: agg, now: now)
    #expect(title.contains("3"))
    #expect(title.contains("1m"))
    #expect(!title.contains("@ "))
    #expect(!title.contains("# "))
}

@Test func testMenuBarTitleEmptyWhenNoActivity() {
    let agg = AggregatedCounts()
    let title = MenuBarTitle.format(aggregated: agg, now: Date())
    #expect(title == "")
}

@Test func testVirtualSectionAssignment() {
    // Simulate the real scenario: "Team" is a standard section with explicit IDs,
    // "Channels" is a virtual section (type "channels") with empty channelIds,
    // "Slack Connect" is a virtual section (type "slack_connect") with empty channelIds,
    // "Direct Messages" is a virtual section (type "direct_messages") with empty channelIds.
    let sections = [
        ChannelSection(id: "S1", name: "Team", type: "standard", channelIds: ["C001", "C002"]),
        ChannelSection(id: "S2", name: "Channels", type: "channels", channelIds: []),
        ChannelSection(id: "S3", name: "Slack Connect", type: "slack_connect", channelIds: []),
        ChannelSection(id: "S4", name: "Direct Messages", type: "direct_messages", channelIds: []),
    ]
    let items = [
        // C001 is in Team (explicit)
        ConversationItem(id: "C001", name: "team-general", type: .channel,
                         teamId: "W1", hasUnreads: true, mentionCount: 0,
                         latestTimestamp: Date()),
        // C003 is a regular channel not in any explicit section → should go to "Channels"
        ConversationItem(id: "C003", name: "random", type: .channel,
                         teamId: "W1", hasUnreads: true, mentionCount: 0,
                         latestTimestamp: Date()),
        // C004 is an ext_shared channel → should go to "Slack Connect"
        ConversationItem(id: "C004", name: "partner-shared", type: .channel,
                         teamId: "W1", hasUnreads: true, mentionCount: 0,
                         latestTimestamp: Date(), isExtShared: true),
        // D001 is a DM → should go to "Direct Messages"
        ConversationItem(id: "D001", name: "Alice", type: .dm,
                         teamId: "W1", hasUnreads: true, mentionCount: 1,
                         latestTimestamp: Date()),
    ]

    let grouped = StateStore.groupBySections(items: items, sections: sections)

    // Team should have C001
    let teamGroup = grouped.first { $0.section.name == "Team" }
    #expect(teamGroup != nil)
    #expect(teamGroup?.items.count == 1)
    #expect(teamGroup?.items[0].id == "C001")

    // Channels (virtual) should have C003
    let channelsGroup = grouped.first { $0.section.name == "Channels" }
    #expect(channelsGroup != nil)
    #expect(channelsGroup?.items.count == 1)
    #expect(channelsGroup?.items[0].id == "C003")

    // External Connections (virtual, renamed from "Slack Connect") should have C004
    let slackConnectGroup = grouped.first { $0.section.name == "External Connections" }
    #expect(slackConnectGroup != nil)
    #expect(slackConnectGroup?.items.count == 1)
    #expect(slackConnectGroup?.items[0].id == "C004")

    // Direct Messages (virtual) should have D001
    let dmsGroup = grouped.first { $0.section.name == "Direct Messages" }
    #expect(dmsGroup != nil)
    #expect(dmsGroup?.items.count == 1)
    #expect(dmsGroup?.items[0].id == "D001")

    // No uncategorized section
    let uncategorized = grouped.first { $0.section.name == "Uncategorized" }
    #expect(uncategorized == nil)
}

@Test func testVirtualSectionMentionsGoToCorrectSection() {
    // Mentions should always get their own "Mentions" section at the top,
    // regardless of which sidebar section the channel belongs to.
    let sections = [
        ChannelSection(id: "S1", name: "Team", type: "standard", channelIds: ["C001"]),
        ChannelSection(id: "S2", name: "Channels", type: "channels", channelIds: []),
    ]
    let items = [
        // C001 has a mention and is in Team's explicit channelIds
        ConversationItem(id: "C001", name: "team-general", type: .mention,
                         teamId: "W1", hasUnreads: true, mentionCount: 2,
                         latestTimestamp: Date()),
        // C002 has a mention but not in any explicit section
        ConversationItem(id: "C002", name: "random", type: .mention,
                         teamId: "W1", hasUnreads: true, mentionCount: 1,
                         latestTimestamp: Date()),
        // C003 is a regular unread channel
        ConversationItem(id: "C003", name: "eng", type: .channel,
                         teamId: "W1", hasUnreads: true, mentionCount: 0,
                         latestTimestamp: Date()),
    ]

    let grouped = StateStore.groupBySections(items: items, sections: sections)

    // Mentions section should be first and contain both mention items
    #expect(grouped[0].section.name == "Mentions")
    #expect(grouped[0].items.count == 2)
    let mentionIds = Set(grouped[0].items.map(\.id))
    #expect(mentionIds == Set(["C001", "C002"]))

    // C003 should go to Channels (virtual), not Mentions
    let channelsGroup = grouped.first { $0.section.name == "Channels" }
    #expect(channelsGroup != nil)
    #expect(channelsGroup?.items.count == 1)
    #expect(channelsGroup?.items[0].id == "C003")

    // Mentions should NOT appear in Team or Channels sections
    let teamGroup = grouped.first { $0.section.name == "Team" }
    #expect(teamGroup == nil)  // C001 is the only Team item but it's a mention, so Team is empty/absent
}

@Test func testFallbackGroupingWhenNoSections() {
    let items = [
        ConversationItem(id: "C1", name: "#general", type: .channel,
                         teamId: "W1", hasUnreads: true, mentionCount: 0,
                         latestTimestamp: Date()),
        ConversationItem(id: "D1", name: "@alice", type: .dm,
                         teamId: "W1", hasUnreads: true, mentionCount: 0,
                         latestTimestamp: Date()),
        ConversationItem(id: "C2", name: "#eng", type: .mention,
                         teamId: "W1", hasUnreads: true, mentionCount: 2,
                         latestTimestamp: Date()),
    ]

    let grouped = StateStore.groupBySections(items: items, sections: [])
    // Fallback: DMs, Mentions, Channels (only groups with items)
    #expect(grouped.count == 3)
    #expect(grouped[0].section.name == "Direct Messages")
    #expect(grouped[1].section.name == "Mentions")
    #expect(grouped[2].section.name == "Channels")
}
