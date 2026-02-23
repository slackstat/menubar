# Contributing to SlackStat

## Getting Started

1. Fork the repository
2. Create a feature branch: `git checkout -b my-feature`
3. Make your changes
4. Run tests: `swift test`
5. Commit and push
6. Open a pull request

## Guidelines

- **Run tests before submitting** — All tests must pass (`swift test`)
- **No external dependencies** — SlackStat uses only Apple frameworks via SPM. Do not add third-party packages.
- **Swift 6** — Use modern Swift concurrency patterns. Follow existing code style.
- **Swift Testing** — New tests should use the Swift Testing framework (`@Test`, `#expect`), not XCTest.
- **One concern per PR** — Keep pull requests focused on a single change.

## Reporting Issues

Open a [GitHub Issue](https://github.com/slackstat/menubar/issues) with:

- macOS version
- Steps to reproduce
- Expected vs. actual behavior

## Security

See [SECURITY.md](SECURITY.md) for reporting security vulnerabilities.
