// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SlackStat",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SlackStat",
            path: "Sources/SlackStat",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Security"),
                .linkedFramework("SwiftUI"),
            ]
        ),
        .testTarget(
            name: "SlackStatTests",
            dependencies: ["SlackStat"],
            path: "Tests/SlackStatTests"
        ),
    ]
)
