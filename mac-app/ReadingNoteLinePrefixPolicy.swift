import Foundation

enum ReadingNoteLinePrefixPolicy {
    struct Replacement: Equatable {
        let range: NSRange
        let text: String
        let selection: NSRange
    }

    static func replacement(text: String, selection: NSRange, displayPrefix: String) -> Replacement? {
        let nsText = text as NSString
        guard selection.length > 0 else {
            let location = min(selection.location, nsText.length)
            let insertPrefix = location == 0 || nsText.substring(to: location).hasSuffix("\n") ? "" : "\n"
            return Replacement(
                range: NSRange(location: location, length: 0),
                text: insertPrefix + displayPrefix,
                selection: NSRange(location: location + (insertPrefix + displayPrefix as NSString).length, length: 0)
            )
        }

        let paragraphRange = nsText.paragraphRange(for: selection)
        let selected = nsText.substring(with: paragraphRange) as NSString
        let shouldRemovePrefix = selectionAlreadyUsesPrefix(displayPrefix, in: selected)
        var offset = 0
        let replacement = NSMutableString()
        selected.enumerateSubstrings(
            in: NSRange(location: 0, length: selected.length),
            options: [.byParagraphs, .substringNotRequired]
        ) { _, lineRange, enclosingRange, _ in
            let line = selected.substring(with: lineRange)
            let enclosing = selected.substring(with: enclosingRange)
            let newlineSuffix = String(enclosing.dropFirst(line.count))
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                replacement.append(line + newlineSuffix)
            } else if shouldRemovePrefix {
                let updated = removingLinePrefix(displayPrefix, from: line)
                replacement.append(updated + newlineSuffix)
                offset -= line.count - updated.count
            } else if lineAlreadyUsesListPrefix(trimmed) {
                replacement.append(line + newlineSuffix)
            } else {
                replacement.append(displayPrefix + line + newlineSuffix)
                offset += displayPrefix.count
            }
        }

        let oldLocation = selection.location
        let oldEnd = selection.location + selection.length
        let newLocation = oldLocation + (oldLocation == paragraphRange.location ? 0 : displayPrefix.count)
        let newLength = max(0, oldEnd - oldLocation + offset)
        return Replacement(
            range: paragraphRange,
            text: replacement as String,
            selection: NSRange(location: newLocation, length: newLength)
        )
    }

    private static func selectionAlreadyUsesPrefix(_ displayPrefix: String, in selected: NSString) -> Bool {
        selectedNonEmptyLines(in: selected).allSatisfy { lineHasPrefix(displayPrefix, $0) }
    }

    private static func selectedNonEmptyLines(in selected: NSString) -> [String] {
        var lines: [String] = []
        selected.enumerateSubstrings(
            in: NSRange(location: 0, length: selected.length),
            options: [.byParagraphs, .substringNotRequired]
        ) { _, lineRange, _, _ in
            let line = selected.substring(with: lineRange)
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append(line)
            }
        }
        return lines
    }

    private static func lineHasPrefix(_ displayPrefix: String, _ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix(displayPrefix)
    }

    private static func lineAlreadyUsesListPrefix(_ trimmedLine: String) -> Bool {
        trimmedLine.hasPrefix("• ") || trimmedLine.hasPrefix("☐ ") || trimmedLine.hasPrefix("☑ ")
    }

    private static func removingLinePrefix(_ displayPrefix: String, from line: String) -> String {
        let leadingWhitespace = line.prefix { $0 == " " || $0 == "\t" }
        let remainder = line.dropFirst(leadingWhitespace.count)
        guard remainder.hasPrefix(displayPrefix) else { return line }
        return String(leadingWhitespace) + String(remainder.dropFirst(displayPrefix.count))
    }
}
