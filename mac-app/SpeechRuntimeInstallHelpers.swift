import Foundation

extension SpeechRuntimeResourceManager {
    static func requiredPathsExist(_ paths: [URL]) -> Bool {
        paths.allSatisfy { path in
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory)
            if path.hasDirectoryPath {
                return exists && isDirectory.boolValue
            }
            return FileManager.default.isExecutableFile(atPath: path.path)
        }
    }

    static func kittenRuntimePathsExist(in directory: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: Runtime.kitten.executableURL(in: directory).path)
    }

    static func bundledRuntimePathsExist(for runtime: Runtime) -> Bool {
        guard let directory = runtime.bundledInstallDirectory else {
            return false
        }
        switch runtime {
        case .kitten:
            return kittenRuntimePathsExist(in: directory)
        case .kokoro:
            return requiredPathsExist(runtime.requiredPaths(in: directory))
        }
    }

    static func kittenModelPathsExist(in directory: URL) -> Bool {
        let modelDirectory = Runtime.kitten.modelDirectory(in: directory)
        let model = modelDirectory.appendingPathComponent("kitten_tts_mini_v0_8.onnx")
        let voices = modelDirectory.appendingPathComponent("voices.npz")
        let config = modelDirectory.appendingPathComponent("config.json")
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: modelDirectory.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && FileManager.default.fileExists(atPath: model.path)
            && FileManager.default.fileExists(atPath: voices.path)
            && FileManager.default.fileExists(atPath: config.path)
    }

    static func kokoroModelCacheDirectories() -> [URL] {
        let cacheRoot = Runtime.fluidAudioModelCacheRoot
        return [
            cacheRoot.appendingPathComponent("kokoro", isDirectory: true),
            cacheRoot.appendingPathComponent("kokoro-82m-coreml", isDirectory: true)
        ]
    }

    static func kokoroAneModelCacheExists() -> Bool {
        kokoroAneModelCacheExists(in: Runtime.fluidAudioModelCacheRoot)
    }

    static func kokoroAneModelCacheExists(in cacheRoot: URL) -> Bool {
        let aneDirectory = cacheRoot
            .appendingPathComponent("kokoro-82m-coreml", isDirectory: true)
            .appendingPathComponent("ANE", isDirectory: true)
        let requiredAneFiles = [
            "KokoroAlbert.mlmodelc",
            "KokoroPostAlbert.mlmodelc",
            "KokoroAlignment.mlmodelc",
            "KokoroProsody.mlmodelc",
            "KokoroNoise.mlmodelc",
            "KokoroVocoder.mlmodelc",
            "KokoroTail.mlmodelc",
            "vocab.json"
        ]
        guard requiredAneFiles.allSatisfy({
            FileManager.default.fileExists(atPath: aneDirectory.appendingPathComponent($0).path)
        }) else {
            return false
        }

        let g2pDirectory = cacheRoot.appendingPathComponent("kokoro", isDirectory: true)
        let requiredG2PFiles = [
            "G2PEncoder.mlmodelc",
            "G2PDecoder.mlmodelc",
            "g2p_vocab.json"
        ]
        return requiredG2PFiles.allSatisfy {
            FileManager.default.fileExists(atPath: g2pDirectory.appendingPathComponent($0).path)
        }
    }

    static func removeItemIfExists(at url: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}

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
