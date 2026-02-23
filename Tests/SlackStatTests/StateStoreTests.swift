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
    // C1 is in Starred (C3 not in items so doesn't appear)
    #expect(grouped[0].section.name == "Starred")
    #expect(grouped[0].items.count == 1)
    #expect(grouped[0].items[0].id == "C1")
    // C2 is in Engineering
    #expect(grouped[1].section.name == "Engineering")
    #expect(grouped[1].items.count == 1)
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
