import Testing
import Foundation
@testable import SlackStat

@Test func testBuildRequest() throws {
    let client = SlackAPIClient(token: "xoxc-test", cookie: "xoxd-test")
    let request = client.buildRequest(method: "client.counts", params: [:])

    #expect(request.url?.absoluteString == "https://slack.com/api/client.counts")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer xoxc-test")
    #expect(request.value(forHTTPHeaderField: "Cookie") == "d=xoxd-test")
    #expect(request.httpMethod == "POST")
}

@Test func testBuildRequestWithParams() throws {
    let client = SlackAPIClient(token: "xoxc-test", cookie: "xoxd-test")
    let request = client.buildRequest(method: "conversations.info", params: ["channel": "C123"])

    let body = String(data: request.httpBody!, encoding: .utf8)!
    #expect(body.contains("token=xoxc-test"))
    #expect(body.contains("channel=C123"))
}

@Test func testParseClientCountsResponse() throws {
    let json = """
    {
        "ok": true,
        "channels": [{"id": "C1", "mention_count": 1, "has_unreads": true, "latest": "1771625714.453859"}],
        "ims": [{"id": "D1", "mention_count": 0, "has_unreads": true, "latest": "1771466036.904419"}],
        "mpims": [],
        "threads": {"has_unreads": false, "mention_count": 0},
        "channel_badges": {"channels": 1, "dms": 1, "app_dms": 0, "thread_mentions": 0, "thread_unreads": 0}
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(ClientCountsResponse.self, from: json)
    #expect(response.channels.count == 1)
    #expect(response.channels[0].mentionCount == 1)
}
