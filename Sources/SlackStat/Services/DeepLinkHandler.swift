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

    /// Open the Slack app. The slack:// URI scheme does not support
    /// navigating to the Threads view, so this just brings Slack to front.
    static func openSlack(teamId: String) {
        let url = URL(string: "slack://open?team=\(teamId)")!
        NSWorkspace.shared.open(url)
    }
}
