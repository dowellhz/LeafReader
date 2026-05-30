import Foundation

enum ReadingNoteSlashRangePolicy {
    struct Trigger: Equatable {
        let triggerRange: NSRange
        let lineRange: NSRange
        let isLineCommand: Bool
    }

    static func trigger(text: String, selection: NSRange) -> Trigger? {
        let nsText = text as NSString
        let location = min(selection.location, nsText.length)
        guard location > 0,
              nsText.substring(with: NSRange(location: location - 1, length: 1)) == "/" else {
            return nil
        }
        let triggerRange = NSRange(location: location - 1, length: 1)
        let lineRange = currentLineRange(text: text, selection: selection)
        let line = nsText.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
        return Trigger(triggerRange: triggerRange, lineRange: lineRange, isLineCommand: line == "/")
    }

    static func currentLineRange(text: String, selection: NSRange) -> NSRange {
        let nsText = text as NSString
        let location = min(selection.location, nsText.length)
        return nsText.lineRange(for: NSRange(location: max(0, location - 1), length: 0))
    }
}
