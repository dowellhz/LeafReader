import Foundation

enum SpeechRuntimeLogicTests {
    static func testAISettingsStoreSpeechSelectionValidation() throws {
        try withIsolatedAISettingsDefaults { defaults in
            try expectEqual(AISettingsStore.selectedSpeechRuntimeID, "piper", "speech runtime should default to Piper")
            try expectEqual(AISettingsStore.selectedKokoroSpeechVoiceID, "af_heart", "Kokoro voice should default to Heart")
            try expectEqual(AISettingsStore.selectedPiperSpeechVoiceID, "en_US-lessac-high", "Piper voice should default to Lessac High")
            try expectEqual(AISettingsStore.selectedSupertonicSpeechVoiceID, "M1", "Supertonic voice should default to M1")
            try expectEqual(AISettingsStore.selectedSpeechSpeedID, "normal", "speech speed should default to normal")
            try expect(AISettingsStore.speechVoiceOptions(runtimeID: "missing").contains { $0.id == "en_US-lessac-high" }, "unknown runtime voice options should fall back to Piper")
            try expect(AISettingsStore.speechVoiceOptions(runtimeID: "kokoro").contains { $0.id == "af_heart" }, "Kokoro voice options should include Heart")
            try expect(AISettingsStore.speechVoiceOptions(runtimeID: "piper").contains { $0.id == "en_US-lessac-high" }, "Piper voice options should include Lessac High")
            try expect(AISettingsStore.speechVoiceOptions(runtimeID: "supertonic").contains { $0.id == "M1" }, "Supertonic voice options should include M1")
            try expect(!AISettingsStore.speechVoiceOptions(runtimeID: "supertonic").contains { $0.id == "M2" }, "Supertonic voice options should hide unavailable M2")
            try expect(!AISettingsStore.speechVoiceOptions(runtimeID: "supertonic").contains { $0.id == "F2" }, "Supertonic voice options should hide unavailable F2")

            AISettingsStore.saveSelectedSpeechRuntimeID("supertonic")
            AISettingsStore.saveKokoroSpeechVoiceID("zf_001")
            AISettingsStore.savePiperSpeechVoiceID("en_US-lessac-high")
            AISettingsStore.saveSupertonicSpeechVoiceID("F4")
            AISettingsStore.saveSpeechSpeedID("slow")
            try expectEqual(AISettingsStore.selectedSpeechRuntimeID, "supertonic", "valid Supertonic speech runtime should save")
            try expectEqual(AISettingsStore.selectedKokoroSpeechVoiceID, "zf_001", "valid Kokoro voice should save")
            try expectEqual(AISettingsStore.selectedPiperSpeechVoiceID, "en_US-lessac-high", "valid Piper voice should save")
            try expectEqual(AISettingsStore.selectedSupertonicSpeechVoiceID, "F4", "valid Supertonic voice should save")
            try expectEqual(AISettingsStore.selectedSpeechSpeedID, "slow", "valid speech speed should save")

            AISettingsStore.saveSelectedSpeechRuntimeID("missing-runtime")
            AISettingsStore.saveKokoroSpeechVoiceID("Dragon")
            AISettingsStore.savePiperSpeechVoiceID("Dragon")
            AISettingsStore.saveSupertonicSpeechVoiceID("Dragon")
            AISettingsStore.saveSpeechSpeedID("warp")
            try expectEqual(AISettingsStore.selectedSpeechRuntimeID, "supertonic", "invalid speech runtime should be ignored")
            try expectEqual(AISettingsStore.selectedKokoroSpeechVoiceID, "zf_001", "invalid Kokoro voice should be ignored")
            try expectEqual(AISettingsStore.selectedPiperSpeechVoiceID, "en_US-lessac-high", "invalid Piper voice should be ignored")
            try expectEqual(AISettingsStore.selectedSupertonicSpeechVoiceID, "F4", "invalid Supertonic voice should be ignored")
            try expectEqual(AISettingsStore.selectedSpeechSpeedID, "slow", "invalid speech speed should be ignored")

            AISettingsStore.saveSpeechVoiceID("en_US-lessac-high", runtimeID: "missing")
            AISettingsStore.saveSpeechVoiceID("zf_002", runtimeID: "kokoro")
            AISettingsStore.saveSpeechVoiceID("en_US-lessac-high", runtimeID: "piper")
            AISettingsStore.saveSpeechVoiceID("F1", runtimeID: "supertonic")
            try expectEqual(AISettingsStore.selectedSpeechVoiceID(runtimeID: "missing"), "en_US-lessac-high", "generic fallback voice save should use the Piper list")
            try expectEqual(AISettingsStore.selectedSpeechVoiceID(runtimeID: "kokoro"), "zf_002", "generic Kokoro voice save should use the Kokoro list")
            try expectEqual(AISettingsStore.selectedSpeechVoiceID(runtimeID: "piper"), "en_US-lessac-high", "generic Piper voice save should use the Piper list")
            try expectEqual(AISettingsStore.selectedSpeechVoiceID(runtimeID: "supertonic"), "F1", "generic Supertonic voice save should use the Supertonic list")
            try expectEqual(AISettingsStore.speechVoiceTitle(for: "zf_002", runtimeID: "kokoro"), AppText.localized("中文女声 2", "Chinese Female 2"), "Kokoro preview should use the display voice title")

            defaults.set(" missing-runtime ", forKey: AISettingsStore.selectedSpeechRuntimeKey)
            defaults.set(" Dragon ", forKey: AISettingsStore.kokoroSpeechVoiceKey)
            defaults.set(" Dragon ", forKey: AISettingsStore.piperSpeechVoiceKey)
            defaults.set(" Dragon ", forKey: AISettingsStore.supertonicSpeechVoiceKey)
            defaults.set(" warp ", forKey: AISettingsStore.speechSpeedKey)
            try expectEqual(AISettingsStore.selectedSpeechRuntimeID, "piper", "invalid stored speech runtime should fall back")
            try expectEqual(AISettingsStore.selectedKokoroSpeechVoiceID, "af_heart", "invalid stored Kokoro voice should fall back")
            try expectEqual(AISettingsStore.selectedPiperSpeechVoiceID, "en_US-lessac-high", "invalid stored Piper voice should fall back")
            try expectEqual(AISettingsStore.selectedSupertonicSpeechVoiceID, "M1", "invalid stored Supertonic voice should fall back")
            try expectEqual(AISettingsStore.selectedSpeechSpeedID, "normal", "invalid stored speech speed should fall back")
        }
    }

    static func testPiperSpeechSpeedLengthScale() throws {
        try withIsolatedAISettingsDefaults { _ in
            try expectEqual(AISettingsStore.piperLengthScale, 1.0, "Piper normal speed should use the default length scale")
            AISettingsStore.saveSpeechSpeedID("fast")
            try expectEqual(AISettingsStore.piperLengthScale, 0.72, "Piper fast speed should shorten phoneme length")
            AISettingsStore.saveSpeechSpeedID("slow")
            try expectEqual(AISettingsStore.piperLengthScale, 1.35, "Piper slow speed should lengthen phonemes")
            AISettingsStore.saveSpeechSpeedID("verySlow")
            try expectEqual(AISettingsStore.piperLengthScale, 1.65, "Piper very slow speed should lengthen phonemes further")
        }
    }

    static func testKokoroSpeechSpeedMultiplier() throws {
        try withIsolatedAISettingsDefaults { _ in
            try expectEqual(AISettingsStore.kokoroSpeechSpeedMultiplier, 1.0, "Kokoro normal speed should use the model default")
            AISettingsStore.saveSpeechSpeedID("fast")
            try expectEqual(AISettingsStore.kokoroSpeechSpeedMultiplier, 1.25, "Kokoro fast speed should use the original faster model speed")
            AISettingsStore.saveSpeechSpeedID("slow")
            try expectEqual(AISettingsStore.kokoroSpeechSpeedMultiplier, 0.82, "Kokoro slow speed should use the original lower model speed")
            AISettingsStore.saveSpeechSpeedID("verySlow")
            try expectEqual(AISettingsStore.kokoroSpeechSpeedMultiplier, 0.7, "Kokoro very slow speed should use the original lower model speed")
        }
    }

    static func testSpeechSynthesisErrorMessagesAreActionable() throws {
        try expect(
            SpeechSynthesisError.runtimeUnavailable("Piper").localizedDescription.contains("Piper"),
            "runtime errors should name the failing runtime"
        )
        try expect(
            SpeechSynthesisError.voiceUnavailable("Kokoro").localizedDescription.contains(AppText.localized("重新下载", "Download")),
            "voice errors should tell the user to download the model again"
        )
        try expect(
            SpeechSynthesisError.workerTimedOut("Kokoro").localizedDescription.contains(AppText.localized("超时", "timed out")),
            "timeout errors should be distinguishable from missing-model errors"
        )
        try expectEqual(
            SpeechSynthesisError.classifiedProcessFailure(
                runtime: "Piper",
                diagnostic: "dyld: Library not loaded: @rpath/libonnxruntime.dylib"
            ),
            .dependencyMissing("Piper"),
            "dynamic-library failures should be classified as missing dependencies"
        )
        try expectEqual(
            SpeechSynthesisError.classifiedProcessFailure(
                runtime: "Kokoro",
                diagnostic: "failed to load onnx model config"
            ),
            .modelLoadFailed("Kokoro"),
            "model/config failures should be classified as model load failures"
        )
        try expectEqual(
            SpeechSynthesisError.classifiedProcessFailure(
                runtime: "Piper",
                diagnostic: "address already in use"
            ),
            .portUnavailable("Piper"),
            "local server port failures should be classified separately"
        )
        try expect(
            SpeechSynthesisError.modelLoadFailed("Piper").supportsRedownload,
            "model load failures should support one-click redownload"
        )
        try expect(
            !SpeechSynthesisError.dependencyMissing("Piper").supportsRedownload,
            "dependency failures should point users to app/runtime repair instead of model redownload"
        )
    }

    static func testSpeechRuntimeInferenceFailureStore() throws {
        let runtime = SpeechRuntimeResourceManager.Runtime.piper
        SpeechRuntimeInferenceFailureStore.clear(for: runtime)
        SpeechRuntimeInferenceFailureStore.record(
            .workerTimedOut("Piper"),
            for: runtime,
            voiceID: "en_US-lessac-high",
            context: "preview",
            text: "Hello",
            outputURL: URL(fileURLWithPath: "/tmp/leafreader-piper.wav")
        )
        let failure = SpeechRuntimeInferenceFailureStore.failure(for: runtime)
        try expectEqual(failure?.runtimeID, "piper", "inference failure should store the runtime id")
        try expectEqual(failure?.voiceID, "en_US-lessac-high", "inference failure should store the voice id")
        try expectEqual(failure?.context, "preview", "inference failure should store the failure context")
        try expectEqual(failure?.textLength, 5, "inference failure should store text length for diagnostics")
        try expectEqual(
            SpeechRuntimeInferenceFailureStore.relativeTimeText(since: 100, now: 220),
            AppText.localized("2分钟前", "2m ago"),
            "inference failure status should format a relative failure time"
        )
        SpeechRuntimeInferenceFailureStore.clear(for: runtime)
    }
}
