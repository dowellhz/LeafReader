import Cocoa
import Foundation

enum SpeechVoiceCatalog {
    static let defaultKittenVoiceID = "Jasper"
    static let defaultKokoroVoiceID = "af_heart"
    static let defaultPiperVoiceID = "en_US-lessac-high"
    static let defaultSupertonicVoiceID = "M1"

    private typealias Definition = (zhTitle: String, enTitle: String, id: String)

    private static let kittenVoiceIDs = ["Bella", "Jasper", "Luna", "Bruno", "Rosie", "Hugo", "Kiki", "Leo"]
    private static let supertonicVoiceIDs = ["M1", "M2", "M3", "M4", "M5", "F1", "F2", "F3", "F4", "F5"]

    private static let piperVoiceDefinitions: [Definition] = [
        ("美国女声 Lessac High", "American Female Lessac High", "en_US-lessac-high"),
        ("美国女声 Lessac Medium", "American Female Lessac Medium", "en_US-lessac-medium"),
        ("美国男声 Ryan", "American Male Ryan", "en_US-ryan-medium")
    ]

    private static let kokoroEnglishVoiceDefinitions: [Definition] = [
        ("美国女声 Bella", "American Female Bella", "af_bella"),
        ("美国女声 Heart", "American Female Heart", "af_heart"),
        ("美国男声 Adam", "American Male Adam", "am_adam"),
        ("英国女声 Emma", "British Female Emma", "bf_emma"),
        ("英国男声 George", "British Male George", "bm_george")
    ]

    private static let kokoroChineseVoiceDefinitions: [Definition] = [
        ("中文女声 1", "Chinese Female 1", "zf_001"),
        ("中文女声 2", "Chinese Female 2", "zf_002"),
        ("中文女声 3", "Chinese Female 3", "zf_003"),
        ("中文女声 4", "Chinese Female 4", "zf_004"),
        ("中文女声 5", "Chinese Female 5", "zf_005"),
        ("中文男声 1", "Chinese Male 1", "zm_009"),
        ("中文男声 2", "Chinese Male 2", "zm_010"),
        ("中文男声 3", "Chinese Male 3", "zm_011"),
        ("中文男声 4", "Chinese Male 4", "zm_012"),
        ("浑厚男", "Deep Male", "zm_013"),
        ("Maple", "Maple", "af_maple"),
        ("Sol", "Sol", "af_sol"),
        ("Vale", "Vale", "bf_vale")
    ]

    static let kokoroEnglishVoiceIDs = Set(kokoroEnglishVoiceDefinitions.map(\.id))
    static let kokoroChineseVoiceIDs = Set(kokoroChineseVoiceDefinitions.map(\.id))

    static func isValidKittenVoiceID(_ id: String) -> Bool {
        Set(kittenVoiceIDs).contains(id)
    }

    static func isValidKokoroVoiceID(_ id: String) -> Bool {
        kokoroEnglishVoiceIDs.contains(id) || kokoroChineseVoiceIDs.contains(id)
    }

    static func isValidPiperVoiceID(_ id: String) -> Bool {
        piperVoiceDefinitions.contains { $0.id == id }
    }

    static func isValidSupertonicVoiceID(_ id: String) -> Bool {
        Set(supertonicVoiceIDs).contains(id)
    }

    static var kittenVoiceOptions: [(title: String, id: String)] {
        kittenVoiceIDs.map { ($0, $0) }
    }

    static var kokoroVoiceOptions: [(title: String, id: String)] {
        kokoroVoiceOptions(languageHint: nil)
    }

    static var piperVoiceOptions: [(title: String, id: String)] {
        let options = localizedOptions(piperVoiceDefinitions)
        let availableIDs = availablePiperVoiceIDs()
        return availableIDs.isEmpty ? options : options.filter { availableIDs.contains($0.id) }
    }

    static var supertonicVoiceOptions: [(title: String, id: String)] {
        supertonicVoiceIDs.map { id in
            let title: String
            if id.hasPrefix("M") {
                title = AppText.localized("Supertonic 男声 \(id.dropFirst())", "Supertonic Male \(id.dropFirst())")
            } else {
                title = AppText.localized("Supertonic 女声 \(id.dropFirst())", "Supertonic Female \(id.dropFirst())")
            }
            return (title, id)
        }
    }

    static func selectedPiperVoiceID(_ selected: String) -> String {
        let options = piperVoiceOptions
        if options.contains(where: { $0.id == selected }) {
            return selected
        }
        return options.first?.id ?? defaultPiperVoiceID
    }

    static func kokoroVoiceOptions(languageHint: AISettingsStore.SpeechLanguageHint?) -> [(title: String, id: String)] {
        let englishOptions = localizedOptions(kokoroEnglishVoiceDefinitions)
        let chineseOptions = localizedOptions(kokoroChineseVoiceDefinitions)
        let availableIDs = availableKokoroVoiceIDs()
        let installedChineseOptions = availableIDs.isEmpty
            ? chineseOptions
            : chineseOptions.filter { availableIDs.contains($0.id) }
        switch languageHint {
        case .english:
            return englishOptions
        case .chinese:
            return installedChineseOptions
        case .none:
            return englishOptions + installedChineseOptions
        }
    }

    static func selectedKokoroVoiceID(_ selected: String, languageHint: AISettingsStore.SpeechLanguageHint?) -> String {
        let options = kokoroVoiceOptions(languageHint: languageHint)
        if options.contains(where: { $0.id == selected }) {
            return selected
        }
        return options.first?.id ?? defaultKokoroVoiceID
    }

    private static func localizedOptions(_ definitions: [Definition]) -> [(title: String, id: String)] {
        definitions.map {
            (title: AppText.localized($0.zhTitle, $0.enTitle), id: $0.id)
        }
    }

    private static func availableKokoroVoiceIDs() -> Set<String> {
        let root = SpeechRuntimeResourceManager.Runtime.fluidAudioModelCacheRoot
            .appendingPathComponent("kokoro-82m-coreml", isDirectory: true)
        let candidates = [
            root.appendingPathComponent("ANE", isDirectory: true),
            root.appendingPathComponent("ANE-zh/voices", isDirectory: true)
        ]
        var ids = Set<String>()
        for directory in candidates {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) else {
                continue
            }
            for url in contents where url.pathExtension == "bin" {
                ids.insert(url.deletingPathExtension().lastPathComponent)
            }
        }
        return ids
    }

    private static func availablePiperVoiceIDs() -> Set<String> {
        var ids = Set<String>()
        let voiceDirectory = SpeechRuntimeResourceManager.Runtime.piper
            .modelDirectory(in: SpeechRuntimeResourceManager.Runtime.piper.installDirectory)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: voiceDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return ids
        }
        let modelIDs = Set(contents.filter { $0.pathExtension == "onnx" }.map { $0.deletingPathExtension().lastPathComponent })
        let configIDs = Set(contents.filter { $0.lastPathComponent.hasSuffix(".onnx.json") }.map {
            $0.lastPathComponent.replacingOccurrences(of: ".onnx.json", with: "")
        })
        ids.formUnion(modelIDs.intersection(configIDs))
        return ids
    }
}
