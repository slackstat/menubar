import Foundation

enum MenuBarTitle {
    /// Formats the menu bar title string from aggregated counts.
    /// Returns empty string when no activity (caller should show icon only).
    static func format(aggregated: AggregatedCounts, now: Date = Date()) -> String {
        var parts: [String] = []

        if aggregated.totalDMs > 0, let ts = aggregated.mostRecentDM {
            let rel = RelativeTime.format(ts, now: now)
            parts.append("\u{1F4AC} \(aggregated.totalDMs) (\(rel))")
        }

        if aggregated.totalMentions > 0, let ts = aggregated.mostRecentMention {
            let rel = RelativeTime.format(ts, now: now)
            parts.append("@ \(aggregated.totalMentions) (\(rel))")
        }

        if aggregated.totalThreads > 0, let ts = aggregated.mostRecentThread {
            let rel = RelativeTime.format(ts, now: now)
            parts.append("\u{1F9F5} \(aggregated.totalThreads) (\(rel))")
        }

        if aggregated.totalChannels > 0, let ts = aggregated.mostRecentChannel {
            let rel = RelativeTime.format(ts, now: now)
            parts.append("# \(aggregated.totalChannels) (\(rel))")
        }

        return parts.joined(separator: "  ")
    }
}
