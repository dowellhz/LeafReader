import Foundation

extension SpeechRuntimeResourceManager.InstallManifest {
    var cacheDirectories: [URL] {
        cacheDirectoryPaths.compactMap { path in
            let url = URL(fileURLWithPath: path, isDirectory: true)
            return url.isInsideFluidAudioModelCache ? url : nil
        }
    }
}

struct KokoroCacheInstallTransaction {
    private struct Replacement {
        let destination: URL
        let backup: URL
        let hadExistingDestination: Bool
    }

    private let fileManager: FileManager
    private var replacements: [Replacement] = []
    private(set) var installedDirectories: [URL] = []
    private var isCommitted = false

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    mutating func replace(source: URL, destination: URL, backup: URL) throws {
        let hadExistingDestination = fileManager.fileExists(atPath: destination.path)
        do {
            if hadExistingDestination {
                try fileManager.moveItem(at: destination, to: backup)
            }
            try fileManager.moveItem(at: source, to: destination)
            replacements.append(Replacement(
                destination: destination,
                backup: backup,
                hadExistingDestination: hadExistingDestination
            ))
            installedDirectories.append(destination)
        } catch {
            restoreCurrentReplacement(destination: destination, backup: backup, hadExistingDestination: hadExistingDestination)
            rollback()
            throw error
        }
    }

    mutating func commit() {
        isCommitted = true
        for replacement in replacements {
            try? fileManager.removeItem(at: replacement.backup)
        }
        replacements.removeAll()
    }

    mutating func rollback() {
        guard !isCommitted else { return }
        for replacement in replacements.reversed() {
            try? fileManager.removeItem(at: replacement.destination)
            if replacement.hadExistingDestination,
               fileManager.fileExists(atPath: replacement.backup.path),
               !fileManager.fileExists(atPath: replacement.destination.path) {
                try? fileManager.moveItem(at: replacement.backup, to: replacement.destination)
            } else {
                try? fileManager.removeItem(at: replacement.backup)
            }
        }
        replacements.removeAll()
        installedDirectories.removeAll()
    }

    private func restoreCurrentReplacement(destination: URL, backup: URL, hadExistingDestination: Bool) {
        try? fileManager.removeItem(at: destination)
        if hadExistingDestination,
           fileManager.fileExists(atPath: backup.path),
           !fileManager.fileExists(atPath: destination.path) {
            try? fileManager.moveItem(at: backup, to: destination)
        } else {
            try? fileManager.removeItem(at: backup)
        }
    }
}

extension URL {
    var isInsideFluidAudioModelCache: Bool {
        let rootPath = SpeechRuntimeResourceManager.Runtime.fluidAudioModelCacheRoot
            .standardizedFileURL
            .path
        let path = standardizedFileURL.path
        return path.hasPrefix(rootPath + "/")
    }
}
