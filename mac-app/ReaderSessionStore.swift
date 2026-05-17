import Cocoa

struct ReaderSessionStore {
    struct PDFProgress {
        let pageIndex: Int
        let scale: CGFloat
    }

    struct WebProgress {
        let scrollProgress: Double
        let zoomPercent: Int?
    }

    private static let lastBookmarkKey = "lastPDFBookmark"

    private let fileMD5: String?
    private let defaults: UserDefaults

    init(fileMD5: String?, defaults: UserDefaults = .standard) {
        self.fileMD5 = fileMD5
        self.defaults = defaults
    }

    func key(_ suffix: String) -> String? {
        guard let fileMD5 else { return nil }
        return "bookSession.\(fileMD5).\(suffix)"
    }

    func saveLastDocumentURL(_ url: URL) {
        let bookmark = (try? url.bookmarkData(options: .withSecurityScope)) ?? Data()
        defaults.set(bookmark, forKey: Self.lastBookmarkKey)
    }

    func restoreLastDocumentURL() -> URL? {
        guard let bookmark = defaults.data(forKey: Self.lastBookmarkKey), !bookmark.isEmpty else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            bookmarkDataIsStale: &stale
        ), !stale else {
            return nil
        }
        return url
    }

    func loadPDFProgress() -> PDFProgress? {
        guard let pageKey = key("pageIndex"),
              let scaleKey = key("scale"),
              defaults.object(forKey: pageKey) != nil else {
            return nil
        }

        let pageIndex = defaults.integer(forKey: pageKey)
        let scale = defaults.double(forKey: scaleKey)
        return PDFProgress(pageIndex: pageIndex, scale: CGFloat(scale))
    }

    func savePDFProgress(pageIndex: Int, scale: CGFloat) {
        guard let pageKey = key("pageIndex"), let scaleKey = key("scale") else { return }
        defaults.set(pageIndex, forKey: pageKey)
        defaults.set(Double(scale), forKey: scaleKey)
    }

    func loadWebProgress() -> WebProgress? {
        guard let progressKey = key("webProgress") else { return nil }
        let progress = min(max(defaults.double(forKey: progressKey), 0), 1)
        let zoomPercent: Int?
        if let zoomKey = key("webZoom") {
            let storedZoom = defaults.integer(forKey: zoomKey)
            zoomPercent = (60...220).contains(storedZoom) ? storedZoom : nil
        } else {
            zoomPercent = nil
        }
        return WebProgress(scrollProgress: progress, zoomPercent: zoomPercent)
    }

    func saveWebProgress(scrollProgress: Double, zoomPercent: Int) {
        guard let progressKey = key("webProgress"), let zoomKey = key("webZoom") else { return }
        defaults.set(scrollProgress, forKey: progressKey)
        defaults.set(zoomPercent, forKey: zoomKey)
    }

    func clearProgress() {
        for suffix in ["pageIndex", "scale", "webProgress", "webZoom"] {
            guard let key = key(suffix) else { continue }
            defaults.removeObject(forKey: key)
        }
    }
}
