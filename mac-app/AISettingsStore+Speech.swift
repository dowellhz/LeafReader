import Foundation

extension AISettingsStore {
    static let selectedSpeechRuntimeKey = "selectedSpeechRuntime"
    static let speechSpeedKey = "speechSpeed"
    static let kittenSpeechVoiceKey = "kittenSpeechVoice"
    static let kokoroSpeechVoiceKey = "kokoroSpeechVoice"
    static let piperSpeechVoiceKey = "piperSpeechVoice"

    private static let defaultSpeechRuntimeID = "kitten"
    private static let defaultSpeechSpeedID = "normal"
    static let defaultKittenSpeechVoiceID = SpeechVoiceCatalog.defaultKittenVoiceID
    static let defaultKokoroSpeechVoiceID = SpeechVoiceCatalog.defaultKokoroVoiceID
    static let defaultPiperSpeechVoiceID = SpeechVoiceCatalog.defaultPiperVoiceID
    private static let validSpeechRuntimeIDs = Set(["kokoro", "kitten", "piper"])
    private static let validSpeechSpeedIDs = Set(["fast", "normal", "slow", "verySlow"])
    static let kokoroEnglishSpeechVoiceIDs = SpeechVoiceCatalog.kokoroEnglishVoiceIDs
    static let kokoroChineseSpeechVoiceIDs = SpeechVoiceCatalog.kokoroChineseVoiceIDs

    static var selectedSpeechRuntimeID: String {
        let value = nonEmptyTrimmed(defaults.string(forKey: selectedSpeechRuntimeKey)) ?? defaultSpeechRuntimeID
        return validSpeechRuntimeIDs.contains(value) ? value : defaultSpeechRuntimeID
    }

    static func saveSelectedSpeechRuntimeID(_ id: String) {
        guard validSpeechRuntimeIDs.contains(id) else { return }
        defaults.set(id, forKey: selectedSpeechRuntimeKey)
        defaults.synchronize()
    }

    static var selectedSpeechSpeedID: String {
        let value = nonEmptyTrimmed(defaults.string(forKey: speechSpeedKey)) ?? defaultSpeechSpeedID
        return validSpeechSpeedIDs.contains(value) ? value : defaultSpeechSpeedID
    }

    static var speechSpeedOptions: [(title: String, id: String)] {
        [
            (AppText.localized("快", "Fast"), "fast"),
            (AppText.localized("正常", "Normal"), "normal"),
            (AppText.localized("慢", "Slow"), "slow"),
            (AppText.localized("非常慢", "Very Slow"), "verySlow")
        ]
    }

    static var kittenSpeechVoiceOptions: [(title: String, id: String)] {
        SpeechVoiceCatalog.kittenVoiceOptions
    }

    static var kokoroSpeechVoiceOptions: [(title: String, id: String)] {
        SpeechVoiceCatalog.kokoroVoiceOptions
    }

    static var piperSpeechVoiceOptions: [(title: String, id: String)] {
        SpeechVoiceCatalog.piperVoiceOptions
    }

    static func kokoroSpeechVoiceOptions(languageHint: SpeechLanguageHint?) -> [(title: String, id: String)] {
        SpeechVoiceCatalog.kokoroVoiceOptions(languageHint: languageHint)
    }

    static func speechVoiceOptions(runtimeID: String?) -> [(title: String, id: String)] {
        if isKokoroSpeechRuntime(runtimeID) {
            return kokoroSpeechVoiceOptions
        }
        if isPiperSpeechRuntime(runtimeID) {
            return piperSpeechVoiceOptions
        }
        return kittenSpeechVoiceOptions
    }

    static func speechVoiceOptions(runtimeID: String?, languageHint: SpeechLanguageHint?) -> [(title: String, id: String)] {
        if isKokoroSpeechRuntime(runtimeID) {
            return kokoroSpeechVoiceOptions(languageHint: languageHint)
        }
        if isPiperSpeechRuntime(runtimeID) {
            return piperSpeechVoiceOptions
        }
        return kittenSpeechVoiceOptions
    }

    static func selectedSpeechVoiceID(runtimeID: String?) -> String {
        if isKokoroSpeechRuntime(runtimeID) {
            return selectedKokoroSpeechVoiceID
        }
        if isPiperSpeechRuntime(runtimeID) {
            return selectedPiperSpeechVoiceID
        }
        return selectedKittenSpeechVoiceID
    }

    static func selectedKokoroSpeechVoiceID(languageHint: SpeechLanguageHint?) -> String {
        SpeechVoiceCatalog.selectedKokoroVoiceID(selectedKokoroSpeechVoiceID, languageHint: languageHint)
    }

    static func speechVoiceTitle(for id: String, runtimeID: String?) -> String {
        speechVoiceOptions(runtimeID: runtimeID).first { $0.id == id }?.title ?? id
    }

    static var selectedKittenSpeechVoiceID: String {
        let value = nonEmptyTrimmed(defaults.string(forKey: kittenSpeechVoiceKey)) ?? defaultKittenSpeechVoiceID
        return SpeechVoiceCatalog.isValidKittenVoiceID(value) ? value : defaultKittenSpeechVoiceID
    }

    static var selectedKokoroSpeechVoiceID: String {
        let value = nonEmptyTrimmed(defaults.string(forKey: kokoroSpeechVoiceKey)) ?? defaultKokoroSpeechVoiceID
        return SpeechVoiceCatalog.isValidKokoroVoiceID(value) ? value : defaultKokoroSpeechVoiceID
    }

    static var selectedPiperSpeechVoiceID: String {
        let value = nonEmptyTrimmed(defaults.string(forKey: piperSpeechVoiceKey)) ?? defaultPiperSpeechVoiceID
        guard SpeechVoiceCatalog.isValidPiperVoiceID(value) else {
            return defaultPiperSpeechVoiceID
        }
        return SpeechVoiceCatalog.selectedPiperVoiceID(value)
    }

    static func saveKittenSpeechVoiceID(_ id: String) {
        guard SpeechVoiceCatalog.isValidKittenVoiceID(id) else { return }
        defaults.set(id, forKey: kittenSpeechVoiceKey)
        defaults.synchronize()
    }

    static func saveKokoroSpeechVoiceID(_ id: String) {
        guard SpeechVoiceCatalog.isValidKokoroVoiceID(id) else { return }
        defaults.set(id, forKey: kokoroSpeechVoiceKey)
        defaults.synchronize()
    }

    static func savePiperSpeechVoiceID(_ id: String) {
        guard SpeechVoiceCatalog.isValidPiperVoiceID(id) else { return }
        defaults.set(id, forKey: piperSpeechVoiceKey)
        defaults.synchronize()
    }

    static func saveSpeechVoiceID(_ id: String, runtimeID: String?) {
        if isKokoroSpeechRuntime(runtimeID) {
            saveKokoroSpeechVoiceID(id)
        } else if isPiperSpeechRuntime(runtimeID) {
            savePiperSpeechVoiceID(id)
        } else {
            saveKittenSpeechVoiceID(id)
        }
    }

    static func saveSpeechSpeedID(_ id: String) {
        guard validSpeechSpeedIDs.contains(id) else { return }
        defaults.set(id, forKey: speechSpeedKey)
        defaults.synchronize()
    }

    static var kittenSpeechSpeedMultiplier: Double {
        switch selectedSpeechSpeedID {
        case "fast": return 1.25
        case "slow": return 0.82
        case "verySlow": return 0.65
        default: return 1.0
        }
    }

    static var kokoroSpeechSpeedMultiplier: Double {
        switch selectedSpeechSpeedID {
        case "fast": return 1.25
        case "slow": return 0.82
        case "verySlow": return 0.7
        default: return 1.0
        }
    }

    static var piperLengthScale: Double {
        switch selectedSpeechSpeedID {
        case "fast": return 0.72
        case "slow": return 1.35
        case "verySlow": return 1.65
        default: return 1.0
        }
    }

    private static func isKokoroSpeechRuntime(_ runtimeID: String?) -> Bool {
        runtimeID == SpeechRuntimeResourceManager.Runtime.kokoro.id
    }

    private static func isPiperSpeechRuntime(_ runtimeID: String?) -> Bool {
        runtimeID == SpeechRuntimeResourceManager.Runtime.piper.id
    }
}
