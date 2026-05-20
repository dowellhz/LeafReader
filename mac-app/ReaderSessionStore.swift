import Cocoa

struct ReaderSessionStore {
    struct PDFProgress {
        let pageIndex: Int
        let scale: CGFloat
        let anchorPoint: CGPoint?
    }

    struct WebProgress {
        let scrollProgress: Double
        let zoomPercent: Int?
    }

    private static let lastBookmarkKey = "lastPDFBookmark"
    private static let pageIndexKey = "pageIndex"
    private static let scaleKey = "scale"
    private static let pdfAnchorXKey = "pdfAnchorX"
    private static let pdfAnchorYKey = "pdfAnchorY"
    private static let webProgressKey = "webProgress"
    private static let webZoomKey = "webZoom"
    private static let farthestPDFPageIndexKey = "farthestPDFPageIndex"
    private static let farthestPDFScaleKey = "farthestPDFScale"
    private static let farthestPDFAnchorXKey = "farthestPDFAnchorX"
    private static let farthestPDFAnchorYKey = "farthestPDFAnchorY"
    private static let farthestWebProgressKey = "farthestWebProgress"
    private static let farthestWebZoomKey = "farthestWebZoom"
    private static let progressKeys = [
        pageIndexKey,
        scaleKey,
        pdfAnchorXKey,
        pdfAnchorYKey,
        webProgressKey,
        webZoomKey,
        farthestPDFPageIndexKey,
        farthestPDFScaleKey,
        farthestPDFAnchorXKey,
        farthestPDFAnchorYKey,
        farthestWebProgressKey,
        farthestWebZoomKey
    ]

    private let fileMD5: String?
    private let defaults: UserDefaults

    init(fileMD5: String?, defaults: UserDefaults = .standard) {
        self.fileMD5 = fileMD5
        self.defaults = defaults
    }

    private func key(_ suffix: String) -> String? {
        guard let fileMD5 else { return nil }
        return "bookSession.\(fileMD5).\(suffix)"
    }

    private func clampedProgress(_ progress: Double) -> Double {
        min(max(progress, 0), 1)
    }

    private func validZoomPercent(_ zoomPercent: Int) -> Int? {
        (60...220).contains(zoomPercent) ? zoomPercent : nil
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
        guard let pageKey = key(Self.pageIndexKey),
              let scaleKey = key(Self.scaleKey),
              defaults.object(forKey: pageKey) != nil else {
            return nil
        }

        let pageIndex = defaults.integer(forKey: pageKey)
        let scale = defaults.double(forKey: scaleKey)
        let anchorPoint: CGPoint?
        if let anchorXKey = key(Self.pdfAnchorXKey),
           let anchorYKey = key(Self.pdfAnchorYKey),
           defaults.object(forKey: anchorXKey) != nil,
           defaults.object(forKey: anchorYKey) != nil {
            anchorPoint = CGPoint(
                x: defaults.double(forKey: anchorXKey),
                y: defaults.double(forKey: anchorYKey)
            )
        } else {
            anchorPoint = nil
        }
        return PDFProgress(pageIndex: pageIndex, scale: CGFloat(scale), anchorPoint: anchorPoint)
    }

    func savePDFProgress(pageIndex: Int, scale: CGFloat, anchorPoint: CGPoint?) {
        guard let pageKey = key(Self.pageIndexKey), let scaleKey = key(Self.scaleKey) else { return }
        defaults.set(pageIndex, forKey: pageKey)
        defaults.set(Double(scale), forKey: scaleKey)
        guard let anchorXKey = key(Self.pdfAnchorXKey), let anchorYKey = key(Self.pdfAnchorYKey) else { return }
        if let anchorPoint {
            defaults.set(Double(anchorPoint.x), forKey: anchorXKey)
            defaults.set(Double(anchorPoint.y), forKey: anchorYKey)
        } else {
            defaults.removeObject(forKey: anchorXKey)
            defaults.removeObject(forKey: anchorYKey)
        }
    }

    func loadFarthestPDFPageIndex() -> Int? {
        guard let key = key(Self.farthestPDFPageIndexKey),
              defaults.object(forKey: key) != nil else {
            return nil
        }
        return defaults.integer(forKey: key)
    }

    func saveFarthestPDFPageIndex(_ pageIndex: Int) {
        saveFarthestPDFProgress(pageIndex: pageIndex, scale: nil, anchorPoint: nil)
    }

    func loadFarthestPDFProgress() -> PDFProgress? {
        guard let pageKey = key(Self.farthestPDFPageIndexKey),
              defaults.object(forKey: pageKey) != nil else {
            return nil
        }

        let pageIndex = defaults.integer(forKey: pageKey)
        let scale: CGFloat
        if let scaleKey = key(Self.farthestPDFScaleKey),
           defaults.object(forKey: scaleKey) != nil {
            scale = CGFloat(defaults.double(forKey: scaleKey))
        } else if let progress = loadPDFProgress(), progress.pageIndex == pageIndex {
            scale = progress.scale
        } else {
            scale = 0
        }

        let anchorPoint: CGPoint?
        if let anchorXKey = key(Self.farthestPDFAnchorXKey),
           let anchorYKey = key(Self.farthestPDFAnchorYKey),
           defaults.object(forKey: anchorXKey) != nil,
           defaults.object(forKey: anchorYKey) != nil {
            anchorPoint = CGPoint(
                x: defaults.double(forKey: anchorXKey),
                y: defaults.double(forKey: anchorYKey)
            )
        } else {
            anchorPoint = nil
        }

        return PDFProgress(pageIndex: pageIndex, scale: scale, anchorPoint: anchorPoint)
    }

    func saveFarthestPDFProgress(pageIndex: Int, scale: CGFloat?, anchorPoint: CGPoint?) {
        guard let pageKey = key(Self.farthestPDFPageIndexKey) else { return }
        let existing = defaults.object(forKey: pageKey).map { _ in defaults.integer(forKey: pageKey) }
        guard existing == nil || pageIndex >= (existing ?? 0) else { return }
        defaults.set(pageIndex, forKey: pageKey)

        if let scaleKey = key(Self.farthestPDFScaleKey) {
            if let scale {
                defaults.set(Double(scale), forKey: scaleKey)
            } else if pageIndex > (existing ?? -1) {
                defaults.removeObject(forKey: scaleKey)
            }
        }
        guard let anchorXKey = key(Self.farthestPDFAnchorXKey),
              let anchorYKey = key(Self.farthestPDFAnchorYKey) else { return }
        if let anchorPoint {
            defaults.set(Double(anchorPoint.x), forKey: anchorXKey)
            defaults.set(Double(anchorPoint.y), forKey: anchorYKey)
        } else if pageIndex > (existing ?? -1) {
            defaults.removeObject(forKey: anchorXKey)
            defaults.removeObject(forKey: anchorYKey)
        }
    }

    func loadWebProgress() -> WebProgress? {
        guard let progressKey = key(Self.webProgressKey),
              defaults.object(forKey: progressKey) != nil else {
            return nil
        }
        let progress = clampedProgress(defaults.double(forKey: progressKey))
        let zoomPercent: Int?
        if let zoomKey = key(Self.webZoomKey) {
            let storedZoom = defaults.integer(forKey: zoomKey)
            zoomPercent = validZoomPercent(storedZoom)
        } else {
            zoomPercent = nil
        }
        return WebProgress(scrollProgress: progress, zoomPercent: zoomPercent)
    }

    func saveWebProgress(scrollProgress: Double, zoomPercent: Int) {
        guard let progressKey = key(Self.webProgressKey), let zoomKey = key(Self.webZoomKey) else { return }
        defaults.set(clampedProgress(scrollProgress), forKey: progressKey)
        defaults.set(zoomPercent, forKey: zoomKey)
    }

    func loadFarthestWebProgress() -> WebProgress? {
        guard let progressKey = key(Self.farthestWebProgressKey),
              defaults.object(forKey: progressKey) != nil else {
            return nil
        }
        let zoomPercent: Int?
        if let zoomKey = key(Self.farthestWebZoomKey) {
            let storedZoom = defaults.integer(forKey: zoomKey)
            zoomPercent = validZoomPercent(storedZoom)
        } else {
            zoomPercent = nil
        }
        return WebProgress(scrollProgress: clampedProgress(defaults.double(forKey: progressKey)), zoomPercent: zoomPercent)
    }

    func saveFarthestWebProgress(_ scrollProgress: Double, zoomPercent: Int? = nil) {
        guard let progressKey = key(Self.farthestWebProgressKey) else { return }
        let progress = clampedProgress(scrollProgress)
        let existing = defaults.object(forKey: progressKey).map { _ in defaults.double(forKey: progressKey) }
        guard existing == nil || progress >= (existing ?? 0) else { return }
        defaults.set(progress, forKey: progressKey)
        guard let zoomPercent, let zoomKey = key(Self.farthestWebZoomKey) else { return }
        defaults.set(zoomPercent, forKey: zoomKey)
    }

    func clearProgress() {
        for suffix in Self.progressKeys {
            guard let key = key(suffix) else { continue }
            defaults.removeObject(forKey: key)
        }
    }
}
