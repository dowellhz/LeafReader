import Cocoa
import PDFKit

final class PDFReadAloudBatchBuilder {
    struct Batch {
        let pages: [PDFPage]
        let pageTextCache: [Int: String]
        let segments: [SpeechPlaybackCoordinator.ReadAloudSegment]
        let lastPage: PDFPage
    }

    private weak var pdfView: PDFView?
    private let titleProvider: () -> String

    init(pdfView: PDFView, titleProvider: @escaping () -> String) {
        self.pdfView = pdfView
        self.titleProvider = titleProvider
    }

    func batchFromCurrentScreen(startAtPageTop: Bool, lockedPageIndex: Int?) -> Batch? {
        guard let pdfView,
              let page = startPageForCurrentScreen(lockedPageIndex: lockedPageIndex),
              let pageIndex = pdfView.document?.index(for: page),
              pageIndex != NSNotFound else {
            return nil
        }
        let text = startAtPageTop
            ? textForFullPage(page)
            : textFromVisibleTopToPageEnd(of: page)
        guard let text else { return nil }

        var pages = [page]
        var pageTexts: [PDFReadAloudPageText] = []
        var pageTextCache: [Int: String] = [:]
        pageTextCache[pageIndex] = page.string ?? ""

        if let nextPage = nextPage(after: page),
           let nextPageIndex = pdfView.document?.index(for: nextPage),
           nextPageIndex != NSNotFound,
           let nextText = textForFullPage(nextPage) {
            pages.append(nextPage)
            pageTextCache[nextPageIndex] = nextPage.string ?? ""
            pageTexts.append(Self.pageText(pageIndex: pageIndex, text: text, cache: pageTextCache))
            pageTexts.append(Self.pageText(pageIndex: nextPageIndex, text: nextText, cache: pageTextCache))
        } else {
            pageTexts.append(Self.pageText(pageIndex: pageIndex, text: text, cache: pageTextCache))
        }

        let segments = Self.playbackSegments(from: PDFReadAloudSegmentMatcher.segments(from: pageTexts))
        guard !segments.isEmpty else { return nil }
        return Batch(
            pages: pages,
            pageTextCache: pageTextCache,
            segments: segments,
            lastPage: pages.last ?? page
        )
    }

    func startPageForCurrentScreen(lockedPageIndex: Int?) -> PDFPage? {
        guard let pdfView else { return nil }
        if let lockedPageIndex,
           let document = pdfView.document,
           lockedPageIndex >= 0,
           lockedPageIndex < document.pageCount,
           isPageIndexVisible(lockedPageIndex) {
            return document.page(at: lockedPageIndex)
        }

        guard pdfView.displayMode == .twoUp,
              let document = pdfView.document else {
            return pdfView.currentPage
        }
        let visiblePages = pdfView.visiblePages
            .filter { document.index(for: $0) != NSNotFound }
            .sorted { document.index(for: $0) < document.index(for: $1) }
        return visiblePages.first ?? pdfView.currentPage
    }

    func isPageIndexVisible(_ pageIndex: Int) -> Bool {
        guard let pdfView,
              let document = pdfView.document,
              pageIndex >= 0,
              pageIndex < document.pageCount else {
            return false
        }
        return pdfView.visiblePages.contains { document.index(for: $0) == pageIndex }
    }

    func languageProbeText(pageLimit: Int, lockedPageIndex: Int?) -> String? {
        guard let pdfView,
              pageLimit > 0,
              let document = pdfView.document,
              let startPage = startPageForCurrentScreen(lockedPageIndex: lockedPageIndex) else {
            return pdfView?.currentPage?.string
        }
        let startIndex = document.index(for: startPage)
        guard startIndex != NSNotFound else { return pdfView.currentPage?.string }
        let endIndex = min(document.pageCount, startIndex + pageLimit)
        let text = (startIndex..<endIndex)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func textFromVisibleTopToPageEnd(of page: PDFPage) -> String? {
        guard let pdfView else { return nil }
        let pageBounds = page.bounds(for: pdfView.displayBox)
        let visibleRect = pdfView.convert(pdfView.bounds, to: page)
            .intersection(pageBounds)
        let verticalChromeInset = max(24, pageBounds.height * 0.06)
        let contentTopY = pageBounds.maxY - verticalChromeInset
        let contentBottomY = pageBounds.minY + verticalChromeInset
        let topY = visibleRect.isNull
            ? contentTopY
            : min(max(visibleRect.maxY, contentBottomY), contentTopY)
        let unreadRect = CGRect(
            x: pageBounds.minX,
            y: contentBottomY,
            width: pageBounds.width,
            height: max(0, topY - contentBottomY)
        )
        let selection = unreadRect.width > 0 && unreadRect.height > 0
            ? page.selection(for: unreadRect)
            : nil
        let rawText = selection?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? page.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        let text = strippedChrome(rawText, page: page)
        guard Self.wordCount(in: text) >= 4 else { return nil }
        return text.isEmpty ? nil : text
    }

    private func textForFullPage(_ page: PDFPage) -> String? {
        let rawText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let text = strippedChrome(rawText, page: page)
        guard Self.wordCount(in: text) >= 4 else { return nil }
        return text.isEmpty ? nil : text
    }

    private func strippedChrome(_ text: String, page: PDFPage) -> String {
        guard let document = pdfView?.document else {
            return ReaderAIContextBuilder.stripPDFPageChrome(
                from: text,
                previousText: "",
                nextText: "",
                title: titleProvider()
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let pageIndex = document.index(for: page)
        let previousText = pageIndex > 0 ? document.page(at: pageIndex - 1)?.string ?? "" : ""
        let nextText = pageIndex + 1 < document.pageCount ? document.page(at: pageIndex + 1)?.string ?? "" : ""
        return ReaderAIContextBuilder.stripPDFPageChrome(
            from: text,
            previousText: previousText,
            nextText: nextText,
            title: titleProvider()
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func nextPage(after page: PDFPage) -> PDFPage? {
        guard let document = pdfView?.document else { return nil }
        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound, pageIndex + 1 < document.pageCount else { return nil }
        return document.page(at: pageIndex + 1)
    }

    private static func pageText(pageIndex: Int, text: String, cache: [Int: String]) -> PDFReadAloudPageText {
        PDFReadAloudPageText(
            pageIndex: pageIndex,
            speechSourceText: text,
            fullPageText: cache[pageIndex] ?? text
        )
    }

    private static func playbackSegments(
        from matchedSegments: [PDFReadAloudMatchedSegment]
    ) -> [SpeechPlaybackCoordinator.ReadAloudSegment] {
        matchedSegments.map { segment in
            SpeechPlaybackCoordinator.ReadAloudSegment(
                speechText: segment.speechText,
                displayText: segment.speechText,
                matchText: segment.sourceText,
                matchRange: segment.range,
                pageIndex: segment.pageIndex
            )
        }
    }

    private static func wordCount(in text: String) -> Int {
        text.split { !$0.isLetter && !$0.isNumber }.count
    }
}
