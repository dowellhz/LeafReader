import Cocoa
import PDFKit
import WebKit

extension ReaderWindowController {
    @objc func showSearchOverlay() {
        searchOverlay.isHidden = false
        window?.makeFirstResponder(searchOverlay.searchField)
    }

    func hideSearchOverlay() {
        searchOverlay.isHidden = true
        window?.makeFirstResponder(currentDocumentKind == .pdf ? pdfView : webView)
    }

    func performSearch(_ rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            clearSearchState()
            pdfView.clearSelection()
            clearWebSearchSelection()
            clearSearchSelectionForAI()
            return
        }
        guard currentDocumentKind == .pdf else {
            performWebSearch(query, backwards: false)
            return
        }
        guard let document = pdfView.document else {
            searchOverlay.setResultText("0 / 0")
            return
        }

        if query != lastSearchQuery {
            searchResults = document.findString(query, withOptions: [.caseInsensitive, .diacriticInsensitive])
            searchResultIndex = 0
            lastSearchQuery = query
        } else if !searchResults.isEmpty {
            searchResultIndex = (searchResultIndex + 1) % searchResults.count
        }

        showCurrentSearchResult()
    }

    func clearSearchState() {
        searchResults.removeAll()
        searchResultIndex = 0
        lastSearchQuery = ""
        searchOverlay.setResultText("")
    }

    func goToPreviousSearchResult() {
        guard currentDocumentKind == .pdf else {
            performWebSearch(searchOverlay.searchField.stringValue, backwards: true)
            return
        }
        guard !searchResults.isEmpty else {
            performSearch(searchOverlay.searchField.stringValue)
            return
        }
        searchResultIndex = (searchResultIndex - 1 + searchResults.count) % searchResults.count
        showCurrentSearchResult()
    }

    func goToNextSearchResult() {
        guard currentDocumentKind == .pdf else {
            performWebSearch(searchOverlay.searchField.stringValue, backwards: false)
            return
        }
        guard !searchResults.isEmpty else {
            performSearch(searchOverlay.searchField.stringValue)
            return
        }
        searchResultIndex = (searchResultIndex + 1) % searchResults.count
        showCurrentSearchResult()
    }

    func showCurrentSearchResult() {
        guard !searchResults.isEmpty else {
            searchOverlay.setResultText("0 / 0")
            pdfView.clearSelection()
            clearSearchSelectionForAI()
            return
        }

        let selection = searchResults[searchResultIndex]
        beginSuppressingSearchSelectionForAI()
        pdfView.setCurrentSelection(selection, animate: true)
        let pageIndex = goToVisibleSearchSelection(selection)
        if let pageIndex {
            lastPageIndex = pageIndex
        }
        updatePageLabel()
        saveSession()
        searchOverlay.setResultText("\(searchResultIndex + 1) / \(searchResults.count)")
        clearSearchSelectionForAI()
    }

    @discardableResult
    func goToVisibleSearchSelection(_ selection: PDFSelection) -> Int? {
        guard let page = selection.pages.first else {
            pdfView.go(to: selection)
            return currentPageIndex()
        }

        let selectionBounds = selection.bounds(for: page)
        guard !selectionBounds.isEmpty else {
            pdfView.go(to: selection)
            return currentPageIndex()
        }

        pdfView.go(to: page)
        let pageBounds = page.bounds(for: pdfView.displayBox)
        let overlayClearance = searchOverlay.isHidden ? CGFloat(64) : CGFloat(150)
        let yOffset = overlayClearance / max(pdfView.scaleFactor, 0.1)
        let destinationY = min(pageBounds.maxY, selectionBounds.maxY + yOffset)
        let destination = PDFDestination(
            page: page,
            at: NSPoint(x: max(pageBounds.minX, selectionBounds.minX), y: destinationY)
        )
        pdfView.go(to: destination)
        return pdfView.document?.index(for: page)
    }

    func performWebSearch(_ rawQuery: String, backwards: Bool) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            clearSearchState()
            clearWebSearchSelection()
            clearSearchSelectionForAI()
            return
        }

        beginSuppressingSearchSelectionForAI()
        let escapedQuery = jsStringLiteral(query)
        let reset = query != lastSearchQuery
        lastSearchQuery = query
        let script = """
        (() => {
          const query = \(escapedQuery);
          if (window.leafReaderSearch) {
            return window.leafReaderSearch(query, \(backwards ? "-1" : "1"), \(reset ? "true" : "false"));
          }
          const found = window.find(query, false, \(backwards ? "true" : "false"), true, false, true, false);
          return { index: found ? 1 : 0, total: found ? 1 : 0 };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            let payload = result as? [String: Any]
            let index = payload?["index"] as? Int ?? 0
            let total = payload?["total"] as? Int ?? 0
            self?.searchResultIndex = max(0, index - 1)
            self?.searchOverlay.setResultText(total > 0 ? "\(index) / \(total)" : "0 / 0")
            self?.clearSearchSelectionForAI()
        }
    }

    func beginSuppressingSearchSelectionForAI() {
        suppressSearchSelectionForAIUntil = Date().addingTimeInterval(1.2)
    }

    func clearSearchSelectionForAI() {
        currentWebSelectedText = ""
        currentWebSelectionContext = ""
        currentWebSelectionOccurrenceIndex = nil
        aiPanel.clearSelectedText()
    }

    func clearWebSearchSelection() {
        webView?.evaluateJavaScript("""
            if (window.leafReaderClearSelection) {
              window.leafReaderClearSelection();
            } else if (window.getSelection) {
              window.getSelection().removeAllRanges();
            }
            if (window.leafReaderClearSearchHighlights) {
              window.leafReaderClearSearchHighlights();
            }
        """)
    }

    func jsStringLiteral(_ text: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [text]),
              let encoded = String(data: data, encoding: .utf8),
              encoded.count >= 2 else {
            return "\"\""
        }
        return String(encoded.dropFirst().dropLast())
    }
}
