import Foundation

enum SpeechRuntimeResourceManager {
    private static let downloadCoordinator = LocalRuntimeDownloadCoordinator<LocalRuntimeDownloadKey>(
        label: "LeafReader.SpeechRuntimeResourceManager.Download"
    )
    private static let installCoordinator = LocalRuntimeInstallCoordinator<LocalRuntimeDownloadKey>(
        label: "LeafReader.SpeechRuntimeResourceManager.Install"
    )
    static let installManifestFileName = ".leafreader-install-manifest.json"
    static let installArchiveTimeout: TimeInterval = 180

    static func isDownloading(_ runtime: Runtime) -> Bool {
        downloadCoordinator.isDownloading(downloadKey(for: runtime))
    }

    static func isPaused(_ runtime: Runtime) -> Bool {
        downloadCoordinator.isPaused(downloadKey(for: runtime))
    }

    static func pause(_ runtime: Runtime) {
        downloadCoordinator.pause(downloadKey(for: runtime))
    }

    static func resume(_ runtime: Runtime) {
        downloadCoordinator.resume(downloadKey(for: runtime))
    }

    static func cancel(_ runtime: Runtime) {
        let completions = stopActiveDownload(for: runtime)
        LocalRuntimeDownloadSupport.removePartialDownload(for: runtime.localRuntimeDownloadPlan)
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
        downloadCoordinator.progress(for: downloadKey(for: runtime))
    }

    static func delete(_ runtime: Runtime) throws {
        _ = stopActiveDownload(for: runtime)
        try ensureNotInstalling(runtime)
        let manifest = installManifest(for: runtime)
        try SpeechRuntimeDeleter.delete(runtime, manifest: manifest)
    }

    private static func stopActiveDownload(for runtime: Runtime) -> [(Result<Void, Error>) -> Void] {
        downloadCoordinator.stop(downloadKey(for: runtime))
    }

    static func download(_ runtime: Runtime, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let downloadID = downloadCoordinator.begin(downloadKey(for: runtime), completion: completion) else { return }
        let plan = runtime.localRuntimeDownloadPlan
        fetchModelManifest(from: plan.manifestURL ?? Runtime.modelManifestURL) { manifestResult in
            guard isCurrentDownload(runtime, downloadID: downloadID) else { return }
            switch manifestResult {
            case .success(let manifest):
                let expectedAsset = manifest?.asset(named: plan.expectedAssetName)
                download(runtime, downloadID: downloadID, plan: plan, expectedAsset: expectedAsset, retryingWithoutResume: false) { result in
                    finishDownload(runtime, downloadID: downloadID, result: result)
                }
            case .failure(let error):
                finishDownload(runtime, downloadID: downloadID, result: .failure(error))
            }
        }
    }

    private static func finishDownload(_ runtime: Runtime, downloadID: UUID, result: Result<Void, Error>) {
        let completions = downloadCoordinator.finish(downloadKey(for: runtime), downloadID: downloadID)
        guard !completions.isEmpty else { return }
        switch result {
        case .success:
            SpeechRuntimeDownloadFailureStore.clear(for: runtime)
            SpeechRuntimeInferenceFailureStore.clear(for: runtime)
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError {
                SpeechRuntimeDownloadFailureStore.record(error, for: runtime)
            }
        }
        DispatchQueue.main.async {
            completions.forEach { $0(result) }
        }
    }

    private static func download(
        _ runtime: Runtime,
        downloadID: UUID,
        plan: LocalRuntimeDownloadPlan,
        expectedAsset: LocalRuntimeDownloadManifestAsset?,
        retryingWithoutResume: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        download(runtime, downloadID: downloadID, plan: plan, expectedAsset: expectedAsset, retryingWithoutResume: retryingWithoutResume, attempt: 1, completion: completion)
    }

    private static func download(
        _ runtime: Runtime,
        downloadID: UUID,
        plan: LocalRuntimeDownloadPlan,
        expectedAsset: LocalRuntimeDownloadManifestAsset?,
        retryingWithoutResume: Bool,
        attempt: Int,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let partialURL = LocalRuntimeDownloadSupport.partialDownloadURL(for: plan)
        let existingSize = retryingWithoutResume
            ? 0
            : LocalRuntimeDownloadSupport.resumablePartialDownloadSize(for: plan, asset: expectedAsset)
        let expectedTotalBytes = LocalRuntimeDownloadSupport.expectedDownloadTotalBytes(asset: expectedAsset)
        var request = URLRequest(url: plan.archiveURL, cachePolicy: .reloadIgnoringLocalCacheData)
        if existingSize > 0 {
            request.setValue("bytes=\(existingSize)-", forHTTPHeaderField: "Range")
            if let metadata = LocalRuntimeDownloadSupport.readPartialDownloadMetadata(for: plan),
               let ifRange = LocalRuntimeDownloadSupport.ifRangeHeaderValue(for: metadata) {
                request.setValue(ifRange, forHTTPHeaderField: "If-Range")
            }
        }

        let downloader = LocalRuntimeDownloader(
            plan: plan,
            downloadID: downloadID,
            partialURL: partialURL,
            existingSize: existingSize,
            retryingWithoutResume: retryingWithoutResume,
            expectedAsset: expectedAsset,
            expectedTotalBytes: expectedTotalBytes,
            progressHandler: { completedBytes, expectedBytes in
                updateDownloadProgress(
                    runtime,
                    downloadID: downloadID,
                    completedBytes: completedBytes,
                    expectedBytes: expectedBytes
                )
            }
        ) { result in
            guard isCurrentDownload(runtime, downloadID: downloadID) else { return }
            do {
                switch result {
                case .success:
                    let installer = localRuntimeInstaller(for: runtime, plan: plan)
                    guard isCurrentDownload(runtime, downloadID: downloadID) else { return }
                    try installer.installDownloadedArchive(partialURL, asset: expectedAsset)
                    LocalRuntimeDownloadSupport.removePartialDownload(for: plan)
                    DispatchQueue.main.async { completion(.success(())) }
                case .failure(let error):
                    recoverDownloadFailure(
                        error,
                        runtime: runtime,
                        downloadID: downloadID,
                        plan: plan,
                        expectedAsset: expectedAsset,
                        attempt: attempt,
                        completion: completion
                    )
                    return
                }
            } catch {
                recoverDownloadFailure(
                    error,
                    runtime: runtime,
                    downloadID: downloadID,
                    plan: plan,
                    expectedAsset: expectedAsset,
                    attempt: attempt,
                    completion: completion
                )
            }
        }

        let session = URLSession(
            configuration: LocalRuntimeDownloadSupport.downloadSessionConfiguration(),
            delegate: downloader,
            delegateQueue: nil
        )
        downloader.session = session
        let task = session.dataTask(with: request)
        downloader.task = task
        let shouldResume = downloadCoordinator.attach(
            key: downloadKey(for: runtime),
            downloadID: downloadID,
            task: task,
            downloader: downloader,
            resumedFromPartial: existingSize > 0
        )
        guard shouldResume else {
            session.invalidateAndCancel()
            return
        }
        task.resume()
    }

    private static func recoverDownloadFailure(
        _ error: Error,
        runtime: Runtime,
        downloadID: UUID,
        plan: LocalRuntimeDownloadPlan,
        expectedAsset: LocalRuntimeDownloadManifestAsset?,
        attempt: Int,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        switch LocalRuntimeDownloadSupport.downloadRecoveryAction(error: error as NSError, attempt: attempt) {
        case .retry(let resumePartial):
            if !resumePartial {
                LocalRuntimeDownloadSupport.removePartialDownload(for: plan)
            }
            download(
                runtime,
                downloadID: downloadID,
                plan: plan,
                expectedAsset: expectedAsset,
                retryingWithoutResume: !resumePartial,
                attempt: attempt + 1,
                completion: completion
            )
        case .fail(let removePartial):
            if removePartial {
                LocalRuntimeDownloadSupport.removePartialDownload(for: plan)
            }
            DispatchQueue.main.async { completion(.failure(error)) }
        }
    }

    private static func isCurrentDownload(_ runtime: Runtime, downloadID: UUID) -> Bool {
        downloadCoordinator.isCurrent(downloadKey(for: runtime), downloadID: downloadID)
    }

    static func updateDownloadProgress(_ runtime: Runtime, downloadID: UUID, completedBytes: Int64, expectedBytes: Int64?) {
        downloadCoordinator.updateProgress(
            key: downloadKey(for: runtime),
            downloadID: downloadID,
            completedBytes: completedBytes,
            expectedBytes: expectedBytes
        )
    }

    private static func localRuntimeInstaller(for runtime: Runtime, plan: LocalRuntimeDownloadPlan) -> LocalRuntimeInstaller {
        LocalRuntimeInstaller(plan: plan) { archiveURL in
            try installArchiveIfIdle(archiveURL, for: runtime)
        }
    }

    private static func downloadKey(for runtime: Runtime) -> LocalRuntimeDownloadKey {
        LocalRuntimeDownloadKey(descriptor: runtime.localRuntimeDescriptor)
    }

    private static func installArchiveIfIdle(_ archiveURL: URL, for runtime: Runtime) throws {
        try installCoordinator.perform(downloadKey(for: runtime), makeError: installInProgressError) {
            try installArchive(archiveURL, for: runtime)
        }
    }

    private static func ensureNotInstalling(_ runtime: Runtime) throws {
        try installCoordinator.ensureNotInstalling(downloadKey(for: runtime), makeError: installInProgressError)
    }

    private static func installInProgressError() -> NSError {
        NSError(
            domain: "LeafReader.SpeechRuntime",
            code: -5,
            userInfo: [NSLocalizedDescriptionKey: AppText.localized("模型正在安装中，请稍后。", "Speech runtime installation is already in progress.")]
        )
    }

}
