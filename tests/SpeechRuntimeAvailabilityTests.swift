import Foundation

enum SpeechRuntimeAvailabilityTests {
    static func testSpeechRuntimeAvailabilityText() throws {
        try expectEqual(
            SpeechRuntimeResourceManager.availabilityText(isSupported: true, downloaded: true, minimumSystemVersionText: "macOS 14.0"),
            nil,
            "available runtimes should not show an unavailable reason"
        )
        try expectEqual(
            SpeechRuntimeResourceManager.availabilityText(isSupported: false, downloaded: true, minimumSystemVersionText: "macOS 14.0"),
            AppText.localized("需要 macOS 14.0", "Requires macOS 14.0"),
            "unsupported downloaded runtimes should show the macOS requirement"
        )
        try expectEqual(
            SpeechRuntimeResourceManager.availabilityText(isSupported: true, downloaded: false, minimumSystemVersionText: "macOS 12.0"),
            AppText.localized("未下载", "Not downloaded"),
            "missing runtimes should show that the model is not downloaded"
        )
    }

    static func testLocalRuntimeStatusPresenter() throws {
        let descriptor = SpeechRuntimeResourceManager.Runtime.piper.localRuntimeDescriptor
        let downloading = LocalRuntimeStatusContext(
            descriptor: descriptor,
            installState: .missingRuntimeAndModel,
            isSupported: true,
            isDownloading: true,
            isPaused: false,
            downloadFailureMessage: nil,
            inferenceFailureText: nil
        )
        try expectEqual(
            LocalRuntimeStatusPresenter.statusText(downloading),
            "下载中 · 约 112 MB",
            "generic local runtime presenter should format active downloads"
        )

        let missingRuntime = LocalRuntimeStatusContext(
            descriptor: descriptor,
            installState: .missingRuntime,
            isSupported: true,
            isDownloading: false,
            isPaused: false,
            downloadFailureMessage: nil,
            inferenceFailureText: nil
        )
        try expectEqual(
            LocalRuntimeStatusPresenter.statusText(missingRuntime),
            "缺少运行时 · 模型已安装 · 约 112 MB",
            "generic local runtime presenter should distinguish missing runtime from missing model"
        )

        let unsupportedFailure = LocalRuntimeStatusContext(
            descriptor: descriptor,
            installState: .missingRuntimeAndModel,
            isSupported: false,
            isDownloading: false,
            isPaused: false,
            downloadFailureMessage: "network failed",
            inferenceFailureText: nil
        )
        try expect(
            LocalRuntimeStatusPresenter.statusText(unsupportedFailure).contains("上次失败：network failed"),
            "generic local runtime presenter should include download failure details"
        )
    }

    static func testPiperRuntimeRequiresPhonemizeResources() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("leafreader-piper-runtime-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let executable = root.appendingPathComponent("piper/piper")
        try fileManager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: executable)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        try expect(
            !SpeechRuntimePathChecks.piperRuntimePathsExist(in: root),
            "Piper runtime should not be runnable without phonemize libraries and espeak data"
        )

        try fileManager.createDirectory(
            at: root.appendingPathComponent("piper-phonemize/lib", isDirectory: true),
            withIntermediateDirectories: true
        )
        try expect(
            !SpeechRuntimePathChecks.piperRuntimePathsExist(in: root),
            "Piper runtime should not be runnable without espeak data"
        )

        try fileManager.createDirectory(
            at: root.appendingPathComponent("piper-phonemize/share/espeak-ng-data", isDirectory: true),
            withIntermediateDirectories: true
        )
        try expect(
            SpeechRuntimePathChecks.piperRuntimePathsExist(in: root),
            "Piper runtime should be runnable when executable, phonemize libraries, and espeak data are present"
        )
    }

    static func testPiperAnyVoiceAcceptsNonDefaultVoice() throws {
        let fileManager = FileManager.default
        let voiceDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("leafreader-piper-voices-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: voiceDirectory) }

        try fileManager.createDirectory(at: voiceDirectory, withIntermediateDirectories: true)
        try Data().write(to: voiceDirectory.appendingPathComponent("en_US-ryan-medium.onnx"))
        try Data("{}".utf8).write(to: voiceDirectory.appendingPathComponent("en_US-ryan-medium.onnx.json"))

        try expect(
            SpeechRuntimePathChecks.piperAnyVoicePathsExist(in: voiceDirectory),
            "Piper should be available when any complete voice model and config pair exists"
        )
        try expect(
            !SpeechRuntimePathChecks.piperVoicePathsExist(in: voiceDirectory),
            "default Piper voice checks should remain voice-specific"
        )
    }

    static func testPiperModelDownloadMakesBundledRuntimeAvailable() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("leafreader-piper-availability-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let runtimeDirectory = root.appendingPathComponent("piper-tts-runtime", isDirectory: true)
        let voiceDirectory = root.appendingPathComponent("piper-voices", isDirectory: true)
        let executable = runtimeDirectory.appendingPathComponent("piper/piper")
        try fileManager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: runtimeDirectory.appendingPathComponent("piper-phonemize/lib", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: runtimeDirectory.appendingPathComponent("piper-phonemize/share/espeak-ng-data", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data().write(to: executable)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        try expect(
            !SpeechRuntimeAvailability.piperRuntimeAndVoicePathsExist(
                installDirectories: [runtimeDirectory],
                voiceDirectory: voiceDirectory
            ),
            "Piper should remain unavailable after runtime install until a voice model is downloaded"
        )

        try fileManager.createDirectory(at: voiceDirectory, withIntermediateDirectories: true)
        try Data().write(to: voiceDirectory.appendingPathComponent("en_US-lessac-high.onnx"))
        try Data("{}".utf8).write(to: voiceDirectory.appendingPathComponent("en_US-lessac-high.onnx.json"))
        try expect(
            SpeechRuntimeAvailability.piperRuntimeAndVoicePathsExist(
                installDirectories: [runtimeDirectory],
                voiceDirectory: voiceDirectory
            ),
            "Piper should become available once the downloaded voice model and config are in the voice cache"
        )
    }

    static func testSpeechRuntimeInstallStateDistinguishesRuntimeAndModel() throws {
        try expectEqual(
            LocalRuntimeInstallState.state(hasRuntime: true, hasModel: true),
            .complete,
            "generic local runtime state should treat runtime plus model as complete"
        )
        try expectEqual(
            SpeechRuntimeResourceManager.runtimeInstallState(hasRuntime: true, hasModel: true),
            .complete,
            "complete runtime state should require both runtime and model files"
        )
        try expectEqual(
            SpeechRuntimeResourceManager.runtimeInstallState(hasRuntime: false, hasModel: true),
            .missingRuntime,
            "runtime state should report missing runtime separately from missing model"
        )
        try expectEqual(
            SpeechRuntimeResourceManager.runtimeInstallState(hasRuntime: true, hasModel: false),
            .missingModel,
            "runtime state should report missing model separately from missing runtime"
        )
        try expectEqual(
            SpeechRuntimeResourceManager.runtimeInstallState(hasRuntime: false, hasModel: false),
            .missingRuntimeAndModel,
            "runtime state should report when both runtime and model files are missing"
        )

        try expectEqual(
            SpeechRuntimeResourceManager.incompleteInstallStatusText(for: .piper, installState: .missingRuntime),
            "缺少运行时 · 模型已安装 · 约 112 MB",
            "missing runtime should surface the new repair-oriented status copy"
        )
        try expectEqual(
            SpeechRuntimeResourceManager.incompleteInstallStatusText(for: .piper, installState: .missingModel),
            nil,
            "missing model should keep the existing not-downloaded status copy"
        )
    }

    static func testSpeechRuntimeHealthDistinguishesRuntimeAndModelPaths() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("leafreader-runtime-health-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let runtimeDirectory = root.appendingPathComponent("piper-tts-runtime", isDirectory: true)
        let voiceDirectory = root.appendingPathComponent("piper-voices", isDirectory: true)
        try fileManager.createDirectory(at: voiceDirectory, withIntermediateDirectories: true)
        try Data().write(to: voiceDirectory.appendingPathComponent("en_US-lessac-high.onnx"))
        try Data("{}".utf8).write(to: voiceDirectory.appendingPathComponent("en_US-lessac-high.onnx.json"))

        let missingRuntimeHealth = SpeechRuntimeAvailability.runtimeHealth(
            for: .piper,
            installDirectories: [runtimeDirectory],
            voiceDirectory: voiceDirectory
        )
        try expect(!missingRuntimeHealth.hasRuntime, "runtime health should report missing Piper runtime files")
        try expect(missingRuntimeHealth.hasModel, "runtime health should report installed Piper voice files")
        try expectEqual(
            missingRuntimeHealth.installState,
            .missingRuntime,
            "runtime health should derive a missing-runtime install state"
        )

        let executable = runtimeDirectory.appendingPathComponent("piper/piper")
        try fileManager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: runtimeDirectory.appendingPathComponent("piper-phonemize/lib", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: runtimeDirectory.appendingPathComponent("piper-phonemize/share/espeak-ng-data", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data().write(to: executable)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let completeHealth = SpeechRuntimeAvailability.runtimeHealth(
            for: .piper,
            installDirectories: [runtimeDirectory],
            voiceDirectory: voiceDirectory
        )
        try expect(completeHealth.isComplete, "runtime health should become complete once runtime and model files exist")
    }

    static func testKokoroModelDownloadMakesBundledRuntimeAvailable() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("leafreader-kokoro-availability-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let runtimeDirectory = root.appendingPathComponent("kokoro-coreml", isDirectory: true)
        let modelCacheRoot = root.appendingPathComponent("Models", isDirectory: true)
        let executable = runtimeDirectory.appendingPathComponent("fluidaudiocli")
        try fileManager.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
        try Data().write(to: executable)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        try expect(
            !SpeechRuntimeAvailability.kokoroRuntimeAndModelPathsExist(
                installDirectories: [runtimeDirectory],
                modelCacheRoot: modelCacheRoot
            ),
            "Kokoro should remain unavailable after runtime install until model cache files are downloaded"
        )

        let aneDirectory = modelCacheRoot
            .appendingPathComponent("kokoro-82m-coreml", isDirectory: true)
            .appendingPathComponent("ANE", isDirectory: true)
        let g2pDirectory = modelCacheRoot.appendingPathComponent("kokoro", isDirectory: true)
        try fileManager.createDirectory(at: aneDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: g2pDirectory, withIntermediateDirectories: true)
        for fileName in [
            "KokoroAlbert.mlmodelc",
            "KokoroPostAlbert.mlmodelc",
            "KokoroAlignment.mlmodelc",
            "KokoroProsody.mlmodelc",
            "KokoroNoise.mlmodelc",
            "KokoroVocoder.mlmodelc",
            "KokoroTail.mlmodelc",
            "vocab.json"
        ] {
            try Data().write(to: aneDirectory.appendingPathComponent(fileName))
        }
        for fileName in ["G2PEncoder.mlmodelc", "G2PDecoder.mlmodelc", "g2p_vocab.json"] {
            try Data().write(to: g2pDirectory.appendingPathComponent(fileName))
        }

        try expect(
            SpeechRuntimeAvailability.kokoroRuntimeAndModelPathsExist(
                installDirectories: [runtimeDirectory],
                modelCacheRoot: modelCacheRoot
            ),
            "Kokoro should become available once the downloaded model cache contains all required files"
        )
    }

    static func testKokoroMandarinModelDownloadMakesBundledRuntimeAvailable() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("leafreader-kokoro-zh-availability-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let runtimeDirectory = root.appendingPathComponent("kokoro-coreml", isDirectory: true)
        let modelCacheRoot = root.appendingPathComponent("Models", isDirectory: true)
        let executable = runtimeDirectory.appendingPathComponent("fluidaudiocli")
        try fileManager.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
        try Data().write(to: executable)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let aneDirectory = modelCacheRoot
            .appendingPathComponent("kokoro-82m-coreml", isDirectory: true)
            .appendingPathComponent("ANE-zh", isDirectory: true)
        try fileManager.createDirectory(
            at: aneDirectory.appendingPathComponent("assets", isDirectory: true),
            withIntermediateDirectories: true
        )
        for fileName in [
            "KokoroAlbert.mlmodelc",
            "KokoroPostAlbert.mlmodelc",
            "KokoroAlignment.mlmodelc",
            "KokoroProsody.mlmodelc",
            "KokoroNoise.mlmodelc",
            "KokoroVocoder.mlmodelc",
            "KokoroTail.mlmodelc",
            "vocab.json",
            "assets/pinyin_phrases.bin",
            "assets/pinyin_single.bin"
        ] {
            try Data().write(to: aneDirectory.appendingPathComponent(fileName))
        }

        try expect(
            SpeechRuntimeAvailability.kokoroRuntimeAndModelPathsExist(
                installDirectories: [runtimeDirectory],
                modelCacheRoot: modelCacheRoot
            ),
            "Kokoro should become available when the Mandarin ANE model cache is complete"
        )
    }

    static func testKittenModelDownloadMakesBundledRuntimeAvailable() throws {
        let fileManager = FileManager.default
        let runtimeDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("leafreader-kitten-availability-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: runtimeDirectory) }

        let executable = runtimeDirectory.appendingPathComponent("kitten-tts-aarch64-macos/kitten-tts-server")
        try fileManager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: executable)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        try expect(
            !SpeechRuntimeAvailability.kittenRuntimeAndModelPathsExist(installDirectories: [runtimeDirectory]),
            "KittenTTS should remain unavailable after runtime install until model files are downloaded"
        )

        let modelDirectory = runtimeDirectory.appendingPathComponent("kitten-tts-mini", isDirectory: true)
        try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try Data().write(to: modelDirectory.appendingPathComponent("kitten_tts_mini_v0_8.onnx"))
        try Data().write(to: modelDirectory.appendingPathComponent("voices.npz"))
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("config.json"))

        try expect(
            SpeechRuntimeAvailability.kittenRuntimeAndModelPathsExist(installDirectories: [runtimeDirectory]),
            "KittenTTS should become available once the downloaded model directory contains all required files"
        )
    }
}
