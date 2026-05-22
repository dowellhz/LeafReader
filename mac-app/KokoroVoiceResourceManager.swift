import Foundation

enum KokoroVoiceResourceManager {
    private static let voiceEmbeddingCount = 510
    private static let voiceEmbeddingWidth = 256
    private static let expectedVoiceBinSize = voiceEmbeddingCount * voiceEmbeddingWidth * MemoryLayout<Float>.size

    static func ensureInstalled(voiceID: String, variant: String) -> Bool {
        guard variant == "en",
              AISettingsStore.kokoroEnglishSpeechVoiceIDs.contains(voiceID) else {
            return true
        }
        let destination = englishVoiceCacheURL(for: voiceID)
        if isUsableVoiceBin(at: destination) {
            return true
        }
        guard let source = bundledEnglishVoiceURL(for: voiceID),
              isUsableVoiceBin(at: source) else {
            NSLog("LeafReader Kokoro voices: missing bundled voice bin for %@", voiceID)
            return false
        }
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: source, to: destination)
            return true
        } catch {
            NSLog(
                "LeafReader Kokoro voices: failed to install %@ (error=%@)",
                voiceID,
                error.localizedDescription
            )
            return false
        }
    }

    private static func bundledEnglishVoiceURL(for voiceID: String) -> URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("KokoroVoices/English", isDirectory: true)
            .appendingPathComponent("\(voiceID).bin")
    }

    private static func englishVoiceCacheURL(for voiceID: String) -> URL {
        SpeechRuntimeResourceManager.Runtime.fluidAudioModelCacheRoot
            .appendingPathComponent("kokoro-82m-coreml", isDirectory: true)
            .appendingPathComponent("ANE", isDirectory: true)
            .appendingPathComponent("\(voiceID).bin")
    }

    private static func isUsableVoiceBin(at url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.intValue == expectedVoiceBinSize
    }
}
