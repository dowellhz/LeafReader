import Foundation

extension SpeechRuntimeResourceManager {
    static func installArchive(_ archiveURL: URL, for runtime: Runtime) throws {
        let fileManager = FileManager.default
        let parent = runtime.installDirectory.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        let stagingDirectory = parent.appendingPathComponent(".\(runtime.id)-install-\(UUID().uuidString)", isDirectory: true)
        let backupDirectory = parent.appendingPathComponent(".\(runtime.id)-backup-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: stagingDirectory)
            try? fileManager.removeItem(at: backupDirectory)
        }
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        let result = try ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["-xzf", archiveURL.path, "-C", stagingDirectory.path],
            timeout: installArchiveTimeout
        )
        guard !result.timedOut else {
            throw NSError(
                domain: "LeafReader.SpeechRuntime",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: AppText.localized("模型安装超时，请重试。", "Speech runtime installation timed out. Please try again.")]
            )
        }
        guard result.terminationStatus == 0 else {
            let message = String(data: result.stderr, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw NSError(
                domain: "LeafReader.SpeechRuntime",
                code: Int(result.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message.isEmpty ? "Failed to extract speech runtime." : message]
            )
        }

        try validateExtractedRuntime(runtime, in: stagingDirectory)
        for path in runtime.requiredPaths(in: stagingDirectory) where !path.hasDirectoryPath {
            guard fileManager.fileExists(atPath: path.path) else { continue }
            try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
        }

        if fileManager.fileExists(atPath: runtime.installDirectory.path) {
            try fileManager.moveItem(at: runtime.installDirectory, to: backupDirectory)
        }
        do {
            try fileManager.moveItem(at: stagingDirectory, to: runtime.installDirectory)
        } catch {
            if fileManager.fileExists(atPath: backupDirectory.path),
               !fileManager.fileExists(atPath: runtime.installDirectory.path) {
                try? fileManager.moveItem(at: backupDirectory, to: runtime.installDirectory)
            }
            throw error
        }
        do {
            if runtime == .kokoro {
                let cacheDirectories = try installBundledKokoroModelCache(from: runtime.installDirectory)
                try writeInstallManifest(runtime: runtime, cacheDirectories: cacheDirectories)
            } else if runtime == .piper {
                let cacheDirectories = try installBundledPiperVoiceCache(from: runtime.installDirectory)
                try writeInstallManifest(runtime: runtime, cacheDirectories: cacheDirectories)
            } else {
                try writeInstallManifest(runtime: runtime, cacheDirectories: [])
            }
        } catch {
            restoreRuntimeInstall(runtime, from: backupDirectory)
            throw error
        }
    }

    static func validateExtractedRuntime(_ runtime: Runtime, in directory: URL) throws {
        let isValid: Bool
        switch runtime {
        case .kitten:
            isValid = kittenModelPathsExist(in: directory)
                && (kittenRuntimePathsExist(in: directory) || bundledRuntimePathsExist(for: runtime))
        case .kokoro:
            let modelCacheRoot = runtime.modelDirectory(in: directory)
            isValid = (requiredPathsExist(runtime.requiredPaths(in: directory)) || bundledRuntimePathsExist(for: runtime))
                && kokoroAneModelCacheExists(in: modelCacheRoot)
        case .piper:
            let voiceDirectory = directory.appendingPathComponent("Voices", isDirectory: true)
            isValid = (requiredPathsExist(runtime.requiredPaths(in: directory)) || bundledRuntimePathsExist(for: runtime))
                && (piperVoicePathsExist(in: voiceDirectory) || piperVoicePathsExist())
        }
        guard isValid else {
            throw NSError(
                domain: "LeafReader.SpeechRuntime",
                code: -4,
                userInfo: [
                    NSLocalizedDescriptionKey: AppText.localized(
                        "模型压缩包缺少必要文件，已保留原有模型。",
                        "The model archive is missing required files; the existing model was preserved."
                    )
                ]
            )
        }
    }

    static func installBundledKokoroModelCache(from installDirectory: URL) throws -> [URL] {
        let fileManager = FileManager.default
        let cacheRoot = Runtime.fluidAudioModelCacheRoot
        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        var transaction = KokoroCacheInstallTransaction(fileManager: fileManager)
        for name in ["kokoro", "kokoro-82m-coreml"] {
            let source = Runtime.kokoro.modelDirectory(in: installDirectory)
                .appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            let destination = cacheRoot.appendingPathComponent(name, isDirectory: true)
            let backup = cacheRoot
                .appendingPathComponent(".\(name)-backup-\(UUID().uuidString)", isDirectory: true)
            try transaction.replace(source: source, destination: destination, backup: backup)
        }
        transaction.commit()
        return transaction.installedDirectories
    }

    static func installBundledPiperVoiceCache(from installDirectory: URL) throws -> [URL] {
        let fileManager = FileManager.default
        let source = installDirectory.appendingPathComponent("Voices", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return []
        }

        let cacheRoot = Runtime.piperVoiceCacheRoot
        try fileManager.createDirectory(at: cacheRoot.deletingLastPathComponent(), withIntermediateDirectories: true)
        let backup = cacheRoot
            .deletingLastPathComponent()
            .appendingPathComponent(".piper-voices-backup-\(UUID().uuidString)", isDirectory: true)
        var transaction = KokoroCacheInstallTransaction(fileManager: fileManager)
        try transaction.replace(source: source, destination: cacheRoot, backup: backup)
        transaction.commit()
        return transaction.installedDirectories
    }

    static func restoreRuntimeInstall(_ runtime: Runtime, from backupDirectory: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: backupDirectory.path) else { return }
        try? fileManager.removeItem(at: runtime.installDirectory)
        try? fileManager.moveItem(at: backupDirectory, to: runtime.installDirectory)
    }

    static func installManifestURL(for runtime: Runtime) -> URL {
        runtime.installDirectory.appendingPathComponent(installManifestFileName)
    }

    static func writeInstallManifest(runtime: Runtime, cacheDirectories: [URL]) throws {
        let manifest = InstallManifest(
            runtimeID: runtime.id,
            cacheDirectoryPaths: cacheDirectories.map(\.path)
        )
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: installManifestURL(for: runtime), options: .atomic)
    }

    static func installManifest(for runtime: Runtime) -> InstallManifest? {
        guard let data = try? Data(contentsOf: installManifestURL(for: runtime)),
              let manifest = try? JSONDecoder().decode(InstallManifest.self, from: data),
              manifest.runtimeID == runtime.id else {
            return nil
        }
        return manifest
    }
}
