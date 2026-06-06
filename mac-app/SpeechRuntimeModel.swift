import Foundation

extension SpeechRuntimeResourceManager {
    typealias InstallManifest = LocalRuntimeInstallManifest

    enum Runtime: CaseIterable {
        case kokoro
        case kitten
        case piper
        case supertonic

        private static let releaseDownloadsBaseURL = "https://github.com/dowellhz/LeafReader/releases"
        // Speech model archives are versioned independently from app releases. Only move
        // this tag when publishing new model assets with scripts/publish_release.sh --with-speech-models.
        static let runtimeAssetsReleaseTag = "v1.5.10"

        static let displayOrder: [Runtime] = [.kitten, .piper, .supertonic, .kokoro]

        var id: String {
            switch self {
            case .kokoro:
                return "kokoro"
            case .kitten:
                return "kitten"
            case .piper:
                return "piper"
            case .supertonic:
                return "supertonic"
            }
        }

        var title: String {
            switch self {
            case .kokoro:
                return "Kokoro"
            case .kitten:
                return "KittenTTS"
            case .piper:
                return "Piper"
            case .supertonic:
                return "Supertonic"
            }
        }

        var downloadSizeText: String {
            switch self {
            case .kokoro:
                return "518 MB"
            case .kitten:
                return "74 MB"
            case .piper:
                return "约 112 MB"
            case .supertonic:
                return AppText.localized("手动安装", "Manual install")
            }
        }

        var summaryText: String {
            switch self {
            case .kokoro:
                return AppText.localized("模型大，支持英语和中文", "Large model, supports English and Chinese")
            case .kitten:
                return AppText.localized("模型小，只有英文", "Small model, English only")
            case .piper:
                return AppText.localized("模型中等，英语质量好", "Medium model, good English quality")
            case .supertonic:
                return AppText.localized("Supertonic 3 MLX，多语言本地朗读", "Supertonic 3 MLX, multilingual local speech")
            }
        }

        var minimumSystemVersion: OperatingSystemVersion {
            switch self {
            case .kokoro:
                return OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)
            case .kitten:
                return OperatingSystemVersion(majorVersion: 12, minorVersion: 0, patchVersion: 0)
            case .piper:
                return OperatingSystemVersion(majorVersion: 12, minorVersion: 0, patchVersion: 0)
            case .supertonic:
                return OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)
            }
        }

        var minimumSystemVersionText: String {
            switch self {
            case .kokoro:
                return "macOS 14.0"
            case .kitten:
                return "macOS 12.0"
            case .piper:
                return "macOS 12.0"
            case .supertonic:
                return "macOS 14.0"
            }
        }

        var isSupportedOnCurrentSystem: Bool {
            ProcessInfo.processInfo.isOperatingSystemAtLeast(minimumSystemVersion)
        }

        static func runtime(for id: String) -> Runtime? {
            displayOrder.first { $0.id == id }
        }

        static var localRuntimeRegistry: LocalRuntimeRegistry {
            SpeechRuntimeCatalog.registry
        }

        static var localRuntimeDescriptors: [LocalRuntimeDescriptor] {
            SpeechRuntimeCatalog.descriptors
        }

        static var localRuntimeDownloadPlans: [LocalRuntimeDownloadPlan] {
            SpeechRuntimeCatalog.downloadPlans
        }

        var localRuntimeDescriptor: LocalRuntimeDescriptor {
            SpeechRuntimeCatalog.descriptor(for: self)
        }

        var localRuntimeDownloadPlan: LocalRuntimeDownloadPlan {
            SpeechRuntimeCatalog.downloadPlan(for: self)
        }

        var downloadURL: URL {
            switch self {
            case .kokoro:
                return Self.releaseAssetURL(fileName: "kokoro-coreml-macos-arm64.tar.gz")
            case .kitten:
                return Self.releaseAssetURL(fileName: "kitten-tts-rs-macos-arm64.tar.gz")
            case .piper:
                return Self.releaseAssetURL(fileName: "piper-tts-macos-arm64.tar.gz")
            case .supertonic:
                return URL(string: "https://github.com/ailuntx/supertonic-mlx/archive/refs/heads/main.tar.gz")!
            }
        }

        static var modelManifestURL: URL {
            releaseAssetURL(fileName: "speech-models-manifest.json")
        }

        private static var userInstallRoot: URL {
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/share/leafreader", isDirectory: true)
        }

        private static var bundledRuntimeRoot: URL? {
            Bundle.main.resourceURL?
                .appendingPathComponent("SpeechRuntimes", isDirectory: true)
        }

        var installDirectory: URL {
            runtimeDirectory(in: Self.userInstallRoot)
        }

        var bundledInstallDirectory: URL? {
            Self.bundledRuntimeRoot.map { runtimeDirectory(in: $0) }
        }

        var installDirectories: [URL] {
            [installDirectory, bundledInstallDirectory].compactMap { $0 }
        }

        var requiredPaths: [URL] {
            requiredPaths(in: installDirectory)
        }

        var bundledExecutableURL: URL? {
            bundledInstallDirectory.map(executableURL(in:))
        }

        var userExecutableURL: URL {
            executableURL(in: installDirectory)
        }

        var kittenModelDirectoryName: String {
            "kitten-tts-mini"
        }

        func modelDirectory(in directory: URL) -> URL {
            switch self {
            case .kokoro:
                return directory.appendingPathComponent("Models", isDirectory: true)
            case .kitten:
                return directory.appendingPathComponent(kittenModelDirectoryName, isDirectory: true)
            case .piper:
                return Self.piperVoiceCacheRoot
            case .supertonic:
                return directory.appendingPathComponent("supertonic-3-mlx", isDirectory: true)
            }
        }

        func executableURL(in directory: URL) -> URL {
            switch self {
            case .kokoro:
                return directory.appendingPathComponent("fluidaudiocli")
            case .kitten:
                return directory.appendingPathComponent("kitten-tts-aarch64-macos/kitten-tts-server")
            case .piper:
                return directory.appendingPathComponent("piper/piper")
            case .supertonic:
                return directory.appendingPathComponent("scripts/infer_mlx.py")
            }
        }

        func requiredPaths(in directory: URL) -> [URL] {
            switch self {
            case .kokoro:
                return [
                    executableURL(in: directory)
                ]
            case .kitten:
                return [
                    directory.appendingPathComponent("kitten-tts-aarch64-macos/kitten-tts"),
                    executableURL(in: directory),
                    modelDirectory(in: directory)
                ]
            case .piper:
                return [
                    executableURL(in: directory)
                ]
            case .supertonic:
                return [
                    executableURL(in: directory),
                    directory.appendingPathComponent("supertonic_mlx", isDirectory: true),
                    modelDirectory(in: directory)
                ]
            }
        }

        static var fluidAudioModelCacheRoot: URL {
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".cache/fluidaudio/Models", isDirectory: true)
        }

        static var piperVoiceCacheRoot: URL {
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".cache/leafreader/piper-voices", isDirectory: true)
        }

        private static func releaseAssetURL(fileName: String) -> URL {
            URL(string: "\(releaseDownloadsBaseURL)/download/\(runtimeAssetsReleaseTag)/\(fileName)")!
        }

        private func runtimeDirectory(in root: URL) -> URL {
            switch self {
            case .kokoro:
                return root.appendingPathComponent("kokoro-coreml", isDirectory: true)
            case .kitten:
                return root.appendingPathComponent("kittentts-rs-runtime", isDirectory: true)
            case .piper:
                return root.appendingPathComponent("piper-tts-runtime", isDirectory: true)
            case .supertonic:
                return root.appendingPathComponent("supertonic-mlx", isDirectory: true)
            }
        }
    }
}
