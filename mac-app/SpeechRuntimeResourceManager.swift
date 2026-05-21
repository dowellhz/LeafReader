import Foundation

enum SpeechRuntimeResourceManager {
    private static let stateQueue = DispatchQueue(label: "LeafReader.SpeechRuntimeResourceManager")
    private static var activeDownloads: [Runtime: [(Result<Void, Error>) -> Void]] = [:]
    private static var activeTasks: [Runtime: URLSessionDownloadTask] = [:]
    private static var pausedDownloads = Set<Runtime>()

    enum Runtime: CaseIterable {
        case kokoro
        case kitten

        static let defaultRuntime: Runtime = .kokoro

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
            allCases.first { $0.id == id }
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

        var requiredPaths: [URL] {
            switch self {
            case .kokoro:
                return [
                    installDirectory.appendingPathComponent("fluidaudiocli"),
                    Self.fluidAudioModelCacheRoot.appendingPathComponent("kokoro", isDirectory: true)
                ]
            case .kitten:
                return [
                    installDirectory.appendingPathComponent("kitten-tts-aarch64-macos/kitten-tts"),
                    installDirectory.appendingPathComponent("kitten-tts-aarch64-macos/kitten-tts-server"),
                    installDirectory.appendingPathComponent("kitten-tts-mini", isDirectory: true)
                ]
            }
        }

        var canDownloadInApp: Bool {
            true
        }

        var isUsableForReadAloud: Bool {
            true
        }

        static var fluidAudioModelCacheRoot: URL {
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".cache/fluidaudio/Models", isDirectory: true)
        }
    }

    static func isInstalled(_ runtime: Runtime) -> Bool {
        runtime.requiredPaths.allSatisfy { path in
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory)
            if path.hasDirectoryPath {
                return exists && isDirectory.boolValue
            }
            return FileManager.default.isExecutableFile(atPath: path.path)
        }
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
        let completions = stateQueue.sync {
            let completions = activeDownloads[runtime] ?? []
            let task = activeTasks[runtime]
            clearActiveDownloadState(for: runtime)
            task?.cancel()
            return completions
        }
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
                return nil
            }
            return progress
        }
    }

    static func delete(_ runtime: Runtime) throws {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: partialDownloadURL(for: runtime))
        try? fileManager.removeItem(at: runtime.installDirectory)
        if runtime == .kokoro {
            try? fileManager.removeItem(at: Runtime.fluidAudioModelCacheRoot.appendingPathComponent("kokoro", isDirectory: true))
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
        pausedDownloads.remove(runtime)
    }

    private static func download(_ runtime: Runtime, retryingWithoutResume: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        let fileManager = FileManager.default
        let partialURL = partialDownloadURL(for: runtime)
        let existingSize = retryingWithoutResume ? 0 : partialDownloadSize(at: partialURL)
        var request = URLRequest(url: runtime.downloadURL, cachePolicy: .reloadIgnoringLocalCacheData)
        if existingSize > 0 {
            request.setValue("bytes=\(existingSize)-", forHTTPHeaderField: "Range")
        }
        let task = URLSession.shared.downloadTask(with: request) { temporaryURL, response, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let temporaryURL else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(
                        domain: "LeafReader.SpeechRuntime",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Downloaded file is missing."]
                    )))
                }
                return
            }
            do {
                try fileManager.createDirectory(at: partialURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
                if existingSize > 0, statusCode == 206 {
                    try appendFile(at: temporaryURL, to: partialURL)
                } else if existingSize > 0, statusCode == 416, !retryingWithoutResume {
                    try? fileManager.removeItem(at: partialURL)
                    download(runtime, retryingWithoutResume: true, completion: completion)
                    return
                } else {
                    try? fileManager.removeItem(at: partialURL)
                    try fileManager.moveItem(at: temporaryURL, to: partialURL)
                }

                try installArchive(partialURL, for: runtime)
                try? fileManager.removeItem(at: partialURL)
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        stateQueue.sync {
            activeTasks[runtime] = task
        }
        task.resume()
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

    private static func appendFile(at sourceURL: URL, to destinationURL: URL) throws {
        let readHandle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? readHandle.close() }
        let writeHandle = try FileHandle(forWritingTo: destinationURL)
        defer { try? writeHandle.close() }
        try writeHandle.seekToEnd()
        while autoreleasepool(invoking: {
            let data = readHandle.readData(ofLength: 1024 * 1024)
            if data.isEmpty { return false }
            writeHandle.write(data)
            return true
        }) {}
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
