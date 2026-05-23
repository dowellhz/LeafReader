import AVFoundation

extension ReaderWindowController: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        guard synthesizer === vocabularySpeechSynthesizer else { return }
        clearSelectionForSpeechStartIfNeeded()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard synthesizer === vocabularySpeechSynthesizer else {
            return
        }
        if let completion = selectionSpeechCompletion {
            selectionSpeechCompletion = nil
            completion()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        guard synthesizer === vocabularySpeechSynthesizer else { return }
        shouldClearSelectionOnSpeechStart = false
        selectionSpeechCompletion = nil
    }
}
