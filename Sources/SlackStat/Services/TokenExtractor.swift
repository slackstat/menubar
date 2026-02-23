import CommonCrypto
import Foundation
import os

enum TokenExtractorError: Error, LocalizedError {
    case slackNotInstalled
    case noTokenFound
    case cookieDecryptionFailed(String)
    case keychainAccessFailed
    case rootStateParsingFailed

    var errorDescription: String? {
        switch self {
        case .slackNotInstalled: return "Slack desktop app not found"
        case .noTokenFound: return "No xoxc token found in Slack storage"
        case .cookieDecryptionFailed(let msg): return "Cookie decryption failed: \(msg)"
        case .keychainAccessFailed: return "Cannot access Slack Safe Storage in Keychain"
        case .rootStateParsingFailed: return "Failed to parse Slack root-state.json"
        }
    }
}

enum TokenExtractor {
    static let slackDataPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/Slack"
    }()

    private static let levelDBPath: String = {
        "\(slackDataPath)/Local Storage/leveldb"
    }()

    private static let cookiesPath: String = {
        "\(slackDataPath)/Cookies"
    }()

    private static let rootStatePath: String = {
        "\(slackDataPath)/storage/root-state.json"
    }()

    // MARK: - Public API

    /// Extract the first LevelDB token and decrypted xoxd cookie.
    static func extractCredentials() throws -> (token: String, cookie: String, workspace: WorkspaceMetadata?) {
        guard FileManager.default.fileExists(atPath: slackDataPath) else {
            throw TokenExtractorError.slackNotInstalled
        }

        let workspaces = try extractWorkspaces()
        let tokens = try extractAllXoxcTokensFromLevelDB()
        let cookie = try extractXoxdCookie()

        guard let token = tokens.first else {
            throw TokenExtractorError.noTokenFound
        }

        return (token, cookie, workspaces.first)
    }

    // MARK: - Workspace Discovery

    static func parseWorkspaces(from data: Data) throws -> [WorkspaceMetadata] {
        struct RootState: Codable {
            let workspaces: [String: WorkspaceMetadata]?
        }

        let rootState = try JSONDecoder().decode(RootState.self, from: data)
        guard let workspaces = rootState.workspaces else {
            return []
        }
        return Array(workspaces.values).sorted { ($0.order ?? 0) < ($1.order ?? 0) }
    }

    private static func extractWorkspaces() throws -> [WorkspaceMetadata] {
        let data = try Data(contentsOf: URL(fileURLWithPath: rootStatePath))
        return try parseWorkspaces(from: data)
    }

    // MARK: - xoxc Token Extraction

    /// Extract xoxc token from raw bytes (LevelDB content)
    static func extractXoxcToken(from data: Data) -> String? {
        extractAllXoxcTokens(from: data).first
    }

    /// Extract ALL xoxc tokens from raw bytes (LevelDB content)
    private static func extractAllXoxcTokens(from data: Data) -> [String] {
        let marker = Data("xoxc-".utf8)
        var tokens: [String] = []
        var searchStart = data.startIndex

        while searchStart < data.endIndex,
              let range = data.range(of: marker, in: searchStart..<data.endIndex) {
            var token = "xoxc-"
            var index = range.lowerBound + 5

            while index < data.count {
                let byte = data[index]
                let char = Character(UnicodeScalar(byte))
                if char.isLetter || char.isNumber || char == "-" || char == "_" {
                    token.append(char)
                    index += 1
                } else {
                    break
                }
            }

            // Real xoxc tokens are 80-120+ chars; reject short fragments
            if token.count > 50 {
                tokens.append(token)
            }
            searchStart = index
        }

        // Deduplicate preserving order
        var seen = Set<String>()
        return tokens.filter { seen.insert($0).inserted }
    }

    private static func extractAllXoxcTokensFromLevelDB() throws -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: levelDBPath) else {
            throw TokenExtractorError.slackNotInstalled
        }

        let files = try fm.contentsOfDirectory(atPath: levelDBPath)
            .filter { $0.hasSuffix(".ldb") || $0.hasSuffix(".log") }
            .map { "\(levelDBPath)/\($0)" }
            .sorted {
                (try? fm.attributesOfItem(atPath: $0)[.modificationDate] as? Date) ?? .distantPast
                    > (try? fm.attributesOfItem(atPath: $1)[.modificationDate] as? Date)
                        ?? .distantPast
            }

        var allTokens: [String] = []
        for file in files {
            let data = try Data(contentsOf: URL(fileURLWithPath: file))
            allTokens.append(contentsOf: extractAllXoxcTokens(from: data))
        }

        // Deduplicate
        var seen = Set<String>()
        return allTokens.filter { seen.insert($0).inserted }
    }

    // MARK: - xoxd Cookie Extraction

    private static func extractXoxdCookie() throws -> String {
        let keychainPassword = try getKeychainPassword()
        let key = try derivePBKDF2Key(password: keychainPassword)
        let encryptedCookie = try readEncryptedCookie()

        guard encryptedCookie.count > 3 else {
            throw TokenExtractorError.cookieDecryptionFailed("Cookie data too short")
        }
        let ciphertext = encryptedCookie.subdata(in: 3..<encryptedCookie.count)
        let iv = Data(repeating: 0x20, count: 16)

        let decrypted = try aesCBCDecrypt(data: ciphertext, key: key, iv: iv)

        guard let range = decrypted.range(of: Data("xoxd-".utf8)) else {
            throw TokenExtractorError.cookieDecryptionFailed("No xoxd token in decrypted cookie")
        }

        let cookieData = decrypted.subdata(in: range.lowerBound..<decrypted.count)
        guard
            let cookie = String(data: cookieData, encoding: .utf8)?
                .trimmingCharacters(in: .controlCharacters)
        else {
            throw TokenExtractorError.cookieDecryptionFailed("Could not decode cookie as UTF-8")
        }

        return cookie
    }

    private static let cachedKeychainPassword = OSAllocatedUnfairLock<String?>(initialState: nil)

    private static func getKeychainPassword() throws -> String {
        if let cached = cachedKeychainPassword.withLock({ $0 }) { return cached }

        // Use the security CLI tool to avoid Keychain authorization dialogs
        // that block unsigned binaries using SecItemCopyMatching.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Slack Safe Storage", "-g"]
        let pipe = Pipe()
        process.standardError = pipe  // -g outputs password to stderr
        process.standardOutput = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            throw TokenExtractorError.keychainAccessFailed
        }

        guard let range = output.range(of: #"password: "(.+)""#, options: .regularExpression) else {
            throw TokenExtractorError.keychainAccessFailed
        }
        let match = String(output[range])
        guard let start = match.range(of: "\""),
              let end = match.range(of: "\"", options: .backwards),
              start.lowerBound != end.lowerBound else {
            throw TokenExtractorError.keychainAccessFailed
        }
        let password = String(match[match.index(after: start.lowerBound)..<end.lowerBound])

        cachedKeychainPassword.withLock { $0 = password }
        return password
    }

    private static func derivePBKDF2Key(password: String) throws -> Data {
        let passwordData = password.data(using: .utf8)!
        let salt = "saltysalt".data(using: .utf8)!
        let iterations: UInt32 = 1003
        let keyLength = 16

        var derivedKey = Data(count: keyLength)
        let result = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            passwordData.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        iterations,
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }

        guard result == kCCSuccess else {
            throw TokenExtractorError.cookieDecryptionFailed("PBKDF2 derivation failed")
        }

        return derivedKey
    }

    private static func readEncryptedCookie() throws -> Data {
        let url = URL(fileURLWithPath: cookiesPath)
        let data = try readCookieFromSQLite(at: url, name: "d", domain: ".slack.com")
        return data
    }

    // MARK: - AES CBC (CommonCrypto)

    static func aesCBCDecrypt(data: Data, key: Data, iv: Data) throws -> Data {
        var outputLength = data.count + kCCBlockSizeAES128
        var outputData = Data(count: outputLength)

        let status = outputData.withUnsafeMutableBytes { outputBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, key.count,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress, data.count,
                            outputBytes.baseAddress, outputLength,
                            &outputLength
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw TokenExtractorError.cookieDecryptionFailed(
                "AES decryption failed with status \(status)")
        }

        outputData.count = outputLength
        return outputData
    }

    /// Encrypt for testing purposes only
    static func aesCBCEncrypt(data: Data, key: Data, iv: Data) throws -> Data {
        var outputLength = data.count + kCCBlockSizeAES128
        var outputData = Data(count: outputLength)

        let status = outputData.withUnsafeMutableBytes { outputBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, key.count,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress, data.count,
                            outputBytes.baseAddress, outputLength,
                            &outputLength
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw TokenExtractorError.cookieDecryptionFailed("AES encryption failed")
        }

        outputData.count = outputLength
        return outputData
    }
}
