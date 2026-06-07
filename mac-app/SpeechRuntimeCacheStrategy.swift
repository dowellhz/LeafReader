import Foundation

struct SpeechRuntimeCacheMove {
    let source: URL
    let destination: URL
    let backupNamePrefix: String
}

struct SpeechRuntimeCacheStrategy {
    typealias Runtime = SpeechRuntimeResourceManager.Runtime
    typealias InstallManifest = SpeechRuntimeResourceManager.InstallManifest

    let runtime: Runtime
    let invalidatesKokoroVoiceCache: Bool
    let fallbackDeleteDirectories: [URL]
    let useFallbackDeleteDirectoriesWhenManifestIsEmpty: Bool
    private let moves: (URL) -> [SpeechRuntimeCacheMove]

    static func strategy(for runtime: Runtime) -> SpeechRuntimeCacheStrategy {
        switch runtime {
        case .kokoro:
            return SpeechRuntimeCacheStrategy(
                runtime: runtime,
                invalidatesKokoroVoiceCache: true,
                fallbackDeleteDirectories: SpeechRuntimePathChecks.kokoroModelCacheDirectories(),
                useFallbackDeleteDirectoriesWhenManifestIsEmpty: false
            ) { installDirectory in
                ["kokoro", "kokoro-82m-coreml"].map { name in
                    SpeechRuntimeCacheMove(
                        source: Runtime.kokoro.modelDirectory(in: installDirectory)
                            .appendingPathComponent(name, isDirectory: true),
                        destination: Runtime.fluidAudioModelCacheRoot
                            .appendingPathComponent(name, isDirectory: true),
                        backupNamePrefix: name
                    )
                }
            }
        case .piper:
            return SpeechRuntimeCacheStrategy(
                runtime: runtime,
                invalidatesKokoroVoiceCache: false,
                fallbackDeleteDirectories: SpeechRuntimePathChecks.piperVoiceCacheDirectories(),
                useFallbackDeleteDirectoriesWhenManifestIsEmpty: true
            ) { installDirectory in
                [
                    SpeechRuntimeCacheMove(
                        source: installDirectory.appendingPathComponent("Voices", isDirectory: true),
                        destination: Runtime.piperVoiceCacheRoot,
                        backupNamePrefix: "piper-voices"
                    )
                ]
            }
        case .supertonic:
            return SpeechRuntimeCacheStrategy(
                runtime: runtime,
                invalidatesKokoroVoiceCache: false,
                fallbackDeleteDirectories: SpeechRuntimePathChecks.supertonicCoreMLModelCacheDirectories(),
                useFallbackDeleteDirectoriesWhenManifestIsEmpty: false
            ) { installDirectory in
                [
                    SpeechRuntimeCacheMove(
                        source: installDirectory
                            .appendingPathComponent("Models", isDirectory: true)
                            .appendingPathComponent("supertonic-3", isDirectory: true),
                        destination: Runtime.supertonicCoreMLModelCacheDirectory,
                        backupNamePrefix: "supertonic-3"
                    )
                ]
            }
        case .kitten:
            return SpeechRuntimeCacheStrategy(
                runtime: runtime,
                invalidatesKokoroVoiceCache: false,
                fallbackDeleteDirectories: [],
                useFallbackDeleteDirectoriesWhenManifestIsEmpty: false,
                moves: { _ in [] }
            )
        }
    }

    func installCaches(from installDirectory: URL) throws -> [URL] {
        let fileManager = FileManager.default
        var transaction = KokoroCacheInstallTransaction(fileManager: fileManager)
        for move in moves(installDirectory) {
            guard SpeechRuntimePathChecks.directoryExists(move.source) else { continue }
            let destinationParent = move.destination.deletingLastPathComponent()
            try fileManager.createDirectory(at: destinationParent, withIntermediateDirectories: true)
            let backup = destinationParent
                .appendingPathComponent(".\(move.backupNamePrefix)-backup-\(UUID().uuidString)", isDirectory: true)
            try transaction.replace(source: move.source, destination: move.destination, backup: backup)
        }
        transaction.commit()
        return transaction.installedDirectories
    }

    func deleteDirectories(from manifest: InstallManifest?) -> [URL] {
        guard let manifest else {
            return fallbackDeleteDirectories
        }
        let directories = manifest.cacheDirectories
        if directories.isEmpty, useFallbackDeleteDirectoriesWhenManifestIsEmpty {
            return fallbackDeleteDirectories
        }
        return directories
    }
}
