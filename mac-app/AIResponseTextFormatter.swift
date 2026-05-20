import Foundation

enum AIResponseTextFormatter {
    static let translationChunkLimit = 3600

    static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func hasTrimmedText(_ text: String) -> Bool {
        !trimmed(text).isEmpty
    }

    static func visibleAnswer(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"(?s)<think>.*?(</think>|$)\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?s)<reasoning>.*?(</reasoning>|$)\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func translationChunks(from text: String) -> [String] {
        let trimmed = trimmed(text)
        guard trimmed.count > translationChunkLimit else { return [trimmed] }

        let paragraphs = trimmed.components(separatedBy: "\n\n")
        guard paragraphs.count > 1 else {
            let midpoint = trimmed.index(trimmed.startIndex, offsetBy: trimmed.count / 2)
            let split = trimmed[midpoint...].firstIndex { ".!?。！？\n".contains($0) } ?? midpoint
            return [
                String(trimmed[..<split]),
                String(trimmed[split...])
            ].map(Self.trimmed)
                .filter { !$0.isEmpty }
        }

        let target = max(1, trimmed.count / 2)
        var first: [String] = []
        var second: [String] = []
        var firstLength = 0
        for paragraph in paragraphs {
            if firstLength < target || second.isEmpty {
                first.append(paragraph)
                firstLength += paragraph.count
            } else {
                second.append(paragraph)
            }
        }
        return [first.joined(separator: "\n\n"), second.joined(separator: "\n\n")]
            .map(Self.trimmed)
            .filter { !$0.isEmpty }
    }

    static func partialTranslationText(_ chunks: [String], currentIndex: Int, generatingText: String) -> String {
        let completed = chunks[..<currentIndex]
            .map(indentedTranslationText)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        if completed.isEmpty { return generatingText }
        return completed + "\n\n" + generatingText
    }

    static func indentedTranslationText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
               .map { line in
                   let trimmed = trimmed(line)
                   guard !trimmed.isEmpty else { return "" }
                   return trimmed
               }
               .joined(separator: "\n")
              .trimmingCharacters(in: .newlines)
   }
}
