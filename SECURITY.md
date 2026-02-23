# Security

## What SlackStat Accesses

SlackStat reads authentication data from the Slack desktop app's local storage to communicate with the Slack API on your behalf. Specifically:

### Files read
- `~/Library/Application Support/Slack/Local Storage/leveldb/` — LevelDB files containing `xoxc-` session tokens
- `~/Library/Application Support/Slack/Cookies` — SQLite database containing the encrypted `xoxd-` session cookie
- `~/Library/Application Support/Slack/storage/root-state.json` — Workspace metadata (name, domain)

### Keychain access
- **Slack Safe Storage** — SlackStat reads the Slack desktop app's encryption password from the macOS Keychain using `/usr/bin/security find-generic-password`. This password is used to decrypt the session cookie. macOS may prompt you to allow this access.

### Temporary files
- `/tmp/slackstat_cookies_<PID>` — A temporary copy of Slack's Cookies database, created to avoid locking Slack's open database. Deleted immediately after reading via `defer`.

### Network
- HTTPS requests to `*.slack.com/api/` — The only network calls SlackStat makes. These use Slack's internal client APIs (`client.counts`, `client.userBoot`, `conversations.info`, `users.info`, `users.prefs.get`).

## What SlackStat Does NOT Do

- Does not write tokens or credentials to disk
- Does not send data to any server other than Slack
- Does not include telemetry, analytics, or crash reporting
- Does not modify any Slack files

## Reporting Vulnerabilities

If you discover a security vulnerability, please report it by opening a [GitHub Issue](https://github.com/slackstat/menubar/issues) with the label "security". For sensitive disclosures, include minimal details in the public issue and request a private channel for the full report.
