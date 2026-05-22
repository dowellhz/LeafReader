import Foundation

enum SpeechRuntimeResourceManager {
    private static let stateQueue = DispatchQueue(label: "LeafReader.SpeechRuntimeResourceManager")
    private static var activeDownloads: [Runtime: [(Result<Void, Error>) -> Void]] = [:]
    private static var activeTasks: [Runtime: URLSessionTask] = [:]
    private static var activeDownloaders: [Runtime: RuntimeDownload] = [:]
    private static var activeProgress: [Runtime: Double] = [:]
    private static var pausedDownloads = Set<Runtime>()
    private static let downloadErrorDomain = "LeafReader.SpeechRuntime.Download"
    private static let maxDownloadAttempts = 4
    private static let releaseDownloadsBaseURL = "https://github.com/dowellhz/LeafReader/releases"

    enum Runtime: CaseIterable {
        case kokoro
        case kitten

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

        static func isValidID(_ id: String) -> Bool {
            runtime(for: id) != nil
        }

        var downloadURL: URL {
            switch self {
            case .kokoro:
                return Self.releaseAssetURL(fileName: "kokoro-coreml-macos-arm64.tar.gz")
            case .kitten:
                return URL(string: "https://github.com/dowellhz/LeafReader/releases/download/v1.4.18/kitten-tts-rs-macos-arm64.tar.gz")!
            }
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
            if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
               !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return URL(string: "\(SpeechRuntimeResourceManager.releaseDownloadsBaseURL)/download/v\(version)/\(fileName)")!
            }
            return URL(string: "\(SpeechRuntimeResourceManager.releaseDownloadsBaseURL)/latest/download/\(fileName)")!
        }
    }

    static func isInstalled(_ runtime: Runtime) -> Bool {
        guard runtime.isSupportedOnCurrentSystem else { return false }
        if runtime == .kitten {
            return runtime.installDirectories.contains { directory in
                kittenRuntimePathsExist(in: directory)
            } && runtime.installDirectories.contains { directory in
                kittenModelPathsExist(in: directory)
            }
        }
        if runtime == .kokoro {
            return runtime.installDirectories.contains { directory in
                FileManager.default.isExecutableFile(atPath: directory.appendingPathComponent("fluidaudiocli").path)
            } && kokoroAneModelCacheExists()
        }
        return runtime.installDirectories.contains { directory in
            requiredPathsExist(runtime.requiredPaths(in: directory))
        }
    }

    static func installedRuntime(preferredID: String) -> Runtime? {
        if let preferred = Runtime.runtime(for: preferredID),
           isInstalled(preferred) {
            return preferred
        }
        return installedReadAloudRuntimes().first
    }

    static func installedReadAloudRuntimes() -> [Runtime] {
        Runtime.displayOrder.filter { runtime in
            isInstalled(runtime)
        }
    }

    private static func requiredPathsExist(_ paths: [URL]) -> Bool {
        paths.allSatisfy { path in
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory)
            if path.hasDirectoryPath {
                return exists && isDirectory.boolValue
            }
            return FileManager.default.isExecutableFile(atPath: path.path)
        }
    }

    private static func kittenRuntimePathsExist(in directory: URL) -> Bool {
        let server = directory.appendingPathComponent("kitten-tts-aarch64-macos/kitten-tts-server")
        return FileManager.default.isExecutableFile(atPath: server.path)
    }

    private static func kittenModelPathsExist(in directory: URL) -> Bool {
        let modelDirectory = directory.appendingPathComponent("kitten-tts-mini", isDirectory: true)
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

    private static func kokoroModelCacheDirectories() -> [URL] {
        let cacheRoot = Runtime.fluidAudioModelCacheRoot
        return [
            cacheRoot.appendingPathComponent("kokoro", isDirectory: true),
            cacheRoot.appendingPathComponent("kokoro-82m-coreml", isDirectory: true)
        ]
    }

    private static func kokoroAneModelCacheExists() -> Bool {
        let cacheRoot = Runtime.fluidAudioModelCacheRoot
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
            "vocab.json",
            "af_heart.bin"
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

    private static func removeItemIfExists(at url: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    static func statusText(for runtime: Runtime) -> String {
        let size = runtime.downloadSizeText
        if !runtime.isSupportedOnCurrentSystem {
            return AppText.localized("需要 \(runtime.minimumSystemVersionText) 或更高 · \(size)", "Requires \(runtime.minimumSystemVersionText) or later · \(size)")
        }
        if isDownloading(runtime) {
            if isPaused(runtime) {
                return AppText.localized("已暂停 · \(size)", "Paused · \(size)")
            }
            return AppText.localized("下载中 · \(size)", "Downloading · \(size)")
        }
        if isInstalled(runtime) {
            return AppText.localized("已安装 · \(size)", "Installed · \(size)")
        }
        return AppText.localized("未安装 · \(size)", "Not installed · \(size)")
    }

    static func isDownloading(_ runtime: Runtime) -> Bool {
        stateQueue.sync {
            activeDownloads[runtime] != nil
        }
    }

    static func isPaused(_ runtime: Runtime) -> Bool {
        stateQueue.sync {
            pausedDownloads.contains(runtime)
        }
    }

    static func pause(_ runtime: Runtime) {
        stateQueue.sync {
            guard activeDownloads[runtime] != nil else { return }
            activeTasks[runtime]?.suspend()
            pausedDownloads.insert(runtime)
        }
    }

    static func resume(_ runtime: Runtime) {
        stateQueue.sync {
            guard activeDownloads[runtime] != nil else { return }
            activeTasks[runtime]?.resume()
            pausedDownloads.remove(runtime)
        }
    }

    static func cancel(_ runtime: Runtime) {
        let completions = stopActiveDownload(for: runtime)
        try? FileManager.default.removeItem(at: partialDownloadURL(for: runtime))
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: NSUserCancelledError,
            userInfo: [NSLocalizedDescriptionKey: AppText.localized("下载已取消", "Download cancelled")]
        )
        DispatchQueue.main.async {
            completions.forEach { $0(.failure(error)) }
        }
    }

    static func downloadProgress(for runtime: Runtime) -> Double? {
        stateQueue.sync {
            guard activeDownloads[runtime] != nil,
                  let progress = activeTasks[runtime]?.progress.fractionCompleted,
                  progress.isFinite,
                  progress >= 0 else {
                return activeProgress[runtime]
            }
            return activeProgress[runtime] ?? progress
        }
    }

    static func delete(_ runtime: Runtime) throws {
        _ = stopActiveDownload(for: runtime)
        try removeItemIfExists(at: partialDownloadURL(for: runtime))
        try removeItemIfExists(at: runtime.installDirectory)
        if runtime == .kokoro {
            for modelCacheDirectory in kokoroModelCacheDirectories() {
                try removeItemIfExists(at: modelCacheDirectory)
            }
        }
    }

    private static func stopActiveDownload(for runtime: Runtime) -> [(Result<Void, Error>) -> Void] {
        stateQueue.sync {
            let completions = activeDownloads[runtime] ?? []
            let task = activeTasks[runtime]
            clearActiveDownloadState(for: runtime)
            task?.cancel()
            return completions
        }
    }

    static func download(_ runtime: Runtime, completion: @escaping (Result<Void, Error>) -> Void) {
        guard runtime.isSupportedOnCurrentSystem else {
            let error = NSError(
                domain: "LeafReader.SpeechRuntime",
                code: -10,
                userInfo: [
                    NSLocalizedDescriptionKey: AppText.localized(
                        "\(runtime.title) 需要 \(runtime.minimumSystemVersionText) 或更高版本。",
                        "\(runtime.title) requires \(runtime.minimumSystemVersionText) or later."
                    )
                ]
            )
            DispatchQueue.main.async {
                completion(.failure(error))
            }
            return
        }

        var shouldStart = false
        stateQueue.sync {
            if activeDownloads[runtime] != nil {
                activeDownloads[runtime]?.append(completion)
            } else {
                activeDownloads[runtime] = [completion]
                shouldStart = true
            }
        }
        guard shouldStart else { return }
        download(runtime, retryingWithoutResume: false) { result in
            finishDownload(runtime, result: result)
        }
    }

    private static func finishDownload(_ runtime: Runtime, result: Result<Void, Error>) {
        let completions = stateQueue.sync {
            let completions = activeDownloads[runtime] ?? []
            clearActiveDownloadState(for: runtime)
            return completions
        }
        DispatchQueue.main.async {
            completions.forEach { $0(result) }
        }
    }

    private static func clearActiveDownloadState(for runtime: Runtime) {
        activeDownloads[runtime] = nil
        activeTasks[runtime] = nil
        activeDownloaders[runtime] = nil
        activeProgress[runtime] = nil
        pausedDownloads.remove(runtime)
    }

    private static func download(_ runtime: Runtime, retryingWithoutResume: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        download(runtime, retryingWithoutResume: retryingWithoutResume, attempt: 1, completion: completion)
    }

    private static func download(
        _ runtime: Runtime,
        retryingWithoutResume: Bool,
        attempt: Int,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let fileManager = FileManager.default
        let partialURL = partialDownloadURL(for: runtime)
        let existingSize = retryingWithoutResume ? 0 : partialDownloadSize(at: partialURL)
        var request = URLRequest(url: runtime.downloadURL, cachePolicy: .reloadIgnoringLocalCacheData)
        if existingSize > 0 {
            request.setValue("bytes=\(existingSize)-", forHTTPHeaderField: "Range")
        }

        let downloader = RuntimeDownload(
            runtime: runtime,
            partialURL: partialURL,
            existingSize: existingSize,
            retryingWithoutResume: retryingWithoutResume
        ) { result in
            do {
                switch result {
                case .success:
                    try validateArchive(at: partialURL)
                    try installArchive(partialURL, for: runtime)
                    try? fileManager.removeItem(at: partialURL)
                    DispatchQueue.main.async { completion(.success(())) }
                case .failure(let error):
                    let nsError = error as NSError
                    if shouldRetryDownload(error: nsError, attempt: attempt) {
                        if nsError.domain == downloadErrorDomain, nsError.code == 416 {
                            try? fileManager.removeItem(at: partialURL)
                            download(runtime, retryingWithoutResume: true, attempt: attempt + 1, completion: completion)
                        } else {
                            download(runtime, retryingWithoutResume: false, attempt: attempt + 1, completion: completion)
                        }
                    } else {
                        DispatchQueue.main.async { completion(.failure(error)) }
                    }
                    return
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }

        let session = URLSession(configuration: .default, delegate: downloader, delegateQueue: nil)
        downloader.session = session
        let task = session.dataTask(with: request)
        downloader.task = task
        stateQueue.sync {
            activeTasks[runtime] = task
            activeDownloaders[runtime] = downloader
            activeProgress[runtime] = existingSize > 0 ? nil : 0
        }
        task.resume()
    }

    private static func shouldRetryDownload(error: NSError, attempt: Int) -> Bool {
        guard attempt < maxDownloadAttempts else { return false }
        if error.domain == downloadErrorDomain, error.code == 416 {
            return true
        }
        if error.domain == NSURLErrorDomain {
            return error.code != NSURLErrorCancelled
        }
        return false
    }

    static func updateDownloadProgress(_ runtime: Runtime, completedBytes: Int64, expectedBytes: Int64?) {
        guard let expectedBytes, expectedBytes > 0 else { return }
        stateQueue.sync {
            activeProgress[runtime] = min(1, max(0, Double(completedBytes) / Double(expectedBytes)))
        }
    }

    private static func partialDownloadURL(for runtime: Runtime) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/leafreader/downloads", isDirectory: true)
            .appendingPathComponent(runtime.downloadURL.lastPathComponent + ".part")
    }

    private static func partialDownloadSize(at url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return 0
        }
        return size.int64Value
    }

    private static func validateArchive(at archiveURL: URL) throws {
        let handle = try FileHandle(forReadingFrom: archiveURL)
        defer { try? handle.close() }
        let magic = handle.readData(ofLength: 2)
        guard magic == Data([0x1f, 0x8b]) else {
            throw NSError(
                domain: downloadErrorDomain,
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: AppText.localized("下载文件不是有效的模型压缩包，请稍后重试。", "The downloaded file is not a valid model archive. Please try again later.")]
            )
        }
    }

    private static func installArchive(_ archiveURL: URL, for runtime: Runtime) throws {
        let fileManager = FileManager.default
        let parent = runtime.installDirectory.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        try? fileManager.removeItem(at: runtime.installDirectory)
        try fileManager.createDirectory(at: runtime.installDirectory, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", archiveURL.path, "-C", runtime.installDirectory.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(
                domain: "LeafReader.SpeechRuntime",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message.isEmpty ? "Failed to extract speech runtime." : message]
            )
        }

        for path in runtime.requiredPaths where !path.hasDirectoryPath {
            try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
        }
        if runtime == .kokoro {
            try installBundledKokoroModelCache(from: runtime.installDirectory)
        }
    }

    private static func installBundledKokoroModelCache(from installDirectory: URL) throws {
        let fileManager = FileManager.default
        let cacheRoot = Runtime.fluidAudioModelCacheRoot
        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        for name in ["kokoro", "kokoro-82m-coreml"] {
            let source = installDirectory.appendingPathComponent("Models/\(name)", isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            let destination = cacheRoot.appendingPathComponent(name, isDirectory: true)
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: source, to: destination)
        }
    }
}
