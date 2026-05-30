import Foundation

struct ReadingNoteAIMarkdownImageProtector {
    struct ImagePlaceholder: Equatable {
        let placeholder: String
        let markdown: String
    }

    struct ProtectedMarkdown {
        let markdown: String
        let placeholders: [ImagePlaceholder]

        var isEmpty: Bool {
            placeholders.isEmpty
        }
    }

    static func protect(_ markdown: String) -> ProtectedMarkdown {
        var placeholders: [ImagePlaceholder] = []
        var protectedLines: [String] = []
        var imageIndex = 1

        for line in markdown.components(separatedBy: .newlines) {
            if isImageMarkdownLine(line) {
                let placeholder = "[[LEAF_IMAGE_\(imageIndex)]]"
                placeholders.append(ImagePlaceholder(placeholder: placeholder, markdown: line))
                protectedLines.append(placeholder)
                imageIndex += 1
            } else {
                protectedLines.append(line)
            }
        }

        return ProtectedMarkdown(
            markdown: protectedLines.joined(separator: "\n"),
            placeholders: placeholders
        )
    }

    static func restore(_ markdown: String, protected: ProtectedMarkdown) -> String {
        var restored = markdown
        var missingImages: [String] = []
        for item in protected.placeholders {
            if restored.contains(item.placeholder) {
                restored = restored.replacingOccurrences(of: item.placeholder, with: item.markdown)
            } else {
                missingImages.append(item.markdown)
            }
        }
        guard !missingImages.isEmpty else { return restored }
        let suffix = restored.hasSuffix("\n") || restored.isEmpty ? "" : "\n\n"
        return restored + suffix + missingImages.joined(separator: "\n")
    }

    private static func isImageMarkdownLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("![") else { return false }
        return trimmed.range(of: #"^!\[[^\]]*\]\([^)]+\)$"#, options: .regularExpression) != nil
    }
}
