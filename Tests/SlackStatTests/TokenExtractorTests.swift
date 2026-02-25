import Testing
import Foundation
@testable import SlackStat

@Test func testParseWorkspacesFromRootState() throws {
    let json = """
    {
        "workspaces": {
            "E00EXAMPLE": {
                "id": "E00EXAMPLE",
                "domain": "example-corp",
                "name": "Example Corp",
                "url": "https://example-corp.enterprise.slack.com/",
                "order": 0
            }
        }
    }
    """.data(using: .utf8)!

    let parsed = try TokenExtractor.parseWorkspaces(from: json)
    #expect(parsed.count == 1)
    #expect(parsed[0].domain == "example-corp")
    #expect(parsed[0].name == "Example Corp")
}

@Test func testExtractXoxcTokenFromBytes() throws {
    // Simulate LevelDB content with an xoxc token embedded
    // Real tokens are 80-120+ chars; use a realistic-length test token
    var data = Data(repeating: 0, count: 50)
    let tokenStr = "xoxc-1234567890-abcdef0123456789-abcdef0123456789-aabbccddeeff00112233445566778899aabb"
    data.append(tokenStr.data(using: .utf8)!)
    data.append(Data([0x00, 0x22])) // null and quote as delimiters

    let token = TokenExtractor.extractXoxcToken(from: data)
    #expect(token == tokenStr)
}

@Test func testExtractXoxcTokenReturnsNilWhenMissing() {
    let data = Data("no token here at all".utf8)
    let token = TokenExtractor.extractXoxcToken(from: data)
    #expect(token == nil)
}

@Test func testDecryptChromeValue() throws {
    let key = Data(repeating: 0xAB, count: 16)
    let iv = Data(repeating: 0x20, count: 16)
    let plaintext = "xoxd-test-cookie-value"

    // Encrypt to create test data
    let encrypted = try TokenExtractor.aesCBCEncrypt(
        data: Data(plaintext.utf8),
        key: key,
        iv: iv
    )

    // Now decrypt
    let decrypted = try TokenExtractor.aesCBCDecrypt(
        data: encrypted,
        key: key,
        iv: iv
    )

    let result = String(data: decrypted, encoding: .utf8)
    #expect(result == plaintext)
}

@Test func testSlackDataPathDetection() {
    let path = TokenExtractor.slackDataPath
    #expect(path.hasSuffix("Application Support/Slack"))
    // Must be one of the two known locations
    let isDirectDownload = path.contains("Library/Application Support/Slack")
        && !path.contains("Containers")
    let isAppStore = path.contains("Containers/com.tinyspeck.slackmacgap")
    #expect(isDirectDownload || isAppStore)
}
