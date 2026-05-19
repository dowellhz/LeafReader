import Cocoa

extension ReaderWindowController {
    func crossLingualRetrievalQueryIfNeeded(
        question: String,
        currentPageText: String,
        generation: Int,
        completion: @escaping (String?) -> Void
    ) {
        guard questionLooksMostlyChinese(question),
              textLooksMostlyEnglish(currentPageText),
              AISettingsStore.hasAPIKeyForSelectedModel else {
            completion(nil)
            return
        }

        let prompt = """
        Convert the user's Chinese document-search question into one concise English search query for retrieving passages from an English book.

        Requirements:
        - Output only the English search query.
        - Keep names, places, book-specific terms, and quoted words.
        - Do not answer the question.
        - Do not add explanations.

        Chinese question:
        \(question)
        """
        retrievalQueryTask?.cancel()
        retrievalQueryTask = retrievalQueryClient.send(messages: [
            ChatMessage(role: "system", content: "You create concise English search queries."),
            ChatMessage(role: "user", content: prompt)
        ]) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, generation == self.documentPromptGeneration else { return }
                self.retrievalQueryTask = nil
                if case .success(let text) = result {
                    let cleaned = text
                        .replacingOccurrences(of: #"^[\"“”']+|[\"“”']+$"#, with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    completion(cleaned.isEmpty ? nil : String(cleaned.prefix(240)))
                    return
                }
                completion(nil)
            }
        }
    }

    func questionLooksMostlyChinese(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        let chineseCount = scalars.filter { $0.value >= 0x4E00 && $0.value <= 0x9FFF }.count
        let letterCount = scalars.filter { CharacterSet.letters.contains($0) }.count
        return chineseCount >= 2 && chineseCount * 2 >= max(1, letterCount)
    }

    func textLooksMostlyEnglish(_ text: String) -> Bool {
        let sample = String(text.prefix(1200))
        let scalars = sample.unicodeScalars
        let latinCount = scalars.filter {
            ($0.value >= 0x41 && $0.value <= 0x5A) || ($0.value >= 0x61 && $0.value <= 0x7A)
        }.count
        let chineseCount = scalars.filter { $0.value >= 0x4E00 && $0.value <= 0x9FFF }.count
        return latinCount >= 80 && latinCount > chineseCount * 4
    }
}
