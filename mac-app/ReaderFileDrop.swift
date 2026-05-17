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

    static func perform(_ sender: NSDraggingInfo, open: ([URL]) -> Void) -> Bool {
        let urls = supportedFileURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        open(urls)
        return true
    }

    private static func canAcceptFileDrag(from pasteboard: NSPasteboard) -> Bool {
        if !supportedFileURLs(from: pasteboard).isEmpty {
            return true
        }
        guard let types = pasteboard.types else { return false }
        return types.contains { pasteboardTypes.contains($0) }
    }

    private static func supportedFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        var results: [URL] = []
        var seenPaths = Set<String>()

        func append(_ url: URL) {
            let fileURL = url.isFileURL ? url : URL(fileURLWithPath: url.path)
            guard isSupportedDocumentURL(fileURL) else { return }
            let path = fileURL.standardizedFileURL.path
            guard !seenPaths.contains(path) else { return }
            seenPaths.insert(path)
            results.append(fileURL)
        }

        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
        for url in urls {
            append(url)
        }

        if let paths = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            for path in paths {
                append(URL(fileURLWithPath: path))
            }
        }

        for type in [.fileURL, NSPasteboard.PasteboardType("public.file-url"), .URL, NSPasteboard.PasteboardType("public.url"), .string] {
            guard let value = pasteboard.string(forType: type) else { continue }
            let candidates = value
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for candidate in candidates {
                let url = URL(string: candidate) ?? URL(fileURLWithPath: candidate)
                append(url)
            }
        }

        return results
    }

    private static func isSupportedDocumentURL(_ url: URL) -> Bool {
        ReaderDocumentKind.kind(for: url) != nil
    }
}
