import Foundation
import CoreGraphics

enum ReadingNoteTextPolicy {
    struct PDFLine {
        let text: String
        let pageIndex: Int
        let bounds: CGRect

        init(text: String, pageIndex: Int, bounds: CGRect) {
            self.text = text
            self.pageIndex = pageIndex
            self.bounds = bounds
        }
    }

    static func normalizeQuote(_ value: String) -> String {
        let normalizedNewlines = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let paragraphs = splitParagraphs(normalizedNewlines)
        return paragraphs
            .map(normalizeParagraph)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    static func normalizePDFLines(_ lines: [PDFLine]) -> String {
        let cleaned = lines
            .map { PDFLine(text: collapsedSpaces($0.text), pageIndex: $0.pageIndex, bounds: $0.bounds) }
            .filter { !$0.text.isEmpty && !$0.bounds.isEmpty }
        guard !cleaned.isEmpty else { return "" }
        let baselineGap = typicalLineGap(cleaned)
        var paragraphs: [[String]] = [[cleaned[0].text]]
        for index in cleaned.indices.dropFirst() {
            let previous = cleaned[index - 1]
            let current = cleaned[index]
            if isParagraphBreak(previous: previous, current: current, baselineGap: baselineGap) {
                paragraphs.append([current.text])
            } else {
                paragraphs[paragraphs.count - 1].append(current.text)
            }
        }
        return paragraphs
            .map { normalizeParagraph($0.joined(separator: "\n")) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private static func normalizeParagraph(_ value: String) -> String {
        let lines = value
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return "" }
        var output: [String] = []
        for line in lines {
            if shouldStartNewLine(line) || output.last.map(shouldKeepBreakAfter) == true {
                output.append(line)
            } else if let last = output.popLast() {
                output.append(joinSoftLineBreak(previous: last, next: line))
            } else {
                output.append(line)
            }
        }
        return output.joined(separator: "\n")
    }

    private static func joinSoftLineBreak(previous: String, next: String) -> String {
        if previous.hasSuffix("-"),
           let beforeHyphen = previous.dropLast().last,
           beforeHyphen.isLetter,
           next.first?.isLetter == true {
            return String(previous.dropLast()) + next
        }
        if previous.last?.isWhitespace == true || next.first?.isWhitespace == true {
            return previous + next
        }
        return previous + " " + next
    }

    private static func typicalLineGap(_ lines: [PDFLine]) -> CGFloat? {
        let gaps = zip(lines, lines.dropFirst()).compactMap { previous, current -> CGFloat? in
            guard previous.pageIndex == current.pageIndex else { return nil }
            let gap = abs(previous.bounds.midY - current.bounds.midY)
            return gap > 0 ? gap : nil
        }.sorted()
        guard !gaps.isEmpty else { return nil }
        return gaps[(gaps.count - 1) / 2]
    }

    private static func isParagraphBreak(previous: PDFLine, current: PDFLine, baselineGap: CGFloat?) -> Bool {
        guard previous.pageIndex == current.pageIndex else { return true }
        let gap = abs(previous.bounds.midY - current.bounds.midY)
        let normalGap = baselineGap ?? max(previous.bounds.height, current.bounds.height)
        return gap > normalGap * 1.55
    }

    private static func collapsedSpaces(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"[ \t\u{00A0}]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shouldStartNewLine(_ line: String) -> Bool {
        line.range(of: #"^([\-*•]|\d+[.)]|[A-Za-z][.)]|[☐☑])\s+"#, options: .regularExpression) != nil
    }

    private static func shouldKeepBreakAfter(_ line: String) -> Bool {
        shouldStartNewLine(line)
    }

    private static func splitParagraphs(_ value: String) -> [String] {
        var paragraphs: [String] = []
        var current: [String] = []
        for line in value.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !current.isEmpty {
                    paragraphs.append(current.joined(separator: "\n"))
                    current.removeAll()
                }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty {
            paragraphs.append(current.joined(separator: "\n"))
        }
        return paragraphs
    }
}
