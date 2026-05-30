import Foundation

enum VocabularyAnswerSanitizer {
    static func removingTrailingTags(from text: String) -> String {
        var lines = text.components(separatedBy: .newlines)
        while let last = lines.last?.trimmingCharacters(in: .whitespacesAndNewlines),
              (last.isEmpty || isTagOnlyLine(last)) {
            lines.removeLast()
        }
        if let last = lines.last {
            lines[lines.count - 1] = removingInlineTrailingTags(from: last)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removingInlineTrailingTags(from line: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(\s+)(?:`?[A-Z0-9+.-]{2,}`?\s*){1,6}$"#) else {
            return line
        }
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, range: fullRange),
              match.range.location != NSNotFound,
              match.range.location > 0 else {
            return line
        }
        let prefix = nsLine.substring(to: match.range.location)
        guard prefix.range(of: #"[。.!?！？）)]$"#, options: .regularExpression) != nil else {
            return line
        }
        return prefix
    }

    private static func isTagOnlyLine(_ line: String) -> Bool {
        let tags = VocabularyTagFormatter.tagValues(from: line)
        guard !tags.isEmpty else { return false }
        let normalized = tags.joined(separator: " ")
        return normalized == line.replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            && tags.allSatisfy { tag in
                tag.range(of: #"^[A-Z0-9+.-]{2,}$"#, options: .regularExpression) != nil
            }
    }
}
