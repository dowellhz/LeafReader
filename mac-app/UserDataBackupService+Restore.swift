import Foundation

extension UserDataBackupService {
    @discardableResult
    func restoreBackup(at backupURL: URL) throws -> UserDataRestoreResult {
        let backupURL = backupURL.standardizedFileURL
        let manifest = try validateBackup(at: backupURL)
        let payloadURL = backupURL.appendingPathComponent(Self.payloadName, isDirectory: true)
        guard let preferencesEntry = manifest.entries.first(where: { $0.kind == .preferences }) else {
            throw UserDataBackupError.invalidBackup("preferences payload is missing")
        }
        let restoredDomain = try preferencesDictionary(
            at: try validatedPayloadURL(for: preferencesEntry.relativePath, payloadRoot: payloadURL)
        )
        let previousDomain = configuration.defaults.persistentDomain(
            forName: configuration.preferencesDomainName
        ) ?? [:]
        let preferencesToApply = UserDataBackupPreferencePolicy.restoring(
            restoredDomain,
            preservingSensitiveValuesFrom: previousDomain
        )

        try fileManager.createDirectory(
            at: configuration.applicationSupportDirectory,
            withIntermediateDirectories: true
        )
        let transactionURL = configuration.applicationSupportDirectory.deletingLastPathComponent()
            .appendingPathComponent(Self.restoreTransactionPrefix + UUID().uuidString, isDirectory: true)
        let stageURL = transactionURL.appendingPathComponent("stage", isDirectory: true)
        let rollbackURL = transactionURL.appendingPathComponent("rollback", isDirectory: true)
        try fileManager.createDirectory(at: stageURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: rollbackURL, withIntermediateDirectories: true)

        let unitNames = Self.databaseNames + [Self.readingNoteAssetsName]
        var journal = UserDataRestoreJournal(
            phase: .applying,
            units: unitNames.map { name in
                UserDataRestoreJournal.Unit(
                    name: name,
                    hadOriginal: fileManager.fileExists(
                        atPath: configuration.applicationSupportDirectory.appendingPathComponent(name).path
                    ),
                    phase: .pending
                )
            },
            preferencesApplyStarted: false,
            preferencesApplied: false
        )
        try writeRestoreJournal(journal, at: transactionURL)
        try writePreferences(previousDomain, to: rollbackURL.appendingPathComponent(Self.rollbackPreferencesName))

        do {
            try stageRestorePayload(manifest, payloadRoot: payloadURL, stageURL: stageURL)
            for index in journal.units.indices {
                try applyRestoreUnit(
                    at: index,
                    journal: &journal,
                    transactionURL: transactionURL,
                    stageURL: stageURL,
                    rollbackURL: rollbackURL
                )
                try restoreCheckpoint?(index + 1)
            }

            journal.preferencesApplyStarted = true
            try writeRestoreJournal(journal, at: transactionURL)
            configuration.defaults.setPersistentDomain(
                preferencesToApply,
                forName: configuration.preferencesDomainName
            )
            guard configuration.defaults.synchronize() else {
                throw UserDataBackupError.preferences("restored preferences could not be synchronized")
            }
            journal.preferencesApplied = true
            journal.phase = .committed
            try writeRestoreJournal(journal, at: transactionURL)
        } catch {
            do {
                try rollbackRestoreTransaction(at: transactionURL, journal: &journal)
                try fileManager.removeItem(at: transactionURL)
            } catch {
                throw UserDataBackupError.rollbackFailed(error.localizedDescription)
            }
            throw error
        }

        try fileManager.removeItem(at: transactionURL)
        return UserDataRestoreResult(
            restoredEntryCount: manifest.entries.count,
            requiresRelaunch: true
        )
    }

    func recoverInterruptedRestoreIfNeeded() throws {
        let parentURL = configuration.applicationSupportDirectory.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: parentURL.path) else { return }
        let candidates = try fileManager.contentsOfDirectory(
            at: parentURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ).filter { $0.lastPathComponent.hasPrefix(Self.restoreTransactionPrefix) }

        for transactionURL in candidates {
            try validateRealDirectory(transactionURL)
            var journal = try readRestoreJournal(at: transactionURL)
            if journal.phase == .committed {
                try fileManager.removeItem(at: transactionURL)
                continue
            }
            try rollbackRestoreTransaction(at: transactionURL, journal: &journal)
            try fileManager.removeItem(at: transactionURL)
        }
    }

    @discardableResult
    func performPendingRestoreIfNeeded() throws -> UserDataRestoreResult? {
        guard let backupURL = try pendingRestoreURL() else { return nil }
        try clearPendingRestore()
        return try restoreBackup(at: backupURL)
    }

    private func stageRestorePayload(
        _ manifest: UserDataBackupManifest,
        payloadRoot: URL,
        stageURL: URL
    ) throws {
        for entry in manifest.entries where entry.kind == .database {
            let source = try validatedPayloadURL(for: entry.relativePath, payloadRoot: payloadRoot)
            try fileManager.copyItem(at: source, to: stageURL.appendingPathComponent(entry.relativePath))
        }
        guard manifest.includesReadingNoteAssetsDirectory else { return }
        let stagedAssets = stageURL.appendingPathComponent(Self.readingNoteAssetsName, isDirectory: true)
        try fileManager.createDirectory(at: stagedAssets, withIntermediateDirectories: true)
        for entry in manifest.entries where entry.kind == .readingNoteAsset {
            let source = try validatedPayloadURL(for: entry.relativePath, payloadRoot: payloadRoot)
            let destination = stageURL.appendingPathComponent(entry.relativePath)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    private func applyRestoreUnit(
        at index: Int,
        journal: inout UserDataRestoreJournal,
        transactionURL: URL,
        stageURL: URL,
        rollbackURL: URL
    ) throws {
        let name = journal.units[index].name
        let destination = configuration.applicationSupportDirectory.appendingPathComponent(name)
        let staged = stageURL.appendingPathComponent(name)
        let rollback = rollbackURL.appendingPathComponent(name)
        let hasStaged = fileManager.fileExists(atPath: staged.path)
        let hasDestination = fileManager.fileExists(atPath: destination.path)
        guard hasStaged || hasDestination else { return }

        if hasDestination {
            journal.units[index].phase = .movingOriginal
            try writeRestoreJournal(journal, at: transactionURL)
            try fileManager.moveItem(at: destination, to: rollback)
            journal.units[index].phase = .originalMoved
            try writeRestoreJournal(journal, at: transactionURL)
        }
        if hasStaged {
            journal.units[index].phase = .installingStaged
            try writeRestoreJournal(journal, at: transactionURL)
            try fileManager.moveItem(at: staged, to: destination)
            journal.units[index].phase = .installed
            try writeRestoreJournal(journal, at: transactionURL)
        }
    }

    private func writeRestoreJournal(_ journal: UserDataRestoreJournal, at transactionURL: URL) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(journal).write(
                to: transactionURL.appendingPathComponent(Self.restoreJournalName),
                options: .atomic
            )
        } catch {
            throw UserDataBackupError.fileOperation("could not write restore journal")
        }
    }

    private func readRestoreJournal(at transactionURL: URL) throws -> UserDataRestoreJournal {
        do {
            return try JSONDecoder().decode(
                UserDataRestoreJournal.self,
                from: Data(contentsOf: transactionURL.appendingPathComponent(Self.restoreJournalName))
            )
        } catch {
            throw UserDataBackupError.rollbackFailed("restore journal is unreadable")
        }
    }

    private func rollbackRestoreTransaction(
        at transactionURL: URL,
        journal: inout UserDataRestoreJournal
    ) throws {
        let rollbackURL = transactionURL.appendingPathComponent("rollback", isDirectory: true)
        var failures: [String] = []
        journal.phase = .rollingBack
        try? writeRestoreJournal(journal, at: transactionURL)

        if journal.preferencesApplyStarted {
            do {
                let previous = try preferencesDictionary(
                    at: rollbackURL.appendingPathComponent(Self.rollbackPreferencesName)
                )
                configuration.defaults.setPersistentDomain(
                    previous,
                    forName: configuration.preferencesDomainName
                )
                guard configuration.defaults.synchronize() else {
                    throw UserDataBackupError.preferences("previous preferences could not be synchronized")
                }
                journal.preferencesApplied = false
            } catch {
                failures.append(Self.preferencesName)
            }
        }

        for unit in journal.units.reversed() {
            let destination = configuration.applicationSupportDirectory.appendingPathComponent(unit.name)
            let rollback = rollbackURL.appendingPathComponent(unit.name)
            let hasRollback = fileManager.fileExists(atPath: rollback.path)
            let hasDestination = fileManager.fileExists(atPath: destination.path)
            do {
                if hasRollback {
                    if hasDestination { try fileManager.removeItem(at: destination) }
                    try fileManager.moveItem(at: rollback, to: destination)
                    continue
                }
                if !unit.hadOriginal,
                   (unit.phase == .installingStaged || unit.phase == .installed),
                   hasDestination {
                    try fileManager.removeItem(at: destination)
                    continue
                }
                if unit.hadOriginal, unit.phase != .pending, !hasDestination {
                    throw UserDataBackupError.rollbackFailed("missing original \(unit.name)")
                }
            } catch {
                failures.append(unit.name)
            }
        }
        guard failures.isEmpty else {
            throw UserDataBackupError.rollbackFailed(failures.joined(separator: ", "))
        }
    }

    private func writePreferences(_ domain: [String: Any], to url: URL) throws {
        do {
            let data = try PropertyListSerialization.data(
                fromPropertyList: domain,
                format: .binary,
                options: 0
            )
            try data.write(to: url, options: .atomic)
        } catch {
            throw UserDataBackupError.preferences("could not journal previous preferences")
        }
    }
}
