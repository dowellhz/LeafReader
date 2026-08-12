import Foundation

extension SpeechRuntimeResourceManager {
    typealias InstallManifest = LocalRuntimeInstallManifest

    enum Runtime: CaseIterable, Hashable {
        case kokoro
        case piper
        case supertonic

        private static let releaseDownloadsBaseURL = "https://github.com/dowellhz/LeafReader/releases"
        // Speech model archives are versioned independently from app releases. Only move
        // this tag when publishing new model assets with scripts/publish_release.sh --with-speech-models.
        static let runtimeAssetsReleaseTag = "v1.5.10"

        static let displayOrder: [Runtime] = [.piper, .supertonic, .kokoro]

        private struct Definition {
            let id: String
            let title: String
            let downloadSizeText: String
            let summaryChinese: String
            let summaryEnglish: String
            let minimumSystemVersion: OperatingSystemVersion
            let minimumSystemVersionText: String
            let archiveFileName: String
            let installDirectoryName: String
            let executableRelativePath: String
        }

        private static let definitions: [Runtime: Definition] = [
            .kokoro: Definition(
                id: "kokoro",
                title: "Kokoro",
                downloadSizeText: "518 MB",
                summaryChinese: "FluidAudio CoreML runtime，支持英语和中文",
                summaryEnglish: "FluidAudio CoreML runtime, supports English and Chinese",
                minimumSystemVersion: OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0),
                minimumSystemVersionText: "macOS 14.0",
                archiveFileName: "kokoro-coreml-macos-arm64.tar.gz",
                installDirectoryName: "kokoro-coreml",
                executableRelativePath: "fluidaudiocli"
            ),
            .piper: Definition(
                id: "piper",
                title: "Piper",
                downloadSizeText: "约 112 MB",
                summaryChinese: "模型中等，英语质量好",
                summaryEnglish: "Medium model, good English quality",
                minimumSystemVersion: OperatingSystemVersion(majorVersion: 12, minorVersion: 0, patchVersion: 0),
                minimumSystemVersionText: "macOS 12.0",
                archiveFileName: "piper-tts-macos-arm64.tar.gz",
                installDirectoryName: "piper-tts-runtime",
                executableRelativePath: "piper/piper"
            ),
            .supertonic: Definition(
                id: "supertonic",
                title: "Supertonic",
                downloadSizeText: "约 209 MB",
                summaryChinese: "Supertonic 3 模型，复用 FluidAudio CoreML runtime",
                summaryEnglish: "Supertonic 3 model, reuses the FluidAudio CoreML runtime",
                minimumSystemVersion: OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0),
                minimumSystemVersionText: "macOS 14.0",
                archiveFileName: "supertonic-coreml-macos-arm64.tar.gz",
                installDirectoryName: "supertonic-coreml",
                executableRelativePath: "supertonic-mini"
            )
        ]

        private var definition: Definition {
            guard let definition = Self.definitions[self] else {
                preconditionFailure("Missing speech runtime definition for \(self)")
            }
            return definition
        }

        var id: String {
            definition.id
        }

        var title: String {
            definition.title
        }

        var downloadSizeText: String {
            definition.downloadSizeText
        }

        var summaryText: String {
            AppText.localized(definition.summaryChinese, definition.summaryEnglish)
        }

        var minimumSystemVersion: OperatingSystemVersion {
            definition.minimumSystemVersion
        }

        var minimumSystemVersionText: String {
            definition.minimumSystemVersionText
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
            Self.releaseAssetURL(fileName: definition.archiveFileName)
        }

        static var modelManifestURL: URL {
            releaseAssetURL(fileName: "speech-models-manifest.json")
        }

        var manifestURL: URL {
            Self.modelManifestURL
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

        func modelDirectory(in directory: URL) -> URL {
            switch self {
            case .kokoro:
                return directory.appendingPathComponent("Models", isDirectory: true)
            case .piper:
                return Self.piperVoiceCacheRoot
            case .supertonic:
                return Self.supertonicCoreMLModelCacheDirectory
            }
        }

        func executableURL(in directory: URL) -> URL {
            directory.appendingPathComponent(definition.executableRelativePath)
        }

        func requiredPaths(in directory: URL) -> [URL] {
            switch self {
            case .kokoro:
                return [
                    executableURL(in: directory)
                ]
            case .piper:
                return [
                    executableURL(in: directory)
                ]
            case .supertonic:
                return [
                    executableURL(in: directory)
                ]
            }
        }

        static var fluidAudioModelCacheRoot: URL {
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".cache/fluidaudio/Models", isDirectory: true)
        }

        static var supertonicCoreMLModelCacheDirectory: URL {
            fluidAudioModelCacheRoot.appendingPathComponent("supertonic-3", isDirectory: true)
        }

        static var piperVoiceCacheRoot: URL {
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".cache/leafreader/piper-voices", isDirectory: true)
        }

        private static func releaseAssetURL(fileName: String) -> URL {
            guard let baseURL = URL(string: releaseDownloadsBaseURL) else {
                preconditionFailure("Invalid speech runtime release base URL")
            }
            return baseURL
                .appendingPathComponent("download", isDirectory: true)
                .appendingPathComponent(runtimeAssetsReleaseTag, isDirectory: true)
                .appendingPathComponent(fileName)
        }

        private func runtimeDirectory(in root: URL) -> URL {
            root.appendingPathComponent(definition.installDirectoryName, isDirectory: true)
        }
    }
}
