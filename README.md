# SlackStat

Slack unread counts in your macOS menu bar.

SlackStat is a native macOS menu bar app that shows your Slack unread message counts at a glance. It reads your Slack desktop app's authentication tokens locally and polls the Slack API to display conversations grouped by your sidebar sections.

## Features

- **Menu bar counts** — See unread DMs, mentions, and channel messages with relative timestamps: `💬 4 (3m)  @ 2 (1h)  # 15 (45m)`
- **Sidebar grouping** — Conversations organized by your actual Slack sidebar sections (Starred, custom sections, etc.)
- **Deep links** — Click any conversation to open it directly in Slack
- **Launch at login** — Start automatically with macOS
- **Zero dependencies** — Pure Swift Package Manager project, no external libraries
- **Privacy-first** — All data stays on your machine. No telemetry, no analytics, no third-party services.

## Requirements

- macOS 14 (Sonoma) or later
- [Slack desktop app](https://slack.com/downloads/mac) installed and signed in

## Install

### From source (recommended)

```bash
git clone https://github.com/slackstat/menubar.git
cd menubar
swift build -c release
cp .build/release/SlackStat /usr/local/bin/
```

Then run `SlackStat` from Terminal, or move the binary wherever you prefer.

### From GitHub Releases

Download the latest `.app` bundle from [Releases](https://github.com/slackstat/menubar/releases).

> **Important:** macOS will show a warning that SlackStat "is damaged and can't be opened." This is normal — it happens because the app is not signed with an Apple Developer certificate. To fix it, run this command in Terminal before opening the app:
>
> ```bash
> xattr -cr /path/to/SlackStat.app
> ```
>
> Then open SlackStat normally. You only need to do this once.

## How It Works

SlackStat reads authentication tokens directly from the Slack desktop app's local storage on your machine:

1. **Token extraction** — Reads `xoxc-` tokens from Slack's LevelDB files in `~/Library/Application Support/Slack/`
2. **Cookie decryption** — Decrypts the `xoxd-` session cookie from Slack's Cookies database using the Keychain password (via `/usr/bin/security`)
3. **API polling** — Polls `client.counts` every 30 seconds (configurable) for unread counts, and `client.userBoot` every 5 minutes for sidebar sections
4. **Display** — Shows aggregated counts in the menu bar with a dropdown menu of conversations

No OAuth flow, no bot tokens, no Slack app installation required.

## Privacy & Security

- **Tokens never leave your machine** — Authentication tokens are held in memory only and are never written to disk by SlackStat
- **No network calls except to Slack** — The only HTTP requests go to `*.slack.com/api/` endpoints
- **No telemetry or analytics** — Zero tracking, zero data collection
- **Temporary files cleaned up** — A copy of Slack's Cookies database is made to `/tmp/` for reading and immediately deleted
- **Open source** — Full source code available for audit

See [SECURITY.md](SECURITY.md) for details on what SlackStat accesses and responsible disclosure.

## Limitations

- **Single workspace only** — SlackStat works with one Slack workspace at a time (the first one found in your Slack app). Enterprise Grid setups with multiple workspaces are not supported.
- **Unsigned binary** — The app is not signed with an Apple Developer certificate, so Gatekeeper will block it on first launch (see install instructions above).
- **Requires Slack desktop app** — SlackStat reads tokens from the Slack desktop app. It does not work with Slack in a browser.

## Configuration

Settings are stored in `~/.config/slackstat/config.json`. You can also configure via the Preferences window (click the menu bar icon → Preferences).

- **Poll interval** — How often to check for new messages (10–120 seconds, default 30)
- **Launch at login** — Start SlackStat when you log in to macOS

## Development

```bash
# Build
swift build

# Run
.build/debug/SlackStat

# Test
swift test

# Release build
swift build -c release
```

## License

[MIT](LICENSE)
