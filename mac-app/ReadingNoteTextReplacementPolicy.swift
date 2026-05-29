import Foundation

enum ReadingNoteTextReplacementPolicy {
    enum Selection {
        case caretAfterReplacement
        case caret(Int)
        case range(NSRange)
        case adjustedOriginal(NSRange)
    }

    static func selectionRange(
        replacing replacedRange: NSRange,
        replacementLength: Int,
        textLengthAfterReplacement: Int,
        selection: Selection
    ) -> NSRange {
        switch selection {
        case .caretAfterReplacement:
            return boundedRange(location: replacedRange.location + replacementLength, length: 0, textLength: textLengthAfterReplacement)
        case .caret(let location):
            return boundedRange(location: location, length: 0, textLength: textLengthAfterReplacement)
        case .range(let range):
            return boundedRange(location: range.location, length: range.length, textLength: textLengthAfterReplacement)
        case .adjustedOriginal(let original):
            let delta = replacementLength - replacedRange.length
            return boundedRange(location: original.location + delta, length: original.length, textLength: textLengthAfterReplacement)
        }
    }

    static func boundedRange(location: Int, length: Int, textLength: Int) -> NSRange {
        let boundedLocation = min(max(0, location), textLength)
        let boundedLength = min(max(0, length), textLength - boundedLocation)
        return NSRange(location: boundedLocation, length: boundedLength)
    }
}
