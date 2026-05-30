import Foundation

enum ReadingNoteMarkdownRenderRangePolicy {
    static func completedLineRangeBeforeCursor(text: String, selection: NSRange) -> NSRange? {
        let nsText = text as NSString
        let cursor = min(selection.location, nsText.length)
        guard cursor > 0 else { return nil }
        let previousLocation = max(0, cursor - 1)
        let previousCharacter = nsText.substring(with: NSRange(location: previousLocation, length: 1))
        let lineLocation = previousCharacter == "\n" ? max(0, previousLocation - 1) : previousLocation
        guard lineLocation < nsText.length else { return nil }
        return nsText.lineRange(for: NSRange(location: lineLocation, length: 0))
    }

    static func pastedParagraphRange(text: String, insertedRange: NSRange) -> NSRange? {
        let nsText = text as NSString
        guard nsText.length > 0 else { return nil }
        let bounded = ReadingNoteTextReplacementPolicy.boundedRange(
            location: insertedRange.location,
            length: insertedRange.length,
            textLength: nsText.length
        )
        return nsText.paragraphRange(for: bounded)
    }
}
