import CryptoKit
import Foundation
import SQLite3

final class UserDataBackupService {
    static let schemaVersion = 1
    static let manifestName = "manifest.json"
    static let payloadName = "payload"
    static let preferencesName = "preferences.plist"
    static let readingNoteAssetsName = "ReadingNoteAssets"
    static let restoreJournalName = "restore-journal.json"
    static let rollbackPreferencesName = "previous-preferences.plist"
    static let restoreTransactionPrefix = ".LeafReader-restore-"
    static let restoreRequestName = ".LeafReader-pending-restore.json"
    static let databaseNames = [
        "word-records.sqlite3",
        "personal-vocabulary.sqlite3",
        "reading-notes.sqlite"
    ]
    static let maximumEntryCount = 20_000
    static let maximumManifestByteCount: Int64 = 10 * 1_024 * 1_024
    static let maximumEntryByteCount: Int64 = 2 * 1_024 * 1_024 * 1_024
    static let maximumExpandedByteCount: Int64 = 10 * 1_024 * 1_024 * 1_024

    let configuration: UserDataBackupConfiguration
    let fileManager: FileManager
    let restoreCheckpoint: ((Int) throws -> Void)?

    init(
        configuration: UserDataBackupConfiguration,
        fileManager: FileManager = .default,
        restoreCheckpoint: ((Int) throws -> Void)? = nil
    ) {
        self.configuration = configuration
        self.fileManager = fileManager
        self.restoreCheckpoint = restoreCheckpoint
    }

    var restoreRequestURL: URL {
        configuration.applicationSupportDirectory.deletingLastPathComponent()
            .appendingPathComponent(Self.restoreRequestName)
    }

    @discardableResult
    func createBackup(at destinationURL: URL) throws -> UserDataBackupManifest {
        let backupURL = destinationURL.standardizedFileURL
        guard !fileManager.fileExists(atPath: backupURL.path) else {
            throw UserDataBackupError.destinationExists(backupURL.path)
        }
        try fileManager.createDirectory(
            at: backupURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let temporaryURL = backupURL.deletingLastPathComponent()
            .appendingPathComponent(".\(backupURL.lastPathComponent)-creating-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: temporaryURL) }

        let payloadURL = temporaryURL.appendingPathComponent(Self.payloadName, isDirectory: true)
        try fileManager.createDirectory(at: payloadURL, withIntermediateDirectories: true)
        var entries: [UserDataBackupManifest.Entry] = []

        let preferencesURL = payloadURL.appendingPathComponent(Self.preferencesName)
        let domain = configuration.defaults.persistentDomain(
            forName: configuration.preferencesDomainName
        ) ?? [:]
        let sanitizedDomain = UserDataBackupPreferencePolicy.sanitized(domain)
        do {
            let data = try PropertyListSerialization.data(
                fromPropertyList: sanitizedDomain,
                format: .binary,
                options: 0
            )
            try data.write(to: preferencesURL, options: .atomic)
        } catch {
            throw UserDataBackupError.preferences(error.localizedDescription)
        }
        entries.append(try entry(
            for: preferencesURL,
            relativePath: Self.preferencesName,
            kind: .preferences
        ))

        for name in Self.databaseNames {
            let source = configuration.applicationSupportDirectory.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = payloadURL.appendingPathComponent(name)
            try snapshotSQLiteDatabase(from: source, to: destination)
            entries.append(try entry(for: destination, relativePath: name, kind: .database))
        }

        let sourceAssets = configuration.applicationSupportDirectory
            .appendingPathComponent(Self.readingNoteAssetsName, isDirectory: true)
        var sourceAssetsIsDirectory: ObjCBool = false
        let includesAssets = fileManager.fileExists(
            atPath: sourceAssets.path,
            isDirectory: &sourceAssetsIsDirectory
        ) && sourceAssetsIsDirectory.boolValue
        if includesAssets {
            try validateRealDirectory(sourceAssets)
            let destinationAssets = payloadURL
                .appendingPathComponent(Self.readingNoteAssetsName, isDirectory: true)
            try fileManager.createDirectory(at: destinationAssets, withIntermediateDirectories: true)
            for source in try regularFilesRecursively(in: sourceAssets) {
                let suffix = relativePath(of: source, under: sourceAssets)
                let relative = Self.readingNoteAssetsName + "/" + suffix
                let destination = payloadURL.appendingPathComponent(relative)
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.copyItem(at: source, to: destination)
                entries.append(try entry(for: destination, relativePath: relative, kind: .readingNoteAsset))
            }
        }

        try enforceLimits(entries)
        entries.sort { $0.relativePath < $1.relativePath }
        let manifest = UserDataBackupManifest(
            schemaVersion: Self.schemaVersion,
            createdAt: Date(),
            applicationBundleIdentifier: configuration.applicationBundleIdentifier,
            preferencesDomainName: configuration.preferencesDomainName,
            includesReadingNoteAssetsDirectory: includesAssets,
            entries: entries
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var manifestData = try encoder.encode(manifest)
        manifestData.append(0x0A)
        try manifestData.write(
            to: temporaryURL.appendingPathComponent(Self.manifestName),
            options: .atomic
        )
        try fileManager.moveItem(at: temporaryURL, to: backupURL)
        return manifest
    }

    func validateBackup(at backupURL: URL) throws -> UserDataBackupManifest {
        let backupURL = backupURL.standardizedFileURL
        try validateRealDirectory(backupURL)
        let manifestURL = backupURL.appendingPathComponent(Self.manifestName)
        let payloadURL = backupURL.appendingPathComponent(Self.payloadName, isDirectory: true)
        let rootEntries = try fileManager.contentsOfDirectory(
            at: backupURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        )
        guard Set(rootEntries.map(\.lastPathComponent)) == [Self.manifestName, Self.payloadName] else {
            throw UserDataBackupError.invalidBackup("backup root contains undeclared entries")
        }
        let manifestValues = try manifestURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        guard manifestValues.isRegularFile == true,
              manifestValues.isSymbolicLink != true,
              try fileSize(manifestURL) <= Self.maximumManifestByteCount else {
            throw UserDataBackupError.invalidBackup("manifest is missing, unsafe, or oversized")
        }
        try validateRealDirectory(payloadURL)

        let manifest: UserDataBackupManifest
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            manifest = try decoder.decode(
                UserDataBackupManifest.self,
                from: Data(contentsOf: manifestURL)
            )
        } catch {
            throw UserDataBackupError.invalidBackup("manifest.json could not be decoded")
        }
        guard manifest.schemaVersion == Self.schemaVersion else {
            throw UserDataBackupError.unsupportedSchema(manifest.schemaVersion)
        }
        guard manifest.applicationBundleIdentifier == configuration.applicationBundleIdentifier else {
            throw UserDataBackupError.incompatibleApplication(manifest.applicationBundleIdentifier)
        }
        guard manifest.preferencesDomainName == configuration.preferencesDomainName else {
            throw UserDataBackupError.invalidBackup("preferences domain does not match")
        }
        try enforceLimits(manifest.entries)

        let assetsURL = payloadURL.appendingPathComponent(Self.readingNoteAssetsName, isDirectory: true)
        var assetsIsDirectory: ObjCBool = false
        let hasAssets = fileManager.fileExists(atPath: assetsURL.path, isDirectory: &assetsIsDirectory)
            && assetsIsDirectory.boolValue
        guard hasAssets == manifest.includesReadingNoteAssetsDirectory else {
            throw UserDataBackupError.invalidBackup("reading-note assets do not match the manifest")
        }
        if hasAssets { try validateRealDirectory(assetsURL) }

        var paths = Set<String>()
        var preferenceCount = 0
        for entry in manifest.entries {
            guard paths.insert(entry.relativePath).inserted else {
                throw UserDataBackupError.invalidBackup("duplicate entry \(entry.relativePath)")
            }
            try validateAllowed(entry)
            let url = try validatedPayloadURL(for: entry.relativePath, payloadRoot: payloadURL)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw UserDataBackupError.invalidBackup("missing or unsafe payload file \(entry.relativePath)")
            }
            guard try fileSize(url) == entry.byteCount else {
                throw UserDataBackupError.invalidBackup("size mismatch for \(entry.relativePath)")
            }
            guard try sha256(url) == entry.sha256 else {
                throw UserDataBackupError.invalidBackup("checksum mismatch for \(entry.relativePath)")
            }
            switch entry.kind {
            case .database:
                try validateSQLiteIntegrity(url)
            case .preferences:
                preferenceCount += 1
                let preferences = try preferencesDictionary(at: url)
                guard UserDataBackupPreferencePolicy.sanitized(preferences).count == preferences.count else {
                    throw UserDataBackupError.invalidBackup("preferences contain credential data")
                }
            case .readingNoteAsset:
                guard manifest.includesReadingNoteAssetsDirectory else {
                    throw UserDataBackupError.invalidBackup("reading-note assets directory is undeclared")
                }
            }
        }
        guard preferenceCount == 1 else {
            throw UserDataBackupError.invalidBackup("exactly one preferences payload is required")
        }
        let actualFiles = Set(try regularFilesRecursively(in: payloadURL).map {
            relativePath(of: $0, under: payloadURL)
        })
        guard actualFiles == paths else {
            throw UserDataBackupError.invalidBackup("payload contains unlisted or missing files")
        }
        try validatePayloadDirectories(payloadURL, manifest: manifest)
        return manifest
    }

    func scheduleRestore(at backupURL: URL) throws {
        _ = try validateBackup(at: backupURL)
        let request = UserDataRestoreRequest(backupPath: backupURL.standardizedFileURL.path)
        let data = try JSONEncoder().encode(request)
        try data.write(to: restoreRequestURL, options: .atomic)
    }

    func pendingRestoreURL() throws -> URL? {
        guard fileManager.fileExists(atPath: restoreRequestURL.path) else { return nil }
        do {
            let request = try JSONDecoder().decode(
                UserDataRestoreRequest.self,
                from: Data(contentsOf: restoreRequestURL)
            )
            guard !request.backupPath.isEmpty else {
                throw UserDataBackupError.invalidBackup("pending restore path is empty")
            }
            return URL(fileURLWithPath: request.backupPath).standardizedFileURL
        } catch let error as UserDataBackupError {
            throw error
        } catch {
            throw UserDataBackupError.invalidBackup("pending restore request is unreadable")
        }
    }

    func clearPendingRestore() throws {
        guard fileManager.fileExists(atPath: restoreRequestURL.path) else { return }
        try fileManager.removeItem(at: restoreRequestURL)
    }

    func validateAllowed(_ entry: UserDataBackupManifest.Entry) throws {
        switch entry.kind {
        case .preferences:
            guard entry.relativePath == Self.preferencesName else {
                throw UserDataBackupError.invalidBackup("preferences path is not allowed")
            }
        case .database:
            guard Self.databaseNames.contains(entry.relativePath) else {
                throw UserDataBackupError.invalidBackup("database path is not allowed")
            }
        case .readingNoteAsset:
            guard entry.relativePath.hasPrefix(Self.readingNoteAssetsName + "/") else {
                throw UserDataBackupError.invalidBackup("reading-note asset path is not allowed")
            }
        }
    }

    func validatedPayloadURL(for relativePath: String, payloadRoot: URL) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.hasPrefix("/"), !components.contains(".."), !components.contains("") else {
            throw UserDataBackupError.invalidBackup("unsafe payload path \(relativePath)")
        }
        let url = payloadRoot.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = payloadRoot.standardizedFileURL.path + "/"
        guard url.path.hasPrefix(rootPath) else {
            throw UserDataBackupError.invalidBackup("payload path escapes the backup")
        }
        return url
    }

    func entry(
        for url: URL,
        relativePath: String,
        kind: UserDataBackupManifest.Entry.Kind
    ) throws -> UserDataBackupManifest.Entry {
        UserDataBackupManifest.Entry(
            relativePath: relativePath,
            kind: kind,
            byteCount: try fileSize(url),
            sha256: try sha256(url)
        )
    }

    func enforceLimits(_ entries: [UserDataBackupManifest.Entry]) throws {
        guard entries.count <= Self.maximumEntryCount else {
            throw UserDataBackupError.invalidBackup("too many payload entries")
        }
        var total: Int64 = 0
        for entry in entries {
            guard entry.byteCount >= 0, entry.byteCount <= Self.maximumEntryByteCount else {
                throw UserDataBackupError.invalidBackup("payload entry is too large")
            }
            let (sum, overflow) = total.addingReportingOverflow(entry.byteCount)
            guard !overflow, sum <= Self.maximumExpandedByteCount else {
                throw UserDataBackupError.invalidBackup("expanded payload is too large")
            }
            total = sum
        }
    }

    func validateRealDirectory(_ directory: URL) throws {
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw UserDataBackupError.invalidBackup("unsafe directory \(directory.lastPathComponent)")
        }
    }

    func regularFilesRecursively(in directory: URL) throws -> [URL] {
        try validateRealDirectory(directory)
        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
            options: [],
            errorHandler: { url, error in
                enumerationError = UserDataBackupError.fileOperation(
                    "could not enumerate \(url.lastPathComponent): \(error.localizedDescription)"
                )
                return false
            }
        ) else {
            throw UserDataBackupError.fileOperation("could not enumerate \(directory.lastPathComponent)")
        }
        var files: [URL] = []
        for case let url as URL in enumerator {
            if let enumerationError { throw enumerationError }
            let values = try url.resourceValues(
                forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
            )
            if values.isSymbolicLink == true {
                throw UserDataBackupError.invalidBackup("symbolic links are not allowed")
            }
            if values.isRegularFile == true { files.append(url) }
            else if values.isDirectory != true {
                throw UserDataBackupError.invalidBackup("unsupported filesystem entry")
            }
        }
        if let enumerationError { throw enumerationError }
        return files.sorted { $0.path < $1.path }
    }

    func validatePayloadDirectories(_ payloadURL: URL, manifest: UserDataBackupManifest) throws {
        var allowed = Set<String>()
        if manifest.includesReadingNoteAssetsDirectory {
            allowed.insert(Self.readingNoteAssetsName)
        }
        for entry in manifest.entries where entry.kind == .readingNoteAsset {
            var components = entry.relativePath.split(separator: "/").map(String.init)
            guard components.count > 1 else { continue }
            components.removeLast()
            while !components.isEmpty {
                allowed.insert(components.joined(separator: "/"))
                components.removeLast()
            }
        }
        guard let enumerator = fileManager.enumerator(
            at: payloadURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else {
            throw UserDataBackupError.invalidBackup("payload could not be enumerated")
        }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw UserDataBackupError.invalidBackup("payload contains a symbolic link")
            }
            guard values.isDirectory == true else { continue }
            let path = relativePath(of: url, under: payloadURL)
            guard allowed.contains(path) else {
                throw UserDataBackupError.invalidBackup("payload contains undeclared directory \(path)")
            }
        }
    }

    func relativePath(of url: URL, under root: URL) -> String {
        String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
    }

    func fileSize(_ url: URL) throws -> Int64 {
        guard let value = try fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber else {
            throw UserDataBackupError.fileOperation("could not read file size")
        }
        return value.int64Value
    }

    func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_024 * 1_024) ?? Data()
            guard !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func snapshotSQLiteDatabase(from sourceURL: URL, to destinationURL: URL) throws {
        var source: OpaquePointer?
        var destination: OpaquePointer?
        guard sqlite3_open_v2(sourceURL.path, &source, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(source)
            throw UserDataBackupError.sqliteSnapshot(sourceURL.lastPathComponent)
        }
        defer { sqlite3_close(source) }
        guard sqlite3_open(destinationURL.path, &destination) == SQLITE_OK else {
            sqlite3_close(destination)
            throw UserDataBackupError.sqliteSnapshot(destinationURL.lastPathComponent)
        }
        defer { sqlite3_close(destination) }
        guard let backup = sqlite3_backup_init(destination, "main", source, "main") else {
            throw UserDataBackupError.sqliteSnapshot(sourceURL.lastPathComponent)
        }
        var result: Int32 = SQLITE_OK
        var retries = 0
        repeat {
            result = sqlite3_backup_step(backup, -1)
            if result == SQLITE_BUSY || result == SQLITE_LOCKED {
                retries += 1
                sqlite3_sleep(10)
            }
        } while (result == SQLITE_BUSY || result == SQLITE_LOCKED) && retries < 100
        let finishResult = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finishResult == SQLITE_OK else {
            throw UserDataBackupError.sqliteSnapshot(sourceURL.lastPathComponent)
        }
    }

    func validateSQLiteIntegrity(_ url: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(database)
            throw UserDataBackupError.sqliteIntegrity(url.lastPathComponent)
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA integrity_check", -1, &statement, nil) == SQLITE_OK else {
            throw UserDataBackupError.sqliteIntegrity(url.lastPathComponent)
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let value = sqlite3_column_text(statement, 0),
              String(cString: value) == "ok" else {
            throw UserDataBackupError.sqliteIntegrity(url.lastPathComponent)
        }
    }

    func preferencesDictionary(at url: URL) throws -> [String: Any] {
        do {
            let object = try PropertyListSerialization.propertyList(
                from: Data(contentsOf: url),
                options: [],
                format: nil
            )
            guard let dictionary = object as? [String: Any] else {
                throw UserDataBackupError.preferences("root value is not a dictionary")
            }
            return dictionary
        } catch let error as UserDataBackupError {
            throw error
        } catch {
            throw UserDataBackupError.preferences(error.localizedDescription)
        }
    }
}
