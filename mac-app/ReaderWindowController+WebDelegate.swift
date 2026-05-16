import Cocoa
import WebKit

extension ReaderWindowController {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "scrollChanged" {
            guard currentDocumentKind != .pdf else { return }
            markReaderInteraction()
            let progress = message.body as? Double ?? 0
            webScrollProgress = progress
            pageLabel.stringValue = "\(Int(round(progress * 100)))%"
            saveWebProgress()
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
        } else {
            text = (message.body as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            context = ""
        }
        currentWebSelectedText = text.count > 1 ? text : ""
        currentWebSelectionContext = currentWebSelectedText.isEmpty ? "" : context
        aiPanel.setSelectedText(currentWebSelectedText)
        if !currentWebSelectedText.isEmpty {
            setAIPanelCollapsed(false, animated: true)
        }
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
        restoreStoredWebWordHighlights()
        applyWebZoomToPage()
        zoomField.stringValue = "\(webZoomPercent)%"
    }
}
