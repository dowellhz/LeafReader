import Foundation

struct PaperStructureHeading {
    let title: String
    let level: Int
    let pageIndex: Int
}

enum PaperStructureDetector {
    private static let maximumHeadings = 80

    static func headings(from pages: [(pageIndex: Int, text: String)]) -> [PaperStructureHeading] {
        var results: [PaperStructureHeading] = []
        var seenKeys = Set<String>()

        for page in pages {
            for line in candidateLines(from: page.text) {
                guard let heading = heading(from: line, pageIndex: page.pageIndex) else { continue }
                let key = normalizedKey(heading.title)
                guard !seenKeys.contains(key) else { continue }
                seenKeys.insert(key)
                results.append(heading)
                if results.count >= maximumHeadings {
                    return reliableHeadings(results)
                }
            }
        }
        return reliableHeadings(results)
    }

    private static func candidateLines(from text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func heading(from line: String, pageIndex: Int) -> PaperStructureHeading? {
        let cleaned = cleanedLine(line)
        guard cleaned.count >= 3, cleaned.count <= 96 else { return nil }
        guard !looksLikeSentence(cleaned) else { return nil }

        if let match = numberedHeading(cleaned, pageIndex: pageIndex) {
            return match
        }
        if let match = namedHeading(cleaned, pageIndex: pageIndex) {
            return match
        }
        return nil
    }

    private static func numberedHeading(_ line: String, pageIndex: Int) -> PaperStructureHeading? {
        let pattern = #"^((?:[0-9]+|[IVX]+)(?:\.[0-9]+){0,3})[\.\)]?\s+(.+)$"#
        guard let match = line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let matched = String(line[match])
        let parts = matched.split(maxSplits: 1) { $0 == " " || $0 == "\t" }
        guard parts.count == 2 else { return nil }
        let number = String(parts[0]).trimmingCharacters(in: CharacterSet(charactersIn: ".)"))
        let title = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard isKnownSectionTitle(title) || titleWordCount(title) <= 8 else { return nil }
        let depth = max(0, min(number.split(separator: ".").count - 1, 3))
        return PaperStructureHeading(title: "\(number) \(title)", level: depth, pageIndex: pageIndex)
    }

    private static func namedHeading(_ line: String, pageIndex: Int) -> PaperStructureHeading? {
        let title = line.trimmingCharacters(in: CharacterSet(charactersIn: ".:"))
        guard isKnownSectionTitle(title) else { return nil }
        return PaperStructureHeading(title: title, level: 0, pageIndex: pageIndex)
    }

    private static func isKnownSectionTitle(_ title: String) -> Bool {
        let normalized = normalizedKey(title)
        let exact: Set<String> = [
            "abstract",
            "introduction",
            "background",
            "relatedwork",
            "method",
            "methods",
            "methodology",
            "approach",
            "model",
            "experiments",
            "experiment",
            "experimentalsetup",
            "implementationdetails",
            "results",
            "evaluation",
            "discussion",
            "limitations",
            "conclusion",
            "conclusions",
            "acknowledgements",
            "acknowledgments",
            "references",
            "bibliography",
            "appendix"
        ]
        if exact.contains(normalized) { return true }
        return normalized.hasPrefix("appendix")
            || normalized.hasPrefix("relatedwork")
            || normalized.hasPrefix("experimentalresults")
            || normalized.hasPrefix("ablation")
    }

    private static func reliableHeadings(_ headings: [PaperStructureHeading]) -> [PaperStructureHeading] {
        guard headings.count >= 2 else { return [] }
        let keys = headings.map { normalizedKey($0.title) }
        if keys.contains(where: isNumberedSectionKey) {
            return headings
        }
        if keys.contains("introduction") {
            return headings
        }
        let bodyHeadingCount = keys.filter(isBodySectionKey).count
        return bodyHeadingCount >= 2 ? headings : []
    }

    private static func isNumberedSectionKey(_ key: String) -> Bool {
        key.range(of: #"^[0-9]"#, options: .regularExpression) != nil
    }

    private static func isBodySectionKey(_ key: String) -> Bool {
        let weakSections: Set<String> = [
            "abstract",
            "acknowledgements",
            "acknowledgments",
            "references",
            "bibliography"
        ]
        guard !weakSections.contains(key), !key.hasPrefix("appendix") else { return false }
        return true
    }

    private static func cleanedLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksLikeSentence(_ line: String) -> Bool {
        guard line.count > 40 else { return false }
        return line.hasSuffix(".") || line.hasSuffix(",") || line.hasSuffix(";")
    }

    private static func titleWordCount(_ title: String) -> Int {
        title.split { !$0.isLetter && !$0.isNumber }.count
    }

    private static func normalizedKey(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]"#, with: "", options: .regularExpression)
    }
}
