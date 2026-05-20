import AVFoundation
import Foundation

enum SpeechUtteranceFactory {
    static func utterance(for text: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice(for: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        return utterance
    }

    private static func voice(for text: String) -> AVSpeechSynthesisVoice? {
        for language in preferredLanguages(for: text) {
            if let voice = AVSpeechSynthesisVoice(language: language) {
                return voice
            }
            if let voice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.language.hasPrefix(language) }) {
                return voice
            }
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    private static func preferredLanguages(for text: String) -> [String] {
        if containsChinese(text) {
            return ["zh-CN", "zh-Hans", "zh-TW", "zh-Hant", "zh-HK"]
        }
        return ["en-US"]
    }

    private static func containsChinese(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2A6DF:
                return true
            default:
                return false
            }
        }
    }
}
