import Foundation

enum SpeechRuntimeResourceManager {
    private static let stateQueue = DispatchQueue(label: "LeafReader.SpeechRuntimeResourceManager")
    private static var activeDownloads: [Runtime: [(Result<Void, Error>) -> Void]] = [:]
    private static var activeDownloadIDs: [Runtime: UUID] = [:]
    private static var activeTasks: [Runtime: URLSessionTask] = [:]
    private static var activeDownloaders: [Runtime: RuntimeDownload] = [:]
    private static var activeProgress: [Runtime: Double] = [:]
    private static var pausedDownloads = Set<Runtime>()
    private static let downloadErrorDomain = "LeafReader.SpeechRuntime.Download"
    private static let maxDownloadAttempts = 4
    private static let releaseDownloadsBaseURL = "https://github.com/dowellhz/LeafReader/releases"
    private static let installManifestFileName = ".leafreader-install-manifest.json"
    private static let lastFailureDefaultsPrefix = "speechRuntime.lastFailure."

    fileprivate struct InstallManifest: Codable {
        let runtimeID: String
        let cacheDirectoryPaths: [String]
    }

    private struct LastDownloadFailure: Codable {
        let message: String
        let timestamp: TimeInterval
    }

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

        var downloadURL: URL {
            switch self {
            case .kokoro:
                return Self.releaseAssetURL(fileName: "kokoro-coreml-macos-arm64.tar.gz")
            case .kitten:
                return Self.releaseAssetURL(fileName: "kitten-tts-rs-macos-arm64.tar.gz")
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

    static func isDownloaded(_ runtime: Runtime) -> Bool {
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

    static func isRunnable(_ runtime: Runtime) -> Bool {
        runtime.isSupportedOnCurrentSystem && isDownloaded(runtime)
    }

    static func runnableRuntime(preferredID: String) -> Runtime? {
        if let preferred = Runtime.runtime(for: preferredID),
           isRunnable(preferred) {
            return preferred
        }
        return runnableReadAloudRuntimes().first
    }

    static func runnableReadAloudRuntimes() -> [Runtime] {
        Runtime.displayOrder.filter { runtime in
            isRunnable(runtime)
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
        kokoroAneModelCacheExists(in: Runtime.fluidAudioModelCacheRoot)
    }

    private static func kokoroAneModelCacheExists(in cacheRoot: URL) -> Bool {
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
        if isDownloading(runtime) {
            if isPaused(runtime) {
                return AppText.localized("已暂停 · \(size)", "Paused · \(size)")
            }
            return AppText.localized("下载中 · \(size)", "Downloading · \(size)")
        }
        if !runtime.isSupportedOnCurrentSystem {
            if isDownloaded(runtime) {
                return AppText.localized(
                    "已下载 · 需要 \(runtime.minimumSystemVersionText) 或更高",
                    "Downloaded · Requires \(runtime.minimumSystemVersionText) or later"
                )
            }
            if let failure = lastDownloadFailure(for: runtime) {
                return AppText.localized(
                    "未下载 · 需要 \(runtime.minimumSystemVersionText) 或更高 · \(size) · 上次失败：\(failure.message)",
                    "Not downloaded · Requires \(runtime.minimumSystemVersionText) or later · \(size) · Last failed: \(failure.message)"
                )
            }
            return AppText.localized(
                "未下载 · 需要 \(runtime.minimumSystemVersionText) 或更高 · \(size)",
                "Not downloaded · Requires \(runtime.minimumSystemVersionText) or later · \(size)"
            )
        }
        if isRunnable(runtime) {
            return AppText.localized("已安装 · \(size)", "Installed · \(size)")
        }
        if let failure = lastDownloadFailure(for: runtime) {
            return AppText.localized(
                "未下载 · \(size) · 上次失败：\(failure.message)",
                "Not downloaded · \(size) · Last failed: \(failure.message)"
            )
        }
        return AppText.localized("未下载 · \(size)", "Not downloaded · \(size)")
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
        clearLastDownloadFailure(for: runtime)
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
        let manifest = installManifest(for: runtime)
        try removeItemIfExists(at: partialDownloadURL(for: runtime))
        try removeItemIfExists(at: runtime.installDirectory)
        clearLastDownloadFailure(for: runtime)
        if runtime == .kokoro {
            let modelCacheDirectories = manifest?.cacheDirectories ?? kokoroModelCacheDirectories()
            for modelCacheDirectory in modelCacheDirectories {
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
        var shouldStart = false
        let downloadID = UUID()
        stateQueue.sync {
            if activeDownloads[runtime] != nil {
                activeDownloads[runtime]?.append(completion)
            } else {
                activeDownloads[runtime] = [completion]
                activeDownloadIDs[runtime] = downloadID
                shouldStart = true
            }
        }
        guard shouldStart else { return }
        download(runtime, downloadID: downloadID, retryingWithoutResume: false) { result in
            finishDownload(runtime, downloadID: downloadID, result: result)
        }
    }

    private static func finishDownload(_ runtime: Runtime, downloadID: UUID, result: Result<Void, Error>) {
        let completions = stateQueue.sync {
            guard activeDownloadIDs[runtime] == downloadID else {
                return [] as [(Result<Void, Error>) -> Void]
            }
            let completions = activeDownloads[runtime] ?? []
            clearActiveDownloadState(for: runtime)
            return completions
        }
        guard !completions.isEmpty else { return }
        switch result {
        case .success:
            clearLastDownloadFailure(for: runtime)
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError {
                recordLastDownloadFailure(error, for: runtime)
            }
        }
        DispatchQueue.main.async {
            completions.forEach { $0(result) }
        }
    }

    private static func clearActiveDownloadState(for runtime: Runtime) {
        activeDownloads[runtime] = nil
        activeDownloadIDs[runtime] = nil
        activeTasks[runtime] = nil
        activeDownloaders[runtime] = nil
        activeProgress[runtime] = nil
        pausedDownloads.remove(runtime)
    }

    private static func download(
        _ runtime: Runtime,
        downloadID: UUID,
        retryingWithoutResume: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        download(runtime, downloadID: downloadID, retryingWithoutResume: retryingWithoutResume, attempt: 1, completion: completion)
    }

    private static func download(
        _ runtime: Runtime,
        downloadID: UUID,
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
            downloadID: downloadID,
            partialURL: partialURL,
            existingSize: existingSize,
            retryingWithoutResume: retryingWithoutResume
        ) { result in
            guard isCurrentDownload(runtime, downloadID: downloadID) else { return }
            do {
                switch result {
                case .success:
                    try validateArchive(at: partialURL)
                    guard isCurrentDownload(runtime, downloadID: downloadID) else { return }
                    try installArchive(partialURL, for: runtime)
                    try? fileManager.removeItem(at: partialURL)
                    DispatchQueue.main.async { completion(.success(())) }
                case .failure(let error):
                    let nsError = error as NSError
                    if shouldRetryDownload(error: nsError, attempt: attempt) {
                        if nsError.domain == downloadErrorDomain, nsError.code == 416 {
                            try? fileManager.removeItem(at: partialURL)
                            download(runtime, downloadID: downloadID, retryingWithoutResume: true, attempt: attempt + 1, completion: completion)
                        } else {
                            download(runtime, downloadID: downloadID, retryingWithoutResume: false, attempt: attempt + 1, completion: completion)
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
        let shouldResume = stateQueue.sync {
            guard activeDownloadIDs[runtime] == downloadID else {
                return false
            }
            activeTasks[runtime] = task
            activeDownloaders[runtime] = downloader
            activeProgress[runtime] = existingSize > 0 ? nil : 0
            return true
        }
        guard shouldResume else {
            session.invalidateAndCancel()
            return
        }
        task.resume()
    }

    private static func isCurrentDownload(_ runtime: Runtime, downloadID: UUID) -> Bool {
        stateQueue.sync {
            activeDownloadIDs[runtime] == downloadID
        }
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

    static func updateDownloadProgress(_ runtime: Runtime, downloadID: UUID, completedBytes: Int64, expectedBytes: Int64?) {
        guard let expectedBytes, expectedBytes > 0 else { return }
        stateQueue.sync {
            guard activeDownloadIDs[runtime] == downloadID else { return }
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

        let stagingDirectory = parent.appendingPathComponent(".\(runtime.id)-install-\(UUID().uuidString)", isDirectory: true)
        let backupDirectory = parent.appendingPathComponent(".\(runtime.id)-backup-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: stagingDirectory)
            try? fileManager.removeItem(at: backupDirectory)
        }
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", archiveURL.path, "-C", stagingDirectory.path]
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

        try validateExtractedRuntime(runtime, in: stagingDirectory)
        for path in runtime.requiredPaths(in: stagingDirectory) where !path.hasDirectoryPath {
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
                try? writeInstallManifest(runtime: runtime, cacheDirectories: cacheDirectories)
            } else {
                try? writeInstallManifest(runtime: runtime, cacheDirectories: [])
            }
        } catch {
            restoreRuntimeInstall(runtime, from: backupDirectory)
            throw error
        }
    }

    private static func validateExtractedRuntime(_ runtime: Runtime, in directory: URL) throws {
        let isValid: Bool
        switch runtime {
        case .kitten:
            isValid = kittenRuntimePathsExist(in: directory) && kittenModelPathsExist(in: directory)
        case .kokoro:
            let modelCacheRoot = directory.appendingPathComponent("Models", isDirectory: true)
            isValid = requiredPathsExist(runtime.requiredPaths(in: directory))
                && kokoroAneModelCacheExists(in: modelCacheRoot)
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

    private static func installBundledKokoroModelCache(from installDirectory: URL) throws -> [URL] {
        let fileManager = FileManager.default
        let cacheRoot = Runtime.fluidAudioModelCacheRoot
        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        var installedDirectories: [URL] = []
        for name in ["kokoro", "kokoro-82m-coreml"] {
            let source = installDirectory.appendingPathComponent("Models/\(name)", isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            let destination = cacheRoot.appendingPathComponent(name, isDirectory: true)
            let backup = cacheRoot.appendingPathComponent(".\(name)-backup-\(UUID().uuidString)", isDirectory: true)
            defer {
                try? fileManager.removeItem(at: backup)
            }
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.moveItem(at: destination, to: backup)
            }
            do {
                try fileManager.moveItem(at: source, to: destination)
                installedDirectories.append(destination)
            } catch {
                if fileManager.fileExists(atPath: backup.path),
                   !fileManager.fileExists(atPath: destination.path) {
                    try? fileManager.moveItem(at: backup, to: destination)
                }
                throw error
            }
        }
        return installedDirectories
    }

    private static func restoreRuntimeInstall(_ runtime: Runtime, from backupDirectory: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: backupDirectory.path) else { return }
        try? fileManager.removeItem(at: runtime.installDirectory)
        try? fileManager.moveItem(at: backupDirectory, to: runtime.installDirectory)
    }

    private static func installManifestURL(for runtime: Runtime) -> URL {
        runtime.installDirectory.appendingPathComponent(installManifestFileName)
    }

    private static func writeInstallManifest(runtime: Runtime, cacheDirectories: [URL]) throws {
        let manifest = InstallManifest(
            runtimeID: runtime.id,
            cacheDirectoryPaths: cacheDirectories.map(\.path)
        )
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: installManifestURL(for: runtime), options: .atomic)
    }

    private static func installManifest(for runtime: Runtime) -> InstallManifest? {
        guard let data = try? Data(contentsOf: installManifestURL(for: runtime)),
              let manifest = try? JSONDecoder().decode(InstallManifest.self, from: data),
              manifest.runtimeID == runtime.id else {
            return nil
        }
        return manifest
    }

    private static func lastFailureDefaultsKey(for runtime: Runtime) -> String {
        "\(lastFailureDefaultsPrefix)\(runtime.id)"
    }

    private static func lastDownloadFailure(for runtime: Runtime) -> LastDownloadFailure? {
        guard let data = UserDefaults.standard.data(forKey: lastFailureDefaultsKey(for: runtime)) else {
            return nil
        }
        return try? JSONDecoder().decode(LastDownloadFailure.self, from: data)
    }

    private static func recordLastDownloadFailure(_ error: Error, for runtime: Runtime) {
        let failure = LastDownloadFailure(
            message: sanitizedFailureMessage(from: error),
            timestamp: Date().timeIntervalSince1970
        )
        guard let data = try? JSONEncoder().encode(failure) else { return }
        UserDefaults.standard.set(data, forKey: lastFailureDefaultsKey(for: runtime))
    }

    private static func clearLastDownloadFailure(for runtime: Runtime) {
        UserDefaults.standard.removeObject(forKey: lastFailureDefaultsKey(for: runtime))
    }

    private static func sanitizedFailureMessage(from error: Error) -> String {
        let raw = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = AppText.localized("未知错误", "Unknown error")
        let message = NetworkErrorFormatter.sanitizedBody(raw.isEmpty ? fallback : raw)
        if message.count > 160 {
            return "\(message.prefix(160))..."
        }
        return message
    }
}

private extension SpeechRuntimeResourceManager.InstallManifest {
    var cacheDirectories: [URL] {
        cacheDirectoryPaths.compactMap { path in
            let url = URL(fileURLWithPath: path, isDirectory: true)
            return url.isInsideFluidAudioModelCache ? url : nil
        }
    }
}

private extension URL {
    var isInsideFluidAudioModelCache: Bool {
        let rootPath = SpeechRuntimeResourceManager.Runtime.fluidAudioModelCacheRoot
            .standardizedFileURL
            .path
        let path = standardizedFileURL.path
        return path.hasPrefix(rootPath + "/")
    }
}
