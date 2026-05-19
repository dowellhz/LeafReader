import Cocoa

extension NSText {
    func selectedString() -> String? {
        let range = selectedRange
        guard range.length > 0,
              let textRange = Range(range, in: string) else {
            return nil
        }
        return String(string[textRange])
    }

    @discardableResult
    func copySelectionToClipboard() -> Bool {
        guard let selectedText = selectedString() else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selectedText, forType: .string)
        return true
    }

    @discardableResult
    func pasteStringFromClipboard(transform: (String) -> String = { $0 }) -> Bool {
        guard let text = NSPasteboard.general.string(forType: .string) else { return false }
        replaceCharacters(in: selectedRange, with: transform(text))
        return true
    }
}
