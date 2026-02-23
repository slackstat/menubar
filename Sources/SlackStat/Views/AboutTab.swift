import SwiftUI

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "number.square.fill")
                .resizable()
                .frame(width: 64, height: 64)
                .foregroundStyle(.blue)

            Text("SlackStat")
                .font(.title2)
                .fontWeight(.bold)

            Text("Version \(appVersion)")
                .foregroundStyle(.secondary)

            Text("Slack unread counts in your menu bar")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Link("GitHub Repository",
                 destination: URL(string: "https://github.com/slackstat/menubar")!)
                .font(.subheadline)

            Text("MIT License")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
