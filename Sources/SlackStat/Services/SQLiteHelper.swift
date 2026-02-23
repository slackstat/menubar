import Foundation
import SQLite3

enum SQLiteError: Error {
    case openFailed(String)
    case queryFailed(String)
    case noResult
}

extension TokenExtractor {
    static func readCookieFromSQLite(at url: URL, name: String, domain: String) throws -> Data {
        // Copy the database to a temp location to avoid WAL/journal lock contention
        // with Slack's open database. The immutable=1 URI flag doesn't reliably read
        // uncommitted journal data, so copying is the safest approach.
        let fm = FileManager.default
        let tmpDB = "/tmp/slackstat_cookies_\(ProcessInfo.processInfo.processIdentifier)"
        let tmpJournal = tmpDB + "-journal"
        let tmpWAL = tmpDB + "-wal"
        let tmpSHM = tmpDB + "-shm"
        defer {
            try? fm.removeItem(atPath: tmpDB)
            try? fm.removeItem(atPath: tmpJournal)
            try? fm.removeItem(atPath: tmpWAL)
            try? fm.removeItem(atPath: tmpSHM)
        }

        try? fm.removeItem(atPath: tmpDB)
        try fm.copyItem(atPath: url.path, toPath: tmpDB)

        // Copy journal/WAL files if they exist
        let srcJournal = url.path + "-journal"
        let srcWAL = url.path + "-wal"
        let srcSHM = url.path + "-shm"
        if fm.fileExists(atPath: srcJournal) {
            try? fm.removeItem(atPath: tmpJournal)
            try? fm.copyItem(atPath: srcJournal, toPath: tmpJournal)
        }
        if fm.fileExists(atPath: srcWAL) {
            try? fm.removeItem(atPath: tmpWAL)
            try? fm.copyItem(atPath: srcWAL, toPath: tmpWAL)
        }
        if fm.fileExists(atPath: srcSHM) {
            try? fm.removeItem(atPath: tmpSHM)
            try? fm.copyItem(atPath: srcSHM, toPath: tmpSHM)
        }

        var db: OpaquePointer?
        // Use READWRITE so SQLite can replay the journal if needed
        guard sqlite3_open_v2(tmpDB, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw SQLiteError.openFailed(msg)
        }
        defer { sqlite3_close(db) }

        let sql = "SELECT encrypted_value FROM cookies WHERE name = ? AND host_key = ? LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError.queryFailed("Failed to prepare statement")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (domain as NSString).utf8String, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw SQLiteError.noResult
        }

        let blobPtr = sqlite3_column_blob(stmt, 0)
        let blobLen = sqlite3_column_bytes(stmt, 0)
        guard let ptr = blobPtr, blobLen > 0 else {
            throw SQLiteError.noResult
        }

        return Data(bytes: ptr, count: Int(blobLen))
    }
}
