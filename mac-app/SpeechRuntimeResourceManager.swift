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
                return "372 MB"
            case .kitten:
                return "74 MB"
            }
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
                return URL(string: "https://github.com/dowellhz/LeafReader/releases/download/v1.4.18/kokoro-coreml-macos-arm64.tar.gz")!
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
                    directory.appendingPathComponent("fluidaudiocli"),
                    Self.fluidAudioModelCacheRoot.appendingPathComponent("kokoro", isDirectory: true)
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
    }

    static func isInstalled(_ runtime: Runtime) -> Bool {
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
            } && kokoroModelPathsExist()
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

    private static func kokoroModelPathsExist() -> Bool {
        let modelDirectory = Runtime.fluidAudioModelCacheRoot.appendingPathComponent("kokoro", isDirectory: true)
        let model = modelDirectory.appendingPathComponent("kokoro_21_15s.mlmodelc", isDirectory: true)
        let voices = modelDirectory.appendingPathComponent("voices", isDirectory: true)
        let config = modelDirectory.appendingPathComponent("config.json")
        let vocab = modelDirectory.appendingPathComponent("vocab_index.json")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: modelDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              FileManager.default.fileExists(atPath: model.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              FileManager.default.fileExists(atPath: voices.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }
        return FileManager.default.fileExists(atPath: config.path)
            && FileManager.default.fileExists(atPath: vocab.path)
    }

    private static func kokoroModelCacheDirectories() -> [URL] {
        let cacheRoot = Runtime.fluidAudioModelCacheRoot
        return [
            cacheRoot.appendingPathComponent("kokoro", isDirectory: true),
            cacheRoot.appendingPathComponent("kokoro-82m-coreml", isDirectory: true)
        ]
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

    fileprivate static func updateDownloadProgress(_ runtime: Runtime, completedBytes: Int64, expectedBytes: Int64?) {
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
        let source = installDirectory.appendingPathComponent("Models/kokoro", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return
        }
        let cacheRoot = Runtime.fluidAudioModelCacheRoot
        let destination = cacheRoot.appendingPathComponent("kokoro", isDirectory: true)
        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: source, to: destination)
    }
}

private final class RuntimeDownload: NSObject, URLSessionDataDelegate {
    private let runtime: SpeechRuntimeResourceManager.Runtime
    private let partialURL: URL
    private let existingSize: Int64
    private let retryingWithoutResume: Bool
    private let completion: (Result<Void, Error>) -> Void
    private var fileHandle: FileHandle?
    private var expectedBytes: Int64?
    private var completedBytes: Int64
    private var completionSent = false
    private var downloadError: Error?

    var session: URLSession?
    weak var task: URLSessionTask?

    init(
        runtime: SpeechRuntimeResourceManager.Runtime,
        partialURL: URL,
        existingSize: Int64,
        retryingWithoutResume: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        self.runtime = runtime
        self.partialURL = partialURL
        self.existingSize = existingSize
        self.retryingWithoutResume = retryingWithoutResume
        self.completion = completion
        self.completedBytes = existingSize
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        do {
            try prepareDestination(for: response)
            completionHandler(.allow)
        } catch {
            downloadError = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try fileHandle?.write(contentsOf: data)
            completedBytes += Int64(data.count)
            SpeechRuntimeResourceManager.updateDownloadProgress(
                runtime,
                completedBytes: completedBytes,
                expectedBytes: expectedBytes
            )
        } catch {
            downloadError = error
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? fileHandle?.close()
        fileHandle = nil
        session.invalidateAndCancel()

        guard !completionSent else { return }
        completionSent = true

        if let downloadError {
            completion(.failure(downloadError))
        } else if let error {
            completion(.failure(error))
        } else {
            completion(.success(()))
        }
    }

    private func prepareDestination(for response: URLResponse) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: partialURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
        if existingSize > 0, statusCode == 416, !retryingWithoutResume {
            throw NSError(
                domain: "LeafReader.SpeechRuntime.Download",
                code: 416,
                userInfo: [NSLocalizedDescriptionKey: AppText.localized("续传位置已失效，正在重新下载。", "Resume position expired; restarting download.")]
            )
        }

        guard (200...299).contains(statusCode) else {
            throw NSError(
                domain: "LeafReader.SpeechRuntime.Download",
                code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: AppText.localized("模型下载失败：服务器返回 HTTP \(statusCode)。", "Model download failed: server returned HTTP \(statusCode).")]
            )
        }

        if existingSize > 0, statusCode == 206 {
            fileHandle = try FileHandle(forWritingTo: partialURL)
            try fileHandle?.seekToEnd()
            completedBytes = existingSize
            expectedBytes = expectedContentLength(from: response).map { existingSize + $0 }
            return
        }

        try? fileManager.removeItem(at: partialURL)
        fileManager.createFile(atPath: partialURL.path, contents: nil)
        fileHandle = try FileHandle(forWritingTo: partialURL)
        completedBytes = 0
        expectedBytes = expectedContentLength(from: response)
    }

    private func expectedContentLength(from response: URLResponse) -> Int64? {
        let length = response.expectedContentLength
        return length > 0 ? length : nil
    }
}
