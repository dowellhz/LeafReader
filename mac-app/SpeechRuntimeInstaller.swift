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
            let cacheDirectories = try SpeechRuntimeCacheStrategy
                .strategy(for: runtime)
                .installCaches(from: runtime.installDirectory)
            try writeInstallManifest(runtime: runtime, cacheDirectories: cacheDirectories)
            try validateInstalledRuntimeIsUsable(runtime)
        } catch {
            restoreRuntimeInstall(runtime, from: backupDirectory)
            throw error
        }
    }

    static func validateInstalledRuntimeIsUsable(_ runtime: Runtime) throws {
        guard isDownloaded(runtime) else {
            throw NSError(
                domain: "LeafReader.SpeechRuntime",
                code: -9,
                userInfo: [
                    NSLocalizedDescriptionKey: AppText.localized(
                        "模型安装完成但仍不可用，请重新下载。",
                        "The model was installed but is still unavailable. Please download it again."
                    )
                ]
            )
        }
    }

    static func validateExtractedRuntime(_ runtime: Runtime, in directory: URL) throws {
        try SpeechRuntimeArchiveValidator.validate(runtime, in: directory)
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
