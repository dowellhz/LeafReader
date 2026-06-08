import Foundation

enum SpeechRuntimeDownloadTests {
    static func testSpeechRuntimeDownloadURLsUseReleaseAssets() throws {
        let kokoroURL = SpeechRuntimeResourceManager.Runtime.kokoro.downloadURL.absoluteString
        let piperURL = SpeechRuntimeResourceManager.Runtime.piper.downloadURL.absoluteString
        let supertonicURL = SpeechRuntimeResourceManager.Runtime.supertonic.downloadURL.absoluteString

        try expect(kokoroURL.hasSuffix("/kokoro-coreml-macos-arm64.tar.gz"), "Kokoro should use the release asset archive")
        try expect(piperURL.hasSuffix("/piper-tts-macos-arm64.tar.gz"), "Piper should use the release asset archive")
        try expectEqual(supertonicURL, expectedSpeechReleaseAssetURL(fileName: "supertonic-coreml-macos-arm64.tar.gz"), "Supertonic should download the Release-hosted CoreML model archive")
        try expect(kokoroURL.contains("/download/\(SpeechRuntimeResourceManager.Runtime.runtimeAssetsReleaseTag)/"), "Kokoro should use the stable speech runtime asset release")
        try expect(piperURL.contains("/download/\(SpeechRuntimeResourceManager.Runtime.runtimeAssetsReleaseTag)/"), "Piper should use the stable speech runtime asset release")
        try expect(SpeechRuntimeResourceManager.Runtime.modelManifestURL.absoluteString.contains("/download/\(SpeechRuntimeResourceManager.Runtime.runtimeAssetsReleaseTag)/"), "Default speech model manifest should use the stable release asset")
        try expect(SpeechRuntimeResourceManager.Runtime.modelManifestURL.absoluteString.hasSuffix("/speech-models-manifest.json"), "Default speech model manifest should use the release asset manifest")
    }

    static func testSpeechRuntimeLocalRuntimeDescriptors() throws {
        let descriptors = SpeechRuntimeResourceManager.Runtime.localRuntimeDescriptors
        try expectEqual(descriptors.map(\.id), ["piper", "supertonic", "kokoro"], "speech runtime descriptors should preserve display order")

        let piper = SpeechRuntimeResourceManager.Runtime.piper
        let descriptor = piper.localRuntimeDescriptor
        try expectEqual(descriptor.family, .speech, "speech runtime descriptor should identify the runtime family")
        try expectEqual(descriptor.id, piper.id, "descriptor should expose runtime id")
        try expectEqual(descriptor.title, piper.title, "descriptor should expose runtime title")
        try expectEqual(descriptor.downloadURL, piper.downloadURL, "descriptor should expose runtime download URL")
        try expectEqual(descriptor.manifestURL, SpeechRuntimeResourceManager.Runtime.modelManifestURL, "descriptor should expose the speech model manifest URL")
        try expectEqual(descriptor.installDirectory, piper.installDirectory, "descriptor should expose the user install directory")
        try expectEqual(descriptor.executableURL, piper.userExecutableURL, "descriptor should expose the user executable URL")
        try expectEqual(descriptor.modelDirectory, piper.modelDirectory(in: piper.installDirectory), "descriptor should expose the model directory")
        try expectEqual(descriptor.requiredPaths, piper.requiredPaths, "descriptor should expose required install paths")
        try expect(descriptor.installDirectories.contains(piper.installDirectory), "descriptor should include the user install directory among candidate directories")
    }

    static func testSpeechRuntimeLocalRuntimeDownloadPlans() throws {
        let plans = SpeechRuntimeResourceManager.Runtime.localRuntimeDownloadPlans
        try expectEqual(plans.map(\.descriptor.id), ["piper", "supertonic", "kokoro"], "speech runtime download plans should preserve display order")

        let piper = SpeechRuntimeResourceManager.Runtime.piper
        let plan = piper.localRuntimeDownloadPlan
        try expectEqual(plan.descriptor.id, piper.id, "download plan should carry the runtime descriptor")
        try expectEqual(plan.archiveURL, piper.downloadURL, "download plan should expose archive URL")
        try expectEqual(plan.manifestURL, SpeechRuntimeResourceManager.Runtime.modelManifestURL, "download plan should expose manifest URL")
        try expectEqual(plan.expectedAssetName, "piper-tts-macos-arm64.tar.gz", "download plan should expose expected release asset name")

        let supertonic = SpeechRuntimeResourceManager.Runtime.supertonic
        let supertonicPlan = supertonic.localRuntimeDownloadPlan
        try expectEqual(supertonicPlan.archiveURL.absoluteString, expectedSpeechReleaseAssetURL(fileName: "supertonic-coreml-macos-arm64.tar.gz"), "Supertonic should download from GitHub Release assets")
        try expectEqual(supertonicPlan.manifestURL?.absoluteString, expectedSpeechReleaseAssetURL(fileName: "speech-models-manifest.json"), "Supertonic should validate against the Release-hosted manifest")
        try expectEqual(supertonicPlan.expectedAssetName, "supertonic-coreml-macos-arm64.tar.gz", "Supertonic download plan should expose expected archive name")
    }

    static func testSpeechRuntimeLocalRuntimeRegistry() throws {
        let registry = SpeechRuntimeResourceManager.Runtime.localRuntimeRegistry
        try expectEqual(
            registry.descriptors.map(\.id),
            ["piper", "supertonic", "kokoro"],
            "speech runtime registry should preserve descriptor display order"
        )

        let piperDescriptor = registry.descriptor(family: .speech, id: "piper")
        try expectEqual(
            piperDescriptor?.downloadURL,
            SpeechRuntimeResourceManager.Runtime.piper.downloadURL,
            "registry should find descriptors by family and id"
        )

        let piperPlan = registry.downloadPlan(family: .speech, id: "piper")
        try expectEqual(
            piperPlan?.expectedAssetName,
            "piper-tts-macos-arm64.tar.gz",
            "registry should find download plans by family and id"
        )
        try expectEqual(
            registry.downloadPlan(family: .localLLM, id: "piper")?.expectedAssetName,
            nil,
            "registry lookups should not cross runtime families"
        )
    }

    static func testLocalRuntimeDownloadManifestAssetDecoding() throws {
        let releaseAssetData = Data(
            #"{"name":"mini.tar.gz","size":123,"sha256":"abc"}"#.utf8
        )
        let releaseAsset = try JSONDecoder().decode(
            LocalRuntimeDownloadManifestAsset.self,
            from: releaseAssetData
        )
        try expectEqual(
            releaseAsset.assetName,
            "mini.tar.gz",
            "release manifest assets should decode name as the generic asset name"
        )
        try expectEqual(
            releaseAsset.byteSize,
            123,
            "release manifest assets should decode size as the generic byte size"
        )

        let genericAssetData = Data(
            #"{"assetName":"mini.tar.gz","byteSize":456,"sha256":"def"}"#.utf8
        )
        let genericAsset = try JSONDecoder().decode(
            LocalRuntimeDownloadManifestAsset.self,
            from: genericAssetData
        )
        try expectEqual(
            genericAsset.name,
            "mini.tar.gz",
            "generic manifest assets should preserve the legacy name accessor"
        )
        try expectEqual(
            genericAsset.size,
            456,
            "generic manifest assets should preserve the legacy size accessor"
        )
    }

    static func testSpeechRuntimeResumeContentRangeValidation() throws {
        try expectEqual(
            LocalRuntimeDownloadSupport.contentRangeStart("bytes 1024-2047/4096"),
            1024,
            "resume validation should parse the Content-Range start byte"
        )
        try expectEqual(
            LocalRuntimeDownloadSupport.contentRangeStart(" bytes 0-99/100 "),
            0,
            "resume validation should tolerate Content-Range whitespace"
        )
        try expectEqual(
            LocalRuntimeDownloadSupport.contentRangeStart("bytes 1024-2047/*"),
            1024,
            "resume validation should allow unknown total sizes"
        )
        try expect(
            LocalRuntimeDownloadSupport.contentRangeStart("bytes */4096") == nil,
            "unsatisfied Content-Range responses should not look resumable"
        )
        try expect(
            LocalRuntimeDownloadSupport.contentRangeStart("items 1024-2047/4096") == nil,
            "non-byte Content-Range responses should be rejected"
        )
    }

    static func testSpeechRuntimePartialRestartPolicy() throws {
        let resumeExpired = NSError(domain: LocalRuntimeDownloadSupport.downloadErrorDomain, code: 416)
        let resumeMismatch = NSError(domain: LocalRuntimeDownloadSupport.downloadErrorDomain, code: LocalRuntimeDownloadSupport.resumeRangeMismatchCode)
        let checksumMismatch = NSError(domain: LocalRuntimeDownloadSupport.downloadErrorDomain, code: -7)
        let networkFailure = NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)

        try expect(
            LocalRuntimeDownloadSupport.shouldRetryDownload(error: resumeMismatch, attempt: 1),
            "mismatched resume responses should retry from a clean download"
        )
        try expect(
            LocalRuntimeDownloadSupport.shouldRetryDownload(error: checksumMismatch, attempt: 1),
            "checksum failures should retry once the corrupt partial archive is discarded"
        )
        try expect(
            !LocalRuntimeDownloadSupport.shouldRetryDownload(error: checksumMismatch, attempt: 4),
            "checksum failures should stop retrying at the download attempt limit"
        )
        try expect(
            LocalRuntimeDownloadSupport.shouldRestartWithoutPartialDownload(error: resumeExpired),
            "expired resume ranges should discard the partial archive"
        )
        try expect(
            LocalRuntimeDownloadSupport.shouldRestartWithoutPartialDownload(error: resumeMismatch),
            "mismatched resume ranges should discard the partial archive"
        )
        try expect(
            LocalRuntimeDownloadSupport.shouldRestartWithoutPartialDownload(error: checksumMismatch),
            "checksum failures should discard the corrupt partial archive"
        )
        try expect(
            !LocalRuntimeDownloadSupport.shouldRestartWithoutPartialDownload(error: networkFailure),
            "transient network failures should keep the partial archive for resume"
        )
        try expectEqual(
            LocalRuntimeDownloadSupport.downloadRecoveryAction(error: checksumMismatch, attempt: 1),
            .retry(resumePartial: false),
            "checksum failures should restart from a clean archive while retry attempts remain"
        )
        try expectEqual(
            LocalRuntimeDownloadSupport.downloadRecoveryAction(error: checksumMismatch, attempt: 4),
            .fail(removePartial: true),
            "checksum failures should remove corrupt archives before surfacing the final error"
        )
        try expectEqual(
            LocalRuntimeDownloadSupport.downloadRecoveryAction(error: networkFailure, attempt: 1),
            .retry(resumePartial: true),
            "transient network failures should retry with the partial archive"
        )
    }

    static func testSpeechRuntimePartialMetadataValidationAndIfRange() throws {
        let asset = SpeechModelManifest.Asset(
            name: "piper-tts-macos-arm64.tar.gz",
            size: 105541145,
            sha256: "b752a7e93456c9b9eab397960976667153bee8c999ab497685fddb82562458b5"
        )
        let metadata = LocalRuntimeDownloadSupport.PartialDownloadMetadata(
            downloadURL: SpeechRuntimeResourceManager.Runtime.piper.downloadURL.absoluteString,
            assetName: asset.name,
            expectedSize: asset.size,
            sha256: asset.sha256,
            eTag: " \"abc\" ",
            lastModified: "Wed, 24 May 2026 00:00:00 GMT"
        )
        try expect(
            LocalRuntimeDownloadSupport.partialDownloadMetadataMatches(
                metadata,
                plan: SpeechRuntimeResourceManager.Runtime.piper.localRuntimeDownloadPlan,
                asset: asset
            ),
            "partial metadata should match the same URL and manifest asset"
        )
        try expect(
            LocalRuntimeDownloadSupport.partialDownloadMetadataMatches(
                metadata,
                plan: SpeechRuntimeResourceManager.Runtime.piper.localRuntimeDownloadPlan,
                asset: asset
            ),
            "partial metadata should also match through the generic local runtime download plan"
        )
        try expectEqual(
            LocalRuntimeDownloadSupport.ifRangeHeaderValue(for: metadata),
            "\"abc\"",
            "If-Range should prefer a trimmed ETag"
        )

        let changedAsset = SpeechModelManifest.Asset(
            name: asset.name,
            size: asset.size,
            sha256: String(repeating: "0", count: 64)
        )
        try expect(
            !LocalRuntimeDownloadSupport.partialDownloadMetadataMatches(
                metadata,
                plan: SpeechRuntimeResourceManager.Runtime.piper.localRuntimeDownloadPlan,
                asset: changedAsset
            ),
            "partial metadata should reject changed asset checksums"
        )

        let lastModifiedOnly = LocalRuntimeDownloadSupport.PartialDownloadMetadata(
            downloadURL: metadata.downloadURL,
            assetName: metadata.assetName,
            expectedSize: metadata.expectedSize,
            sha256: metadata.sha256,
            eTag: " ",
            lastModified: "Wed, 24 May 2026 00:00:00 GMT"
        )
        try expectEqual(
            LocalRuntimeDownloadSupport.ifRangeHeaderValue(for: lastModifiedOnly),
            "Wed, 24 May 2026 00:00:00 GMT",
            "If-Range should fall back to Last-Modified when ETag is missing"
        )
    }

    static func testSpeechRuntimeDownloadConfigurationAndProgressTotals() throws {
        let configuration = LocalRuntimeDownloadSupport.downloadSessionConfiguration()
        try expectEqual(
            configuration.timeoutIntervalForRequest,
            30,
            "speech model downloads should have a bounded per-request timeout"
        )
        try expectEqual(
            configuration.timeoutIntervalForResource,
            60 * 60,
            "speech model downloads should allow large archives enough total download time"
        )
        try expect(
            configuration.waitsForConnectivity,
            "speech model downloads should wait for connectivity on transient offline states"
        )

        let asset = SpeechModelManifest.Asset(
            name: "piper-tts-macos-arm64.tar.gz",
            size: 105541145,
            sha256: "b752a7e93456c9b9eab397960976667153bee8c999ab497685fddb82562458b5"
        )
        try expectEqual(
            LocalRuntimeDownloadSupport.expectedDownloadTotalBytes(asset: asset),
            105541145,
            "progress should use manifest size when available"
        )
        try expectEqual(
            LocalRuntimeDownloadSupport.expectedDownloadTotalBytes(asset: nil),
            nil,
            "progress should fall back to response length without manifest size"
        )
    }

    static func testSpeechRuntimeInstallDiskSpacePolicy() throws {
        let required = LocalRuntimeDownloadSupport.requiredInstallFreeSpaceBytes(archiveSize: 100)
        try expectEqual(
            required,
            200 * 1024 * 1024 + 300,
            "install disk-space policy should reserve room for archive, extraction, and a safety margin"
        )
        try expect(
            LocalRuntimeDownloadSupport.hasEnoughFreeSpace(availableBytes: required, requiredBytes: required),
            "exactly enough free space should be accepted"
        )
        try expect(
            !LocalRuntimeDownloadSupport.hasEnoughFreeSpace(availableBytes: required - 1, requiredBytes: required),
            "insufficient free space should be rejected before install"
        )
        try expect(
            LocalRuntimeDownloadSupport.hasEnoughFreeSpace(availableBytes: nil, requiredBytes: required),
            "unknown free space should not block installation"
        )
    }

    static func testPiperArchiveValidationRequiresPackagedVoice() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("leafreader-piper-archive-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let executable = root.appendingPathComponent("piper/piper")
        try fileManager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: executable)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        do {
            try SpeechRuntimeResourceManager.validateExtractedRuntime(.piper, in: root)
            throw TestFailure(description: "Piper archive validation should reject archives without a packaged voice")
        } catch let error as NSError {
            try expectEqual(error.domain, "LeafReader.SpeechRuntime", "Piper archive validation should use the speech runtime domain")
            try expectEqual(error.code, -4, "Piper archive validation should report missing required files")
        }

        let voiceDirectory = root.appendingPathComponent("Voices", isDirectory: true)
        try fileManager.createDirectory(at: voiceDirectory, withIntermediateDirectories: true)
        try Data().write(to: voiceDirectory.appendingPathComponent("en_US-ryan-medium.onnx"))
        try Data("{}".utf8).write(to: voiceDirectory.appendingPathComponent("en_US-ryan-medium.onnx.json"))

        try SpeechRuntimeResourceManager.validateExtractedRuntime(.piper, in: root)
    }

    static func testSpeechRuntimeInstallManifestFiltersExternalCachePaths() throws {
        let cacheRoot = SpeechRuntimeResourceManager.Runtime.fluidAudioModelCacheRoot
        let validCacheDirectory = cacheRoot.appendingPathComponent("kokoro", isDirectory: true)
        let piperCacheRoot = SpeechRuntimeResourceManager.Runtime.piperVoiceCacheRoot
        let validPiperCacheDirectory = piperCacheRoot.appendingPathComponent("en", isDirectory: true)
        let externalDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("leafreader-external-cache-\(UUID().uuidString)", isDirectory: true)
        let manifest = SpeechRuntimeResourceManager.InstallManifest(
            runtimeID: SpeechRuntimeResourceManager.Runtime.kokoro.id,
            cacheDirectoryPaths: [
                validCacheDirectory.path,
                cacheRoot.path,
                validPiperCacheDirectory.path,
                piperCacheRoot.path,
                externalDirectory.path
            ]
        )

        try expectEqual(
            manifest.cacheDirectories,
            [validCacheDirectory, validPiperCacheDirectory],
            "install manifests should only expose child directories inside known speech model caches"
        )
    }

    static func testLocalRuntimeInstallManifestCompatibility() throws {
        let legacyData = Data(
            #"{"runtimeID":"piper","cacheDirectoryPaths":["/tmp/leafreader-voice"]}"#.utf8
        )
        let legacyManifest = try JSONDecoder().decode(LocalRuntimeInstallManifest.self, from: legacyData)

        try expectEqual(
            legacyManifest.family,
            .speech,
            "legacy speech install manifests should default to the speech runtime family"
        )
        try expectEqual(
            legacyManifest.runtimeID,
            "piper",
            "legacy speech install manifests should preserve the runtime ID"
        )
        try expectEqual(
            legacyManifest.cacheDirectoryPaths,
            ["/tmp/leafreader-voice"],
            "legacy speech install manifests should preserve cache paths"
        )

        let llmManifest = LocalRuntimeInstallManifest(
            family: .localLLM,
            runtimeID: "minicpm",
            cacheDirectoryPaths: []
        )
        let roundTripManifest = try JSONDecoder().decode(
            LocalRuntimeInstallManifest.self,
            from: JSONEncoder().encode(llmManifest)
        )

        try expectEqual(
            roundTripManifest,
            llmManifest,
            "new local runtime install manifests should round-trip their runtime family"
        )
    }

    static func testKokoroCacheInstallTransactionRollbackAndCommit() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("leafreader-kokoro-cache-transaction-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let existing = root.appendingPathComponent("existing", isDirectory: true)
        let existingMarker = existing.appendingPathComponent("marker.txt")
        let replacement = root.appendingPathComponent("replacement", isDirectory: true)
        let replacementMarker = replacement.appendingPathComponent("marker.txt")
        let backup = root.appendingPathComponent("backup", isDirectory: true)
        try fileManager.createDirectory(at: existing, withIntermediateDirectories: true)
        try "old".write(to: existingMarker, atomically: true, encoding: .utf8)
        try fileManager.createDirectory(at: replacement, withIntermediateDirectories: true)
        try "new".write(to: replacementMarker, atomically: true, encoding: .utf8)

        var rollbackTransaction = KokoroCacheInstallTransaction(fileManager: fileManager)
        try rollbackTransaction.replace(source: replacement, destination: existing, backup: backup)
        rollbackTransaction.rollback()
        try expectEqual(
            try String(contentsOf: existingMarker, encoding: .utf8),
            "old",
            "rollback should restore the previous cache directory"
        )
        try expect(!fileManager.fileExists(atPath: backup.path), "rollback should remove the cache backup")

        let committedReplacement = root.appendingPathComponent("committed-replacement", isDirectory: true)
        let committedMarker = committedReplacement.appendingPathComponent("marker.txt")
        let committedBackup = root.appendingPathComponent("committed-backup", isDirectory: true)
        try fileManager.createDirectory(at: committedReplacement, withIntermediateDirectories: true)
        try "committed".write(to: committedMarker, atomically: true, encoding: .utf8)

        var commitTransaction = KokoroCacheInstallTransaction(fileManager: fileManager)
        try commitTransaction.replace(source: committedReplacement, destination: existing, backup: committedBackup)
        commitTransaction.commit()
        try expectEqual(
            try String(contentsOf: existingMarker, encoding: .utf8),
            "committed",
            "commit should keep the replacement cache directory"
        )
        try expect(!fileManager.fileExists(atPath: committedBackup.path), "commit should remove the cache backup")
        try expectEqual(
            commitTransaction.installedDirectories,
            [existing],
            "commit should keep installed directory records for manifest writing"
        )
    }
}
