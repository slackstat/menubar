import Testing
import Foundation
@testable import SlackStat

@Test func testSlackDeepLinkGeneration() {
    let link = DeepLinkHandler.slackURL(teamId: "T01ABC", channelId: "C02DEF")
    #expect(link.absoluteString == "slack://channel?team=T01ABC&id=C02DEF")
}

@Test func testSlackDeepLinkForDM() {
    let link = DeepLinkHandler.slackURL(teamId: "T01ABC", channelId: "D03GHI")
    #expect(link.absoluteString == "slack://channel?team=T01ABC&id=D03GHI")
}
