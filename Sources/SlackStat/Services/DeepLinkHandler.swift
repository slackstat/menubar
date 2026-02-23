import AppKit
import Foundation

enum DeepLinkHandler {
    static func slackURL(teamId: String, channelId: String) -> URL {
        URL(string: "slack://channel?team=\(teamId)&id=\(channelId)")!
    }

    static func openInSlack(teamId: String, channelId: String) {
        let url = slackURL(teamId: teamId, channelId: channelId)
        NSWorkspace.shared.open(url)
    }
}
