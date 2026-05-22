import Cocoa
import PDFKit

extension ReaderWindowController {
    private static let aiSourceUnderlinePrefix = "ai-source"
    private static let maxAISourceUnderlineLines = 12

    func addAISourceUnderline(for source: AIConversationSourceLocation) {
        if source.kind == .webProgress {
            addWebAISourceUnderline(for: source)
            return
        }
        guard source.kind == .pdfPage,
              let page = pdfView.document?.page(at: source.index),
              let boundsList = source.pdfBounds,
              !boundsList.isEmpty else {
            return
        }

        for (lineIndex, rect) in boundsList.prefix(Self.maxAISourceUnderlineLines).enumerated() {
            let bounds = rect.cgRect.insetBy(dx: -1.5, dy: -1)
            guard !bounds.isEmpty else { continue }
            let key = aiSourceUnderlineKey(source: source, lineIndex: lineIndex, bounds: bounds)
            guard !aiSourceUnderlineKeys.contains(key) else { continue }
            aiSourceUnderlineKeys.insert(key)
            aiSourceLocationsByUnderlineKey[key] = source

            let annotation = PDFAnnotation(bounds: bounds, forType: .underline, withProperties: nil)
            annotation.color = NSColor.systemBlue.withAlphaComponent(0.55)
            annotation.contents = key
            let border = PDFBorder()
            border.lineWidth = 0.5
            annotation.border = border
            page.addAnnotation(annotation)
        }
        pdfView.setNeedsDisplay(pdfView.bounds)
    }

    func restoreSavedAISourceUnderlines(from loadedConversation: SavedAIConversation? = nil) {
        guard AISettingsStore.saveAIConversationEnabled else {
            return
        }
        let conversation = loadedConversation ?? loadedAIConversation ?? aiConversationStore?.load() ?? .empty
        loadedAIConversation = conversation
        if currentDocumentKind != .pdf {
            restoreWebAISourceUnderlines(for: conversation.bubbles.compactMap(\.sourceLocation))
            return
        }
        for bubble in conversation.bubbles {
            guard let source = bubble.sourceLocation else { continue }
            addAISourceUnderline(for: source)
        }
    }

    func clearAISourceUnderlines() {
        if currentDocumentKind != .pdf {
            clearWebAISourceUnderlines()
            clearAISourceUnderlineTracking()
            return
        }
        guard let document = pdfView.document else {
            clearAISourceUnderlineTracking()
            return
        }
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations where isAISourceUnderline(annotation) {
                page.removeAnnotation(annotation)
            }
        }
        clearAISourceUnderlineTracking()
        pdfView.setNeedsDisplay(pdfView.bounds)
    }

    func reconcileAISourceUnderlines(activeSources: [AIConversationSourceLocation]) {
        guard activeSources != activeAISourceUnderlines else { return }
        clearAISourceUnderlines()
        activeAISourceUnderlines = activeSources
        guard AISettingsStore.saveAIConversationEnabled else { return }
        if currentDocumentKind != .pdf {
            restoreWebAISourceUnderlines(for: activeSources)
            return
        }
        for source in activeSources {
            addAISourceUnderline(for: source)
        }
    }

    func aiSourceLocation(at event: NSEvent) -> AIConversationSourceLocation? {
        guard currentDocumentKind == .pdf else { return nil }
        let pointInPDFView = pdfView.convert(event.locationInWindow, from: nil)
        guard let page = pdfView.page(for: pointInPDFView, nearest: false) else { return nil }
        let pointOnPage = pdfView.convert(pointInPDFView, to: page)

        let annotation = page.annotations.first { annotation in
            guard isAISourceUnderline(annotation) else { return false }
            return annotation.bounds.insetBy(dx: -3, dy: -5).contains(pointOnPage)
        }
        guard let key = annotation?.contents else { return nil }
        return aiSourceLocationsByUnderlineKey[key]
    }

    func clearAISourceUnderlineTracking() {
        aiSourceUnderlineKeys.removeAll()
        aiSourceLocationsByUnderlineKey.removeAll()
        webAISourceLocationsByKey.removeAll()
        activeAISourceUnderlines.removeAll()
    }

    func addWebAISourceUnderline(for source: AIConversationSourceLocation) {
        guard currentDocumentKind != .pdf,
              let selectedText = source.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !selectedText.isEmpty else {
            return
        }
        let key = registerWebAISource(source)
        webView.evaluateJavaScript("window.leafReaderAddAISourceUnderlineForSelection && window.leafReaderAddAISourceUnderlineForSelection(\(jsStringLiteral(key)));")
    }

    func restoreWebAISourceUnderlines(for sources: [AIConversationSourceLocation]) {
        webAISourceLocationsByKey.removeAll()
        let payload = sources.compactMap { source -> [String: String]? in
            guard source.kind == .webProgress,
                  let selectedText = source.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !selectedText.isEmpty else {
                return nil
            }
            let key = registerWebAISource(source)
            return [
                "key": key,
                "selectedText": selectedText,
                "context": source.webContext?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        webView.evaluateJavaScript("window.leafReaderRestoreAISourceUnderlines && window.leafReaderRestoreAISourceUnderlines(\(json));")
    }

    func clearWebAISourceUnderlines() {
        guard currentDocumentKind != .pdf else { return }
        webView.evaluateJavaScript("window.leafReaderClearAISourceUnderlines && window.leafReaderClearAISourceUnderlines();")
    }

    func handleWebAISourceClick(key: String) {
        guard currentDocumentKind != .pdf,
              let source = webAISourceLocationsByKey[key] else {
            return
        }
        ensureAIConversationSourceBubbleLoaded(source)
        pendingAIPanelExpansionAction = { [weak self] in
            self?.aiPanel.scrollToConversationSource(source)
        }
        setAIPanelCollapsed(false, animated: true)
    }

    func currentPDFSelectionSourceLocation(pageIndex: Int) -> AIConversationSourceLocation {
        guard AISettingsStore.saveAIConversationEnabled,
              let selection = pdfView.currentSelection,
              let page = pdfView.document?.page(at: pageIndex),
              selection.pages.contains(page) else {
            return AIConversationSourceLocation(kind: .pdfPage, index: pageIndex, progress: nil)
        }

        let selectedText = ReaderAIContextBuilder.normalizeWhitespace(selection.string ?? "")
        let lineBounds = selection
            .selectionsByLine()
            .filter { $0.pages.contains(page) }
            .map { StoredPDFWordRect($0.bounds(for: page)) }
            .filter { !$0.cgRect.isEmpty }
        let source = AIConversationSourceLocation(
            kind: .pdfPage,
            index: pageIndex,
            progress: nil,
            selectedText: selectedText.isEmpty ? nil : selectedText,
            pdfBounds: lineBounds.isEmpty ? nil : lineBounds
        )
        addAISourceUnderline(for: source)
        return source
    }

    private func isAISourceUnderline(_ annotation: PDFAnnotation) -> Bool {
        annotation.contents?.hasPrefix("\(Self.aiSourceUnderlinePrefix):") == true
    }

    private func aiSourceUnderlineKey(source: AIConversationSourceLocation, lineIndex: Int, bounds: CGRect) -> String {
        [
            Self.aiSourceUnderlinePrefix,
            "\(source.index)",
            "\(lineIndex)",
            "\(Int(bounds.minX.rounded()))",
            "\(Int(bounds.minY.rounded()))",
            "\(Int(bounds.width.rounded()))",
            "\(Int(bounds.height.rounded()))"
        ].joined(separator: ":")
    }

    private func registerWebAISource(_ source: AIConversationSourceLocation) -> String {
        if let existing = webAISourceLocationsByKey.first(where: { $0.value == source })?.key {
            return existing
        }
        let key = "web-source-\(UUID().uuidString)"
        webAISourceLocationsByKey[key] = source
        return key
    }
}
