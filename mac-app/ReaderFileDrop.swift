import Cocoa

enum ReaderFileDrop {
    static let pasteboardTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .URL,
        .string,
        NSPasteboard.PasteboardType("public.url"),
        NSPasteboard.PasteboardType("public.file-url"),
        NSPasteboard.PasteboardType("com.apple.finder.node"),
        NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"),
        NSPasteboard.PasteboardType("NSFilenamesPboardType")
    ]

    static func register(_ view: NSView) {
        view.registerForDraggedTypes(pasteboardTypes)
    }

    static func register(_ window: NSWindow) {
        window.registerForDraggedTypes(pasteboardTypes)
    }

    static func operation(for sender: NSDraggingInfo) -> NSDragOperation {
        canAcceptFileDrag(from: sender.draggingPasteboard) ? .copy : []
    }

    static func perform(_ sender: NSDraggingInfo, open: (URL) -> Void) -> Bool {
        guard let url = supportedFileURL(from: sender.draggingPasteboard) else { return false }
        open(url)
        return true
    }

    private static func canAcceptFileDrag(from pasteboard: NSPasteboard) -> Bool {
        if supportedFileURL(from: pasteboard) != nil {
            return true
        }
        guard let types = pasteboard.types else { return false }
        return types.contains { pasteboardTypes.contains($0) }
    }

    private static func supportedFileURL(from pasteboard: NSPasteboard) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
        if let url = urls.first(where: isSupportedDocumentURL) {
            return url
        }

        if let paths = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String],
           let path = paths.first(where: { isSupportedDocumentURL(URL(fileURLWithPath: $0)) }) {
            return URL(fileURLWithPath: path)
        }

        for type in [.fileURL, NSPasteboard.PasteboardType("public.file-url"), .URL, NSPasteboard.PasteboardType("public.url"), .string] {
            guard let value = pasteboard.string(forType: type) else { continue }
            let candidates = value
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for candidate in candidates {
                let url = URL(string: candidate) ?? URL(fileURLWithPath: candidate)
                if isSupportedDocumentURL(url) {
                    return url
                }
            }
        }

        return nil
    }

    private static func isSupportedDocumentURL(_ url: URL) -> Bool {
        ReaderDocumentKind.kind(for: url) != nil
    }
}
