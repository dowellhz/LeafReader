import Cocoa
import PDFKit

extension ReaderWindowController {
    private static let ttsTitlePreviewLimit = 72
    private static let ttsPartialTokenWindowSizes = [12, 10, 8, 6, 4]
    private static let ttsMinimumPartialQueryTokens = 6
    private static let ttsMinimumPartialPageTokens = 4
    private static let temporaryTTSHighlightColor = NSColor(red: 0.56, green: 0.78, blue: 0.49, alpha: 0.32)

    func installKittenTTSProgressObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKittenTTSProgress(_:)),
            name: KittenTTSPlayer.readingSegmentDidChangeNotification,
            object: nil
        )
    }

    @objc private func handleKittenTTSProgress(_ notification: Notification) {
        let isActive = notification.userInfo?["active"] as? Bool ?? false
        guard isActive else {
            restoreTitleAfterKittenTTS()
            return
        }

        if ttsReadingOriginalTitle == nil {
            ttsReadingOriginalTitle = titleLabel.stringValue
            ttsReadingOriginalToolTip = titleLabel.toolTip
        }

        let text = notification.userInfo?["text"] as? String ?? ""
        let index = notification.userInfo?["index"] as? Int
        if let pageIndex = notification.userInfo?["pageIndex"] as? Int {
            turnPDFReadAloudPageIfNeeded(to: pageIndex)
        }
        let preview = Self.ttsTitlePreview(for: text)
        let originalTitle = ttsReadingOriginalTitle ?? titleLabel.stringValue
        titleLabel.stringValue = "\(originalTitle) · \(preview)"
        titleLabel.toolTip = text
        updateTemporaryTTSUnderline(for: text, index: index)
    }

    private func restoreTitleAfterKittenTTS() {
        clearTemporaryTTSUnderline()
        ttsReadingPDFPages.removeAll()
        ttsReadingPDFPageIndex = 0
        ttsReadingPDFSearchLocation = 0
        if let original = ttsReadingOriginalTitle {
            titleLabel.stringValue = original
            ttsReadingOriginalTitle = nil
        }
        titleLabel.toolTip = ttsReadingOriginalToolTip
        ttsReadingOriginalToolTip = nil
    }

    private static func ttsTitlePreview(for text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > ttsTitlePreviewLimit else { return normalized }
        let endIndex = normalized.index(normalized.startIndex, offsetBy: ttsTitlePreviewLimit)
        return String(normalized[..<endIndex]) + "..."
    }

    private func updateTemporaryTTSUnderline(for text: String, index: Int?) {
        clearTemporaryTTSUnderline()
        if currentDocumentKind == .pdf {
            underlinePDFSegment(text)
        } else {
            underlineWebSegment(text, index: index)
        }
    }

    func clearTemporaryTTSUnderline() {
        for item in temporaryTTSUnderlineAnnotations {
            item.page.removeAnnotation(item.annotation)
        }
        temporaryTTSUnderlineAnnotations.removeAll()
        webView?.evaluateJavaScript("window.leafReaderClearTTSUnderline && window.leafReaderClearTTSUnderline();")
    }

    private func underlinePDFSegment(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        let candidatePages = !ttsReadingPDFPages.isEmpty
            ? ttsReadingPDFPages
            : [pdfView.currentPage].compactMap { $0 }
        if underlinePDFSegment(text: query, in: candidatePages, usesCursor: true) {
            return
        }
        _ = underlinePDFSegment(text: query, in: candidatePages, usesCursor: false)
    }

    private func turnPDFReadAloudPageIfNeeded(to pageIndex: Int) {
        guard currentDocumentKind == .pdf,
              let document = pdfView.document,
              pageIndex >= 0,
              pageIndex < document.pageCount,
              currentPageIndex() != pageIndex,
              let page = document.page(at: pageIndex) else {
            return
        }
        let bounds = page.bounds(for: pdfView.displayBox)
        let destination = PDFDestination(page: page, at: NSPoint(x: bounds.minX, y: bounds.maxY))
        pdfView.go(to: destination)
        lastPageIndex = pageIndex
        updatePageLabel()
        saveSession()
    }

    private func underlinePDFSegment(text query: String, in candidatePages: [PDFPage], usesCursor: Bool) -> Bool {
        for (pageIndex, page) in candidatePages.enumerated() {
            if usesCursor, pageIndex < ttsReadingPDFPageIndex {
                continue
            }
            guard let pageText = page.string,
                  let nsRange = Self.ttsRange(
                    of: query,
                    in: pageText,
                    searchRange: usesCursor ? ttsSearchRange(for: pageText, pageIndex: pageIndex) : nil
                  ) else {
                continue
            }
            guard let selection = page.selection(for: nsRange) else { continue }
            var segmentBounds = CGRect.null
            for lineSelection in selection.selectionsByLine() {
                let bounds = lineSelection.bounds(for: page)
                guard bounds.width > 0, bounds.height > 0 else { continue }
                segmentBounds = segmentBounds.union(bounds)
                let annotation = PDFAnnotation(
                    bounds: bounds.insetBy(dx: -1, dy: -1),
                    forType: .highlight,
                    withProperties: nil
                )
                annotation.color = Self.temporaryTTSHighlightColor
                page.addAnnotation(annotation)
                temporaryTTSUnderlineAnnotations.append((page, annotation))
            }
            if !temporaryTTSUnderlineAnnotations.isEmpty {
                ttsReadingPDFPageIndex = pageIndex
                ttsReadingPDFSearchLocation = NSMaxRange(nsRange)
                scrollPDFSegmentToCenter(page: page, bounds: segmentBounds)
                return true
            }
        }
        return false
    }

    private func ttsSearchRange(for pageText: String, pageIndex: Int) -> NSRange {
        let fullRange = NSRange(pageText.startIndex..<pageText.endIndex, in: pageText)
        let start = pageIndex == ttsReadingPDFPageIndex ? ttsReadingPDFSearchLocation : 0
        let location = min(max(0, start), fullRange.length)
        return NSRange(location: location, length: fullRange.length - location)
    }

    private func scrollPDFSegmentToCenter(page: PDFPage, bounds: CGRect) {
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return }
        let pageVisibleRect = pdfView.convert(pdfView.bounds, to: page)
        let target = NSPoint(
            x: max(bounds.minX, pageVisibleRect.minX),
            y: bounds.midY + pageVisibleRect.height * 0.5
        )
        pdfView.go(to: PDFDestination(page: page, at: target))
    }

    private func underlineWebSegment(_ text: String, index: Int?) {
        let segmentIndex = index ?? 0
        let script = """
        (() => {
          if (window.leafReaderUnderlineTTSIndex) {
            return window.leafReaderUnderlineTTSIndex(\(segmentIndex), \(jsStringLiteral(text)));
          }
          return window.leafReaderUnderlineTTS && window.leafReaderUnderlineTTS(\(jsStringLiteral(text)));
        })();
        """
        webView?.evaluateJavaScript(script)
    }

    private static func ttsRange(of query: String, in pageText: String, searchRange: NSRange? = nil) -> NSRange? {
        let fullRange = NSRange(pageText.startIndex..<pageText.endIndex, in: pageText)
        let targetRange = searchRange ?? fullRange
        let exactRange = (pageText as NSString).range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: targetRange,
            locale: nil
        )
        if exactRange.location != NSNotFound {
            return exactRange
        }

        let parts = query
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }

        let pattern = parts
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: #"\s+"#)
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .useUnicodeWordBoundaries]
        ) else {
            return nil
        }
        if let match = regex.firstMatch(in: pageText, range: targetRange)?.range {
            return match
        }
        if let tokenRange = ttsTokenRange(of: query, in: pageText, searchRange: targetRange) {
            return tokenRange
        }
        return ttsPartialTokenRange(of: query, in: pageText, searchRange: targetRange)
    }

    private struct TTSToken {
        let value: String
        let range: NSRange
    }

    private static func ttsTokenRange(of query: String, in pageText: String, searchRange: NSRange) -> NSRange? {
        let queryTokens = ttsTokens(in: query).map(\.value)
        let pageTokens = ttsTokens(in: pageText, searchRange: searchRange)
        return ttsTokenRange(tokens: queryTokens, in: pageTokens)
    }

    private static func ttsPartialTokenRange(of query: String, in pageText: String, searchRange: NSRange) -> NSRange? {
        let queryTokens = ttsTokens(in: query).map(\.value)
        guard queryTokens.count >= ttsMinimumPartialQueryTokens else { return nil }
        let pageTokens = ttsTokens(in: pageText, searchRange: searchRange)
        guard pageTokens.count >= ttsMinimumPartialPageTokens else { return nil }

        for windowSize in ttsPartialTokenWindowSizes {
            guard queryTokens.count >= windowSize else { continue }
            let window = Array(queryTokens.prefix(windowSize))
            if let range = ttsTokenRange(tokens: window, in: pageTokens) {
                return range
            }
        }
        return nil
    }

    private static func ttsTokenRange(tokens queryTokens: [String], in pageTokens: [TTSToken]) -> NSRange? {
        guard !queryTokens.isEmpty, queryTokens.count <= pageTokens.count else {
            return nil
        }
        let lastStart = pageTokens.count - queryTokens.count
        for start in 0...lastStart {
            var matches = true
            for offset in 0..<queryTokens.count where pageTokens[start + offset].value != queryTokens[offset] {
                matches = false
                break
            }
            guard matches else { continue }
            let first = pageTokens[start].range
            let last = pageTokens[start + queryTokens.count - 1].range
            return ttsRange(from: first, through: last)
        }
        return nil
    }

    private static func ttsRange(from first: NSRange, through last: NSRange) -> NSRange {
        NSRange(location: first.location, length: NSMaxRange(last) - first.location)
    }

    private static func ttsTokens(in text: String, searchRange: NSRange? = nil) -> [TTSToken] {
        guard let regex = try? NSRegularExpression(
            pattern: #"[A-Za-z0-9]+"#,
            options: [.useUnicodeWordBoundaries]
        ) else {
            return []
        }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let tokens: [TTSToken] = regex.matches(in: text, range: searchRange ?? fullRange).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let value = String(text[range])
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .lowercased()
            return TTSToken(value: value, range: match.range)
        }
        return ttsTokensMergingLineBreakHyphenation(tokens, in: text)
    }

    private static func ttsTokensMergingLineBreakHyphenation(_ tokens: [TTSToken], in text: String) -> [TTSToken] {
        guard tokens.count >= 2 else { return tokens }
        var merged: [TTSToken] = []
        var index = 0
        while index < tokens.count {
            let current = tokens[index]
            guard index + 1 < tokens.count else {
                merged.append(current)
                break
            }
            let next = tokens[index + 1]
            let separatorRange = NSRange(location: NSMaxRange(current.range), length: next.range.location - NSMaxRange(current.range))
            if separatorRange.length > 0,
               let separator = Range(separatorRange, in: text).map({ String(text[$0]) }),
               shouldMergeTTSTokens(current, next, separatedBy: separator) {
                merged.append(TTSToken(
                    value: current.value + next.value,
                    range: NSRange(location: current.range.location, length: NSMaxRange(next.range) - current.range.location)
                ))
                index += 2
            } else {
                merged.append(current)
                index += 1
            }
        }
        return merged
    }

    private static func shouldMergeTTSTokens(_ current: TTSToken, _ next: TTSToken, separatedBy separator: String) -> Bool {
        if separator.range(of: #"[-\u{2010}-\u{2015}]\s+"#, options: .regularExpression) != nil {
            return true
        }
        let nonDropCapLetters: Set<String> = ["a", "i"]
        return current.value.count == 1
            && !nonDropCapLetters.contains(current.value)
            && next.value.count >= 2
            && separator.range(of: #"^\s+$"#, options: .regularExpression) != nil
    }
}
