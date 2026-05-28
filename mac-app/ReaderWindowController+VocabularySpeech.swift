import Cocoa

extension ReaderWindowController {
    func vocabularySpeakerWord(_ text: String) -> String? {
        VocabularyTextPolicy.speakableWord(text)
    }

    @objc func playVocabularyWord(_ sender: NSButton) {
        guard let word = (sender as? VocabularySpeakerButton)?.spokenWord else { return }
        speakVocabularyWord(word)
    }

    func autoPlayVocabularyWordIfNeeded(_ word: String) {
        guard AISettingsStore.speakSelectedWordEnabled,
              let spokenWord = vocabularySpeakerWord(word) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.speakVocabularyWord(spokenWord)
        }
    }

    func speakVocabularyWord(_ word: String) {
        speakVocabularyTexts([word])
    }

    func autoPlayVocabularyAnswerIfNeeded(record: VocabularyExportRecord) {
        guard AISettingsStore.speakSelectedWordEnabled,
              let spokenWord = vocabularySpeakerWord(record.word) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.speakVocabularyWord(spokenWord)
        }
    }

    func autoPlayVocabularyContextIfNeeded(record: VocabularyExportRecord) {
        guard AISettingsStore.speakSelectedWordEnabled else { return }
        let context = record.context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isMeaningfulVocabularyContext(context) else { return }
        let sentence = String(context.prefix(280))
        DispatchQueue.main.async { [weak self] in
            self?.speakVocabularyTexts([sentence], options: .normalSpeed)
        }
    }

    func speakVocabularyTexts(
        _ texts: [String],
        options: SpeechPlaybackCoordinator.SynthesisOptions = .default
    ) {
        vocabularySpeechCoordinator.speak(texts, options: options)
    }
}
