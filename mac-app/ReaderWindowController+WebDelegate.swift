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
        if message.name == "webNoteClicked" {
            guard currentDocumentKind != .pdf,
                  let noteID = message.body as? String,
                  let note = storedReadingNotes.first(where: { $0.id == noteID }) else {
                return
            }
            openReadingNotePanel(note)
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
        selectionCoordinator.handleWebSelectionChanged(body: message.body)
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
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        let navigationURL = url.isFileURL ? url.standardizedFileURL.absoluteString : url.absoluteString
        let isApprovedInitialNavigation = navigationAction.navigationType == .other
            && navigationAction.targetFrame?.isMainFrame == true
            && allowedInitialWebNavigationURLs.contains(navigationURL)
        if isApprovedInitialNavigation {
            allowedInitialWebNavigationURLs.removeAll()
        }
        let policy = WebDocumentNavigationPolicy.decision(
            for: url,
            isUserActivatedLink: navigationAction.navigationType == .linkActivated,
            isApprovedInitialNavigation: isApprovedInitialNavigation
        )
        switch policy {
        case .allow:
            decisionHandler(.allow)
        case .cancel:
            decisionHandler(.cancel)
        case .openExternally:
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        case .scrollToFragment(let fragment):
            webView.evaluateJavaScript("document.getElementById(\(jsStringLiteral(fragment)))?.scrollIntoView({behavior:'smooth', block:'start'});")
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard currentDocumentKind != .pdf else { return }
        applyWebReaderTheme()
        restoreStoredWebWordHighlights { [weak self] in
            self?.restoreWebReadingNoteHighlights {
                self?.restoreSavedAISourceUnderlines()
            }
        }
        applyWebZoomToPage()
        zoomField.stringValue = "\(webZoomPercent)%"
        applyPendingWebProgressRestoreIfReady()
    }
}
