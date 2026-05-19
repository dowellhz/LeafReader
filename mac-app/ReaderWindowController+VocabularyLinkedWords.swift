import Cocoa

extension ReaderWindowController {
    func updateStoredLinkedWordAnswer(linkID: String, question: String, answer: String) {
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAnswer.isEmpty else {
            pendingPDFWordRecords.removeValue(forKey: linkID)
            pendingWebWordRecords.removeValue(forKey: linkID)
            return
        }

        if let index = storedWordRecords.firstIndex(where: { $0.id == linkID }) {
            storedWordRecords[index].question = question
            storedWordRecords[index].answer = trimmedAnswer
            saveStoredWordRecord(storedWordRecords[index])
            return
        }
        if let index = storedWebWordRecords.firstIndex(where: { $0.id == linkID }) {
            storedWebWordRecords[index].question = question
            storedWebWordRecords[index].answer = trimmedAnswer
            saveStoredWebWordRecord(storedWebWordRecords[index])
            return
        }

        if let pending = pendingPDFWordRecords.removeValue(forKey: linkID) {
            let record = StoredPDFWordRecord(
                id: pending.id,
                word: pending.word,
                pageIndex: pending.pageIndex,
                bounds: pending.bounds,
                context: pending.context,
                question: question,
                answer: trimmedAnswer,
                createdAt: pending.createdAt,
                srs: VocabularySRSState.initial(createdAt: pending.createdAt)
            )
            storedWordRecords.append(record)
            addStoredWordAnnotation(record)
            saveStoredWordRecord(record)
            return
        }

        if let pending = pendingWebWordRecords.removeValue(forKey: linkID) {
            let record = StoredWebWordRecord(
                id: pending.id,
                word: pending.word,
                context: pending.context,
                occurrenceIndex: pending.occurrenceIndex,
                scrollProgress: pending.scrollProgress,
                question: question,
                answer: trimmedAnswer,
                createdAt: pending.createdAt,
                srs: VocabularySRSState.initial(createdAt: pending.createdAt)
            )
            storedWebWordRecords.append(record)
            saveStoredWebWordRecord(record)
        }
    }

    func discardPendingLinkedWord(linkID: String) {
        pendingPDFWordRecords.removeValue(forKey: linkID)
        if pendingWebWordRecords.removeValue(forKey: linkID) != nil {
            removeWebWordHighlight(id: linkID)
        }
    }

    func linkedWordAnswer(for linkID: String) -> String? {
        if let record = storedWordRecords.first(where: { $0.id == linkID }) {
            return record.answer
        }
        if let record = storedWebWordRecords.first(where: { $0.id == linkID }) {
            return record.answer
        }
        return nil
    }

    func reusablePDFWordRecord(for word: String) -> StoredPDFWordRecord? {
        let normalized = normalizedVocabularyKey(word)
        return storedWordRecords.first {
            normalizedVocabularyKey($0.word) == normalized && !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func reusableWebWordRecord(for word: String) -> StoredWebWordRecord? {
        let normalized = normalizedVocabularyKey(word)
        return storedWebWordRecords.first {
            normalizedVocabularyKey($0.word) == normalized && !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func normalizedVocabularyKey(_ word: String) -> String {
        word
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
