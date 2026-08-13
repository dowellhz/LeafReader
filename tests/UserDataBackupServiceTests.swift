import Foundation
import SQLite3

enum UserDataBackupServiceTests {
    private struct Fixture {
        let root: URL
        let support: URL
        let backup: URL
        let domain: String
        let defaults: UserDefaults

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("LeafReaderBackupTests-\(UUID().uuidString)", isDirectory: true)
            support = root.appendingPathComponent("LeafReader", isDirectory: true)
            backup = root.appendingPathComponent("snapshot.leafreaderbackup", isDirectory: true)
            domain = "LeafReaderBackupTests.\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: domain) else {
                throw TestFailure(description: "could not create backup test defaults")
            }
            self.defaults = defaults
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        }

        func service(checkpoint: ((Int) throws -> Void)? = nil) -> UserDataBackupService {
            UserDataBackupService(
                configuration: UserDataBackupConfiguration(
                    applicationSupportDirectory: support,
                    preferencesDomainName: domain,
                    applicationBundleIdentifier: "com.linlu.LeafReader.tests",
                    defaults: defaults
                ),
                restoreCheckpoint: checkpoint
            )
        }

        func cleanUp() {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: root)
        }
    }

    static func testRoundTripExcludesCredentialsAndPreservesCurrentKeyReferences() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try seedManagedData(fixture, value: "before")
        fixture.defaults.set("before", forKey: "readerTheme")
        fixture.defaults.set("backup-secret", forKey: "apiKey.legacy")
        fixture.defaults.synchronize()

        let manifest = try fixture.service().createBackup(at: fixture.backup)
        try expectEqual(manifest.schemaVersion, 1, "backup format should be versioned")
        let preferencesURL = fixture.backup.appendingPathComponent("payload/preferences.plist")
        let preferences = try propertyList(at: preferencesURL)
        try expect(preferences["apiKey.legacy"] == nil, "backup preferences must exclude legacy API keys")
        try expect(
            !manifest.entries.contains { $0.relativePath.hasSuffix("-wal") || $0.relativePath.hasSuffix("-shm") },
            "SQLite sidecars should not be copied into a backup"
        )

        try seedManagedData(fixture, value: "after")
        fixture.defaults.set("after", forKey: "readerTheme")
        fixture.defaults.set("current-secret", forKey: "apiKey.legacy")
        fixture.defaults.synchronize()

        let result = try fixture.service().restoreBackup(at: fixture.backup)
        try expect(result.requiresRelaunch, "restored stores should be reopened on launch")
        try expectEqual(try databaseValue(fixture.support.appendingPathComponent("word-records.sqlite3")), "before", "word records should restore")
        try expectEqual(try databaseValue(fixture.support.appendingPathComponent("personal-vocabulary.sqlite3")), "before", "personal vocabulary should restore")
        try expectEqual(try databaseValue(fixture.support.appendingPathComponent("reading-notes.sqlite")), "before", "reading notes should restore")
        try expectEqual(fixture.defaults.string(forKey: "readerTheme"), "before", "preferences should restore")
        try expectEqual(fixture.defaults.string(forKey: "apiKey.legacy"), "current-secret", "restore should preserve current-machine credentials")
        let asset = fixture.support.appendingPathComponent("ReadingNoteAssets/note-image.txt")
        try expectEqual(try String(contentsOf: asset, encoding: .utf8), "before", "reading-note assets should restore")
    }

    static func testTamperedPayloadIsRejectedBeforeMutation() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try seedManagedData(fixture, value: "backup")
        fixture.defaults.set("backup", forKey: "readerTheme")
        _ = try fixture.service().createBackup(at: fixture.backup)

        try seedManagedData(fixture, value: "current")
        fixture.defaults.set("current", forKey: "readerTheme")
        let asset = fixture.backup.appendingPathComponent("payload/ReadingNoteAssets/note-image.txt")
        try Data("tampered".utf8).write(to: asset, options: .atomic)
        do {
            _ = try fixture.service().restoreBackup(at: fixture.backup)
            throw TestFailure(description: "tampered backup should not restore")
        } catch is TestFailure {
            throw TestFailure(description: "tampered backup should not restore")
        } catch {
            // Expected validation failure.
        }
        try expectEqual(try databaseValue(fixture.support.appendingPathComponent("word-records.sqlite3")), "current", "validation failure should preserve databases")
        try expectEqual(fixture.defaults.string(forKey: "readerTheme"), "current", "validation failure should preserve preferences")
    }

    static func testFailedRestoreRollsBackReplacements() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try seedManagedData(fixture, value: "backup")
        fixture.defaults.set("backup", forKey: "readerTheme")
        _ = try fixture.service().createBackup(at: fixture.backup)
        try seedManagedData(fixture, value: "current")
        fixture.defaults.set("current", forKey: "readerTheme")

        enum InjectedFailure: Error { case stop }
        let service = fixture.service { count in
            if count == 1 { throw InjectedFailure.stop }
        }
        do {
            _ = try service.restoreBackup(at: fixture.backup)
            throw TestFailure(description: "injected restore failure should surface")
        } catch is TestFailure {
            throw TestFailure(description: "injected restore failure should surface")
        } catch {
            // Expected rollback.
        }
        try expectEqual(try databaseValue(fixture.support.appendingPathComponent("word-records.sqlite3")), "current", "rollback should restore the first replaced database")
        try expectEqual(try databaseValue(fixture.support.appendingPathComponent("personal-vocabulary.sqlite3")), "current", "rollback should preserve later databases")
        try expectEqual(fixture.defaults.string(forKey: "readerTheme"), "current", "rollback should preserve preferences")
    }

    static func testInterruptedRestoreRecoveryUsesJournal() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try seedManagedData(fixture, value: "before")
        let transaction = fixture.root.appendingPathComponent(
            UserDataBackupService.restoreTransactionPrefix + "interrupted",
            isDirectory: true
        )
        let rollback = transaction.appendingPathComponent("rollback", isDirectory: true)
        try FileManager.default.createDirectory(at: rollback, withIntermediateDirectories: true)
        let wordDatabase = fixture.support.appendingPathComponent("word-records.sqlite3")
        try FileManager.default.moveItem(
            at: wordDatabase,
            to: rollback.appendingPathComponent("word-records.sqlite3")
        )
        try createDatabase(at: wordDatabase, value: "after")
        try writePropertyList([:], to: rollback.appendingPathComponent(UserDataBackupService.rollbackPreferencesName))
        let journal = UserDataRestoreJournal(
            phase: .applying,
            units: [
                .init(name: "word-records.sqlite3", hadOriginal: true, phase: .installed),
                .init(name: "personal-vocabulary.sqlite3", hadOriginal: true, phase: .pending),
                .init(name: "reading-notes.sqlite", hadOriginal: true, phase: .pending),
                .init(name: "ReadingNoteAssets", hadOriginal: true, phase: .pending)
            ],
            preferencesApplyStarted: false,
            preferencesApplied: false
        )
        try JSONEncoder().encode(journal).write(
            to: transaction.appendingPathComponent(UserDataBackupService.restoreJournalName),
            options: .atomic
        )

        try fixture.service().recoverInterruptedRestoreIfNeeded()
        try expectEqual(try databaseValue(wordDatabase), "before", "cold-start recovery should restore the original database")
        try expect(!FileManager.default.fileExists(atPath: transaction.path), "successful recovery should remove its transaction")
    }

    static func testBackupRejectsManagedAssetSymlinks() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try seedManagedData(fixture, value: "before")
        let assets = fixture.support.appendingPathComponent("ReadingNoteAssets", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            at: assets.appendingPathComponent("linked-secret.txt"),
            withDestinationURL: fixture.root.appendingPathComponent("outside.txt")
        )
        do {
            _ = try fixture.service().createBackup(at: fixture.backup)
            throw TestFailure(description: "asset symlink should be rejected")
        } catch is TestFailure {
            throw TestFailure(description: "asset symlink should be rejected")
        } catch {
            // Expected fail-closed behavior.
        }
        try expect(!FileManager.default.fileExists(atPath: fixture.backup.path), "rejected backup should not be published")
    }

    private static func seedManagedData(_ fixture: Fixture, value: String) throws {
        for name in UserDataBackupService.databaseNames {
            let url = fixture.support.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: url)
            try createDatabase(at: url, value: value)
        }
        let assets = fixture.support.appendingPathComponent("ReadingNoteAssets", isDirectory: true)
        try? FileManager.default.removeItem(at: assets)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data(value.utf8).write(to: assets.appendingPathComponent("note-image.txt"), options: .atomic)
    }

    private static func createDatabase(at url: URL, value: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK else {
            throw TestFailure(description: "could not create SQLite fixture")
        }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, "CREATE TABLE state(value TEXT NOT NULL);", nil, nil, nil) == SQLITE_OK else {
            throw TestFailure(description: "could not create SQLite fixture table")
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "INSERT INTO state(value) VALUES (?)", -1, &statement, nil) == SQLITE_OK else {
            throw TestFailure(description: "could not prepare SQLite fixture insert")
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw TestFailure(description: "could not insert SQLite fixture")
        }
    }

    private static func databaseValue(_ url: URL) throws -> String {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw TestFailure(description: "could not open SQLite fixture")
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT value FROM state LIMIT 1", -1, &statement, nil) == SQLITE_OK else {
            throw TestFailure(description: "could not query SQLite fixture")
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else {
            throw TestFailure(description: "SQLite fixture has no value")
        }
        return String(cString: value)
    }

    private static func propertyList(at url: URL) throws -> [String: Any] {
        let object = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: url),
            options: [],
            format: nil
        )
        guard let dictionary = object as? [String: Any] else {
            throw TestFailure(description: "fixture property list is not a dictionary")
        }
        return dictionary
    }

    private static func writePropertyList(_ dictionary: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: dictionary,
            format: .binary,
            options: 0
        )
        try data.write(to: url, options: .atomic)
    }
}
