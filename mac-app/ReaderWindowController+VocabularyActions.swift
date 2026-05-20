import AVFoundation
import Cocoa

extension ReaderWindowController {
    func reloadVocabularyPanelContent() {
        guard let panel = vocabularyPanel,
              let root = panel.contentView else { return }
        let filter = selectedVocabularyListFilter(in: root)
        let isDark = ReaderTheme.selected == .dark
        refreshVocabularyListContent(in: root, filter: filter)
        if !vocabularyListModeEnabled,
           let reviewContainer = findView(identifier: "vocabularyReviewContainer", in: root) {
            populateVocabularyReviewContainer(reviewContainer, records: currentVocabularyExportRecords, filter: filter, isDark: isDark, autoPlayNewCard: !vocabularyListModeEnabled)
        }
    }

    func scheduleVocabularyPanelReload() {
        vocabularyPanelReloadTask.schedule { [weak self] in
            self?.reloadVocabularyPanelContent()
        }
    }

    @objc func markVocabularyRecordMastered(_ sender: NSButton) {
        let ids = sender.identifier?.rawValue
            .split(separator: "|")
            .map(String.init)
            .filter { !$0.isEmpty } ?? []
        guard !ids.isEmpty else { return }
        removeVocabularyRecords(ids: ids)
        if let card = sender.superview,
           let stack = card.superview as? NSStackView {
            stack.removeArrangedSubview(card)
            card.removeFromSuperview()
        }
        currentVocabularyExportRecords.removeAll { record in
            !Set(record.ids).isDisjoint(with: ids)
        }
        if currentVocabularyExportRecords.isEmpty,
           let panel = vocabularyPanel {
            closeVocabularyPanel(panel)
        } else {
            vocabularyReviewIndex = min(vocabularyReviewIndex, max(0, vocabularyReviewRecords(currentVocabularyExportRecords).count - 1))
            vocabularyReviewAnswerShown = false
            scheduleVocabularyPanelReload()
        }
    }

    func removeVocabularyRecords(ids: [String]) {
        let idSet = Set(ids)
        pendingPDFWordRecords = pendingPDFWordRecords.filter { !idSet.contains($0.key) }
        pendingWebWordRecords = pendingWebWordRecords.filter { !idSet.contains($0.key) }

        if currentDocumentKind == .pdf {
            let removedRecords = storedWordRecords.filter { idSet.contains($0.id) }
            guard !removedRecords.isEmpty else {
                aiPanel.removeLinkedWordBubbles(ids: ids)
                saveCurrentAIConversationBeforeDocumentChange()
                return
            }
            for record in removedRecords {
                guard let page = pdfView.document?.page(at: record.pageIndex) else { continue }
                for annotation in page.annotations where storedWordID(from: annotation) == record.id {
                    page.removeAnnotation(annotation)
                }
            }
            storedWordRecords.removeAll { idSet.contains($0.id) }
            highlightedSelectionKeys.removeAll()
            restoreStoredWordAnnotations()
            deleteStoredWordRecords(ids: ids)
            pdfView.setNeedsDisplay(pdfView.bounds)
        } else {
            storedWebWordRecords.removeAll { idSet.contains($0.id) }
            deleteStoredWebWordRecords(ids: ids)
            restoreStoredWebWordHighlights { [weak self] in
                guard let self else { return }
                self.restoreWebAISourceUnderlines(for: self.aiPanel.activeConversationSources())
            }
        }

        aiPanel.removeLinkedWordBubbles(ids: ids)
        saveCurrentAIConversationBeforeDocumentChange()
    }

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
            self?.speakVocabularyTexts([sentence])
        }
    }

    func speakVocabularyTexts(_ texts: [String]) {
        let playableTexts = texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !playableTexts.isEmpty else { return }
        if vocabularySpeechSynthesizer.isSpeaking {
            vocabularySpeechSynthesizer.stopSpeaking(at: AVSpeechBoundary.immediate)
        }
        for text in playableTexts {
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
            vocabularySpeechSynthesizer.speak(utterance)
        }
    }

    func vocabularyAnswerBody(_ answer: String, word: String) -> String {
        var lines = answer.components(separatedBy: .newlines)
        let normalizedWord = normalizeVocabularyHeading(word)
        while let first = lines.first {
            let normalizedFirst = normalizeVocabularyHeading(first)
            if normalizedFirst.isEmpty {
                lines.removeFirst()
                continue
            }
            if normalizedFirst == normalizedWord {
                lines.removeFirst()
                continue
            }
            break
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func normalizeVocabularyHeading(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\*\*(.*)\*\*$"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"^__(.*)__$"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ：:"))
            .lowercased()
    }
}
