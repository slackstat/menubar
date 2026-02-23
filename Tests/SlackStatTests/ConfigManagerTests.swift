import Testing
import Foundation
@testable import SlackStat

@Test func testConfigManagerLoadsDefaults() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let manager = ConfigManager(directory: tempDir)
    let config = manager.load()
    #expect(config.pollIntervalSeconds == 30)
}

@Test func testConfigManagerSavesAndLoads() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let manager = ConfigManager(directory: tempDir)
    var config = AppConfig()
    config.pollIntervalSeconds = 60
    try manager.save(config)

    let loaded = manager.load()
    #expect(loaded.pollIntervalSeconds == 60)
}
