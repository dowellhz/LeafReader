import Cocoa

enum MarkdownBlockParser {
    struct BlockNode: Equatable {
        let rawLine: String
        let display: String
        let type: MarkdownRenderer.Block
        let isHeading: Bool
        let isBoldLine: Bool
        let isBullet: Bool
        let fontSize: CGFloat
    }

    static func parse(_ text: String, baseFontSize: CGFloat, scalesHeadings: Bool = true) -> [BlockNode] {
        var nodes: [BlockNode] = []
        let lines = text.components(separatedBy: .newlines)
        let trimmedLines = lines.map { $0.trimmingCharacters(in: .whitespaces) }
        let nextNonEmptyLines = nextNonEmptyLineLookup(for: trimmedLines)
        var hasContent = false
        var previousLineWasBlank = false
        var previousNonEmptyLine: String?

        for (index, line) in trimmedLines.enumerated() {
            if line.isEmpty {
                if shouldSkipCompactExplanationBlankLine(previousLine: previousNonEmptyLine, nextLine: nextNonEmptyLines[index]) {
                    continue
                }
                guard hasContent, !previousLineWasBlank else { continue }
                nodes.append(BlockNode(
                    rawLine: "",
                    display: "",
                    type: .paragraph,
                    isHeading: false,
                    isBoldLine: false,
                    isBullet: false,
                    fontSize: baseFontSize
                ))
                previousLineWasBlank = true
                continue
            }
            hasContent = true
            previousLineWasBlank = false
            previousNonEmptyLine = line
            nodes.append(parseLine(line, baseFontSize: baseFontSize, scalesHeadings: scalesHeadings))
        }

        return nodes
    }

    private static func parseLine(_ line: String, baseFontSize: CGFloat, scalesHeadings: Bool) -> BlockNode {
        var display = line
        var isHeading = false
        var fontSize = baseFontSize
        var block: MarkdownRenderer.Block = .paragraph

        if let range = display.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
            let marker = String(display[range]).trimmingCharacters(in: .whitespaces)
            display.removeSubrange(range)
            isHeading = true
            switch marker.count {
            case 1:
                fontSize = scalesHeadings ? baseFontSize + 3 : baseFontSize
                block = .heading1
            case 2:
                fontSize = scalesHeadings ? baseFontSize + 1 : baseFontSize
                block = .heading2
            case 3:
                block = .heading3
            case 4:
                block = .heading4
            case 5:
                block = .heading5
            default:
                block = .heading6
            }
        } else if display.hasPrefix("【"), display.contains("】") {
            isHeading = true
            block = .heading3
        } else if isReadingNoteSectionHeading(display) {
            isHeading = true
            block = .heading3
        }

        let isBullet = display.range(of: #"^[-*]\s+"#, options: .regularExpression) != nil
            || display.range(of: #"^- \[[ xX]\]\s+"#, options: .regularExpression) != nil
            || display.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
        if display.range(of: #"^- \[[ xX]\]\s+"#, options: .regularExpression) != nil {
            block = .checklist
        } else if display.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
            block = .numberedList
        } else if display.range(of: #"^[-*]\s+"#, options: .regularExpression) != nil {
            block = .bullet
        }
        display = display
            .replacingOccurrences(of: #"^- \[ \]\s+"#, with: "☐ ", options: .regularExpression)
            .replacingOccurrences(of: #"^- \[[xX]\]\s+"#, with: "☑ ", options: .regularExpression)
            .replacingOccurrences(of: #"^>\s?"#, with: "", options: .regularExpression)
        display = display
            .replacingOccurrences(of: #"^[-*]\s+"#, with: "• ", options: .regularExpression)

        let trimmed = display.trimmingCharacters(in: .whitespaces)
        return BlockNode(
            rawLine: line,
            display: display,
            type: block,
            isHeading: isHeading,
            isBoldLine: isStandaloneBoldLine(trimmed),
            isBullet: isBullet,
            fontSize: fontSize
        )
    }

    private static func nextNonEmptyLineLookup(for lines: [String]) -> [String?] {
        var lookup = Array<String?>(repeating: nil, count: lines.count)
        var nextLine: String?
        for index in lines.indices.reversed() {
            lookup[index] = nextLine
            if !lines[index].isEmpty {
                nextLine = lines[index]
            }
        }
        return lookup
    }

    private static func shouldSkipCompactExplanationBlankLine(previousLine: String?, nextLine: String?) -> Bool {
        guard let previousLine, let nextLine else {
            return false
        }
        if isStandaloneBoldLine(previousLine) && isStandaloneBoldLine(nextLine) {
            return true
        }
        return isTranslationHeadingLine(nextLine)
    }

    private static func isStandaloneBoldLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return (trimmed.hasPrefix("**") && trimmed.hasSuffix("**") && trimmed.count > 4)
            || (trimmed.hasPrefix("__") && trimmed.hasSuffix("__") && trimmed.count > 4)
    }

    private static func isTranslationHeadingLine(_ line: String) -> Bool {
        let normalized = line
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#*:：: "))
            .lowercased()
        return normalized == "翻译"
            || normalized == "译文"
            || normalized == "translation"
            || normalized == "explanation"
    }

    private static func isReadingNoteSectionHeading(_ line: String) -> Bool {
        let normalized = line
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#*_：: "))
            .lowercased()
        return normalized == "笔记"
            || normalized == "解析"
            || normalized == "翻译"
            || normalized == "总结"
            || normalized == "整理"
            || normalized == "润色"
            || normalized == "notes"
            || normalized == "note"
            || normalized == "explain"
            || normalized == "explanation"
            || normalized == "translate"
            || normalized == "translation"
            || normalized == "summary"
            || normalized == "summarize"
            || normalized == "organize"
            || normalized == "polish"
    }
}
