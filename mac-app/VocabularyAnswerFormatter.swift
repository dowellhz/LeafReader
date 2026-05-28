import Foundation

enum VocabularyAnswerFormatter {
    static func answerBody(_ answer: String, word: String) -> String {
        var lines = answer.components(separatedBy: .newlines)
        let normalizedWord = normalizedHeading(word)
        while let first = lines.first {
            let normalizedFirst = normalizedHeading(first)
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

    static func normalizedHeading(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\*\*(.*)\*\*$"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"^__(.*)__$"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ：:"))
            .lowercased()
    }
}
