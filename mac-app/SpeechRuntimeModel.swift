import Foundation

extension SpeechRuntimeResourceManager {
    struct InstallManifest: Codable {
        let runtimeID: String
        let cacheDirectoryPaths: [String]
    }

    enum Runtime: CaseIterable {
        case kokoro
        case kitten
        case piper

        private static let releaseDownloadsBaseURL = "https://github.com/dowellhz/LeafReader/releases"
        static let runtimeAssetsReleaseTag = "v1.5.10"

        static let displayOrder: [Runtime] = [.kitten, .piper, .kokoro]

        var id: String {
            switch self {
            case .kokoro:
                return "kokoro"
            case .kitten:
                return "kitten"
            case .piper:
                return "piper"
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
            }
        }

        var isSupportedOnCurrentSystem: Bool {
            ProcessInfo.processInfo.isOperatingSystemAtLeast(minimumSystemVersion)
        }

        static func runtime(for id: String) -> Runtime? {
            displayOrder.first { $0.id == id }
        }

        var downloadURL: URL {
            switch self {
            case .kokoro:
                return Self.releaseAssetURL(fileName: "kokoro-coreml-macos-arm64.tar.gz")
            case .kitten:
                return Self.releaseAssetURL(fileName: "kitten-tts-rs-macos-arm64.tar.gz")
            case .piper:
                return Self.releaseAssetURL(fileName: "piper-tts-macos-arm64.tar.gz")
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
            }
        }
    }
}
