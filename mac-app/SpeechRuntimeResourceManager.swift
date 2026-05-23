import Foundation

enum SpeechRuntimeResourceManager {
    private static let stateQueue = DispatchQueue(label: "LeafReader.SpeechRuntimeResourceManager")
    private static var activeDownloads: [Runtime: [(Result<Void, Error>) -> Void]] = [:]
    private static var activeDownloadIDs: [Runtime: UUID] = [:]
    private static var activeTasks: [Runtime: URLSessionTask] = [:]
    private static var activeDownloaders: [Runtime: RuntimeDownload] = [:]
    private static var activeProgress: [Runtime: Double] = [:]
    private static var activeInstalls = Set<Runtime>()
    private static var pausedDownloads = Set<Runtime>()
    static let installManifestFileName = ".leafreader-install-manifest.json"
    static let installArchiveTimeout: TimeInterval = 180

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
        SpeechRuntimeDownloadFailureStore.clear(for: runtime)
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
        try ensureNotInstalling(runtime)
        let manifest = installManifest(for: runtime)
        try removeItemIfExists(at: partialDownloadURL(for: runtime))
        try removeItemIfExists(at: runtime.installDirectory)
        SpeechRuntimeDownloadFailureStore.clear(for: runtime)
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
        fetchModelManifest { manifestResult in
            guard isCurrentDownload(runtime, downloadID: downloadID) else { return }
            switch manifestResult {
            case .success(let manifest):
                let expectedAsset = manifest?.asset(named: runtime.downloadURL.lastPathComponent)
                download(runtime, downloadID: downloadID, expectedAsset: expectedAsset, retryingWithoutResume: false) { result in
                    finishDownload(runtime, downloadID: downloadID, result: result)
                }
            case .failure(let error):
                finishDownload(runtime, downloadID: downloadID, result: .failure(error))
            }
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
            SpeechRuntimeDownloadFailureStore.clear(for: runtime)
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError {
                SpeechRuntimeDownloadFailureStore.record(error, for: runtime)
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
        expectedAsset: SpeechModelManifest.Asset?,
        retryingWithoutResume: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        download(runtime, downloadID: downloadID, expectedAsset: expectedAsset, retryingWithoutResume: retryingWithoutResume, attempt: 1, completion: completion)
    }

    private static func download(
        _ runtime: Runtime,
        downloadID: UUID,
        expectedAsset: SpeechModelManifest.Asset?,
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
                    try validateArchiveManifest(partialURL, asset: expectedAsset)
                    guard isCurrentDownload(runtime, downloadID: downloadID) else { return }
                    try installArchiveIfIdle(partialURL, for: runtime)
                    try? fileManager.removeItem(at: partialURL)
                    DispatchQueue.main.async { completion(.success(())) }
                case .failure(let error):
                    let nsError = error as NSError
                    if shouldRetryDownload(error: nsError, attempt: attempt) {
                        if nsError.domain == downloadErrorDomain, nsError.code == 416 {
                            try? fileManager.removeItem(at: partialURL)
                            download(runtime, downloadID: downloadID, expectedAsset: expectedAsset, retryingWithoutResume: true, attempt: attempt + 1, completion: completion)
                        } else {
                            download(runtime, downloadID: downloadID, expectedAsset: expectedAsset, retryingWithoutResume: false, attempt: attempt + 1, completion: completion)
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

    static func updateDownloadProgress(_ runtime: Runtime, downloadID: UUID, completedBytes: Int64, expectedBytes: Int64?) {
        guard let expectedBytes, expectedBytes > 0 else { return }
        stateQueue.sync {
            guard activeDownloadIDs[runtime] == downloadID else { return }
            activeProgress[runtime] = min(1, max(0, Double(completedBytes) / Double(expectedBytes)))
        }
    }

    private static func installArchiveIfIdle(_ archiveURL: URL, for runtime: Runtime) throws {
        try beginInstall(runtime)
        defer { finishInstall(runtime) }
        try installArchive(archiveURL, for: runtime)
    }

    private static func ensureNotInstalling(_ runtime: Runtime) throws {
        let isInstalling = stateQueue.sync {
            activeInstalls.contains(runtime)
        }
        guard !isInstalling else {
            throw installInProgressError()
        }
    }

    private static func beginInstall(_ runtime: Runtime) throws {
        let didStart = stateQueue.sync {
            guard !activeInstalls.contains(runtime) else { return false }
            activeInstalls.insert(runtime)
            return true
        }
        guard didStart else {
            throw installInProgressError()
        }
    }

    private static func finishInstall(_ runtime: Runtime) {
        stateQueue.sync {
            _ = activeInstalls.remove(runtime)
        }
    }

    private static func installInProgressError() -> NSError {
        NSError(
            domain: "LeafReader.SpeechRuntime",
            code: -5,
            userInfo: [NSLocalizedDescriptionKey: AppText.localized("模型正在安装中，请稍后。", "Speech runtime installation is already in progress.")]
        )
    }

}
