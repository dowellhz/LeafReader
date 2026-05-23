import Foundation

enum KokoroVoiceResourceManager {
    private static let voiceEmbeddingCount = 510
    private static let voiceEmbeddingWidth = 256
    private static let expectedVoiceBinSize = voiceEmbeddingCount * voiceEmbeddingWidth * MemoryLayout<Float>.size

    static func ensureInstalled(voiceID: String, variant: String) -> Bool {
        guard let location = voiceLocation(voiceID: voiceID, variant: variant) else {
            return true
        }
        let destination = cacheURL(for: voiceID, location: location)
        if isUsableVoiceBin(at: destination) {
            return true
        }
        guard let source = bundledVoiceURL(for: voiceID, location: location),
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

    private enum VoiceLocation {
        case english
        case chinese

        var bundleDirectoryName: String {
            switch self {
            case .english:
                return "English"
            case .chinese:
                return "Chinese"
            }
        }

        var cacheSubpath: String {
            switch self {
            case .english:
                return "ANE"
            case .chinese:
                return "ANE-zh/voices"
            }
        }
    }

    private static func voiceLocation(voiceID: String, variant: String) -> VoiceLocation? {
        if variant == "en", AISettingsStore.kokoroEnglishSpeechVoiceIDs.contains(voiceID) {
            return .english
        }
        if variant == "zh", AISettingsStore.kokoroChineseSpeechVoiceIDs.contains(voiceID) {
            return .chinese
        }
        return nil
    }

    private static func bundledVoiceURL(for voiceID: String, location: VoiceLocation) -> URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("KokoroVoices", isDirectory: true)
            .appendingPathComponent(location.bundleDirectoryName, isDirectory: true)
            .appendingPathComponent("\(voiceID).bin")
    }

    private static func cacheURL(for voiceID: String, location: VoiceLocation) -> URL {
        SpeechRuntimeResourceManager.Runtime.fluidAudioModelCacheRoot
            .appendingPathComponent("kokoro-82m-coreml", isDirectory: true)
            .appendingPathComponent(location.cacheSubpath, isDirectory: true)
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
