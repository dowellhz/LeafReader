import Foundation

extension SpeechRuntimeResourceManager {
    struct InstallManifest: Codable {
        let runtimeID: String
        let cacheDirectoryPaths: [String]
    }

    enum Runtime: CaseIterable {
        case kokoro
        case kitten

        private static let releaseDownloadsBaseURL = "https://github.com/dowellhz/LeafReader/releases"
        static let runtimeAssetsReleaseTag = "v1.5.10"

        static let displayOrder: [Runtime] = [.kitten, .kokoro]

        var id: String {
            switch self {
            case .kokoro:
                return "kokoro"
            case .kitten:
                return "kitten"
            }
        }

        var title: String {
            switch self {
            case .kokoro:
                return "Kokoro"
            case .kitten:
                return "KittenTTS"
            }
        }

        var downloadSizeText: String {
            switch self {
            case .kokoro:
                return "518 MB"
            case .kitten:
                return "74 MB"
            }
        }

        var minimumSystemVersion: OperatingSystemVersion {
            switch self {
            case .kokoro:
                return OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)
            case .kitten:
                return OperatingSystemVersion(majorVersion: 12, minorVersion: 0, patchVersion: 0)
            }
        }

        var minimumSystemVersionText: String {
            switch self {
            case .kokoro:
                return "macOS 14.0"
            case .kitten:
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
            }
        }

        static var modelManifestURL: URL {
            releaseAssetURL(fileName: "speech-models-manifest.json")
        }

        var installDirectory: URL {
            let root = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/share/leafreader", isDirectory: true)
            switch self {
            case .kokoro:
                return root.appendingPathComponent("kokoro-coreml", isDirectory: true)
            case .kitten:
                return root.appendingPathComponent("kittentts-rs-runtime", isDirectory: true)
            }
        }

        var bundledInstallDirectory: URL? {
            guard let resourceURL = Bundle.main.resourceURL else {
                return nil
            }
            let root = resourceURL.appendingPathComponent("SpeechRuntimes", isDirectory: true)
            switch self {
            case .kokoro:
                return root.appendingPathComponent("kokoro-coreml", isDirectory: true)
            case .kitten:
                return root.appendingPathComponent("kittentts-rs-runtime", isDirectory: true)
            }
        }

        var installDirectories: [URL] {
            [installDirectory, bundledInstallDirectory].compactMap { $0 }
        }

        var requiredPaths: [URL] {
            requiredPaths(in: installDirectory)
        }

        func requiredPaths(in directory: URL) -> [URL] {
            switch self {
            case .kokoro:
                return [
                    directory.appendingPathComponent("fluidaudiocli")
                ]
            case .kitten:
                return [
                    directory.appendingPathComponent("kitten-tts-aarch64-macos/kitten-tts"),
                    directory.appendingPathComponent("kitten-tts-aarch64-macos/kitten-tts-server"),
                    directory.appendingPathComponent("kitten-tts-mini", isDirectory: true)
                ]
            }
        }

        static var fluidAudioModelCacheRoot: URL {
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".cache/fluidaudio/Models", isDirectory: true)
        }

        private static func releaseAssetURL(fileName: String) -> URL {
            URL(string: "\(releaseDownloadsBaseURL)/download/\(runtimeAssetsReleaseTag)/\(fileName)")!
        }
    }
}
