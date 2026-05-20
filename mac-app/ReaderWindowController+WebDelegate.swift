import Cocoa
import WebKit

extension ReaderWindowController {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "scrollChanged" {
            guard currentDocumentKind != .pdf else { return }
            markReaderInteraction()
            let progress = message.body as? Double ?? 0
            webScrollProgress = progress
            updateWebProgressLabel(progress)
            saveSession()
            return
        }
        if message.name == "webWordClicked" {
            guard currentDocumentKind != .pdf,
                  let linkID = message.body as? String,
                  !linkID.isEmpty else {
                return
            }
            selectStoredLinkedWord(linkID: linkID)
            return
        }
        if message.name == "webAISourceClicked" {
            guard currentDocumentKind != .pdf,
                  let key = message.body as? String,
                  !key.isEmpty else {
                return
            }
            handleWebAISourceClick(key: key)
            return
        }
        guard message.name == "selectionChanged" else { return }
        guard Date() >= suppressSearchSelectionForAIUntil else {
            clearSearchSelectionForAI()
            return
        }
        let text: String
        let context: String
        if let payload = message.body as? [String: Any] {
            text = (payload["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            context = (payload["context"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            currentWebSelectionOccurrenceIndex = payload["occurrenceIndex"] as? Int
            currentWebSelectionRect = webSelectionRect(from: payload["rect"])
        } else {
            text = (message.body as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            context = ""
            currentWebSelectionOccurrenceIndex = nil
            currentWebSelectionRect = nil
        }
        currentWebSelectedText = text.count > 1 ? text : ""
        currentWebSelectionContext = currentWebSelectedText.isEmpty ? "" : context
        if currentWebSelectedText.isEmpty {
            currentWebSelectionOccurrenceIndex = nil
            currentWebSelectionRect = nil
        }
        aiPanel.setSelectedText(currentWebSelectedText)
        if currentWebSelectedText.isEmpty {
            hideSelectionToolbar()
        } else {
            showSelectionToolbarForWebSelection(rect: currentWebSelectionRect, text: currentWebSelectedText)
        }
    }

    func webSelectionRect(from value: Any?) -> NSRect? {
        guard let rect = value as? [String: Any],
              let x = rect["x"] as? Double,
              let y = rect["y"] as? Double,
              let width = rect["width"] as? Double,
              let height = rect["height"] as? Double,
              width > 0,
              height > 0 else {
            return nil
        }
        let viewRect = NSRect(
            x: x,
            y: Double(webView.bounds.height) - y - height,
            width: width,
            height: height
        )
        return webView.convert(viewRect, to: contentArea)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.navigationType == .linkActivated else {
            decisionHandler(.allow)
            return
        }

        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        if url.scheme == "http" || url.scheme == "https" {
            NSWorkspace.shared.open(url)
        } else if let fragment = url.fragment, !fragment.isEmpty {
            webView.evaluateJavaScript("document.getElementById(\(jsStringLiteral(fragment)))?.scrollIntoView({behavior:'smooth', block:'start'});")
        }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard currentDocumentKind != .pdf else { return }
        applyWebReaderTheme()
        restoreStoredWebWordHighlights { [weak self] in
            self?.restoreSavedAISourceUnderlines()
        }
        applyWebZoomToPage()
        zoomField.stringValue = "\(webZoomPercent)%"
    }
}
