import Cocoa
import PDFKit
import WebKit

private enum ReaderInputPolicy {
    static let aiSourceClickSelectionDelay: TimeInterval = 0.18
    static let aiSourceClickScrollDelay: TimeInterval = 0.08
}

extension ReaderWindowController {
    func installKeyboardPagingMonitor() {
        guard localEventMonitor == nil else { return }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel, .leftMouseDown]) { [weak self] event in
            guard let self = self, event.window === self.window else { return event }
            switch event.type {
            case .keyDown:
                guard self.handlePageKey(event) else { return event }
                return nil
            case .scrollWheel:
                self.markReaderInteraction()
                DispatchQueue.main.async { [weak self] in
                    self?.updateZoomLabel()
                }
                guard self.handlePDFTrackpadScroll(event) else { return event }
                return nil
            case .leftMouseDown:
                if self.handleStoredWordClick(event) {
                    return nil
                }
                if self.handleAISourceUnderlineClick(event) {
                    return nil
                }
                self.clearAISelectionIfClickingReader(event)
                self.hideSearchOverlayIfClickingReader(event)
                return event
            default:
                return event
            }
        }
    }

    func handleStoredWordClick(_ event: NSEvent) -> Bool {
        guard isMouseEventInsidePDFArea(event),
              let linkID = storedWordID(at: event) else {
            return false
        }
        selectStoredLinkedWord(linkID: linkID)
        return true
    }

    func handleAISourceUnderlineClick(_ event: NSEvent) -> Bool {
        guard isMouseEventInsidePDFArea(event),
              let source = aiSourceLocation(at: event) else {
            return false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + ReaderInputPolicy.aiSourceClickSelectionDelay) { [weak self] in
            guard let self else { return }
            let selectedText = self.pdfView.currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard selectedText.isEmpty else { return }
            self.setAIPanelCollapsed(false, animated: true)
            self.ensureAIConversationSourceBubbleLoaded(source)
            DispatchQueue.main.asyncAfter(deadline: .now() + ReaderInputPolicy.aiSourceClickScrollDelay) { [weak self] in
                self?.aiPanel.scrollToConversationSource(source)
            }
        }
        return false
    }

    func clearAISelectionIfClickingReader(_ event: NSEvent) {
        guard isMouseEventInsidePDFArea(event) else { return }
        clearAISelectionForNavigation()
    }

    func hideSearchOverlayIfClickingReader(_ event: NSEvent) {
        guard !searchOverlay.isHidden else { return }

        let pointInContent = contentArea.convert(event.locationInWindow, from: nil)
        guard contentArea.bounds.contains(pointInContent) else { return }

        let pointInSearch = searchOverlay.convert(event.locationInWindow, from: nil)
        guard !searchOverlay.bounds.contains(pointInSearch) else { return }

        hideSearchOverlay()
    }

    func handlePDFTrackpadScroll(_ event: NSEvent) -> Bool {
        guard currentDocumentKind == .pdf,
              event.hasPreciseScrollingDeltas,
              abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
              abs(event.scrollingDeltaY) > 0,
              isMouseEventInsidePDFArea(event) else {
            return false
        }

        guard let edgeDirection = pdfTrackpadPageDirectionAtEdge(for: event) else {
            accumulatedPDFTrackpadScroll = 0
            didTurnPageForCurrentPDFTrackpadGesture = false
            lastPDFTrackpadEdgeDirection = nil
            return false
        }

        guard event.momentumPhase == [] else { return true }

        if event.phase == .began {
            accumulatedPDFTrackpadScroll = 0
            didTurnPageForCurrentPDFTrackpadGesture = false
            lastPDFTrackpadEdgeDirection = nil
        }

        if event.phase == .ended || event.phase == .cancelled {
            accumulatedPDFTrackpadScroll = 0
            didTurnPageForCurrentPDFTrackpadGesture = false
            lastPDFTrackpadEdgeDirection = nil
            return true
        }

        guard !didTurnPageForCurrentPDFTrackpadGesture else { return true }

        if let lastDirection = lastPDFTrackpadEdgeDirection, lastDirection != edgeDirection {
            accumulatedPDFTrackpadScroll = 0
        }
        lastPDFTrackpadEdgeDirection = edgeDirection

        accumulatedPDFTrackpadScroll += abs(event.scrollingDeltaY)
        let threshold = pdfTrackpadPageTurnThreshold()
        guard abs(accumulatedPDFTrackpadScroll) >= threshold else { return true }

        let now = Date()
        guard now.timeIntervalSince(lastPDFTrackpadPageTurn) > PDFPagingPolicy.trackpadPageTurnCooldown else {
            accumulatedPDFTrackpadScroll = 0
            return true
        }

        lastPDFTrackpadPageTurn = now
        accumulatedPDFTrackpadScroll = 0
        didTurnPageForCurrentPDFTrackpadGesture = true
        lastPDFTrackpadEdgeDirection = nil
        turnPageFromScroll(edgeDirection)
        return true
    }

    func pdfTrackpadPageDirectionAtEdge(for event: NSEvent) -> EdgePagingPDFView.ScrollPageDirection? {
        guard let scrollView = firstScrollView(in: pdfView) else {
            return nil
        }
        let clipView = scrollView.contentView
        guard let documentView = scrollView.documentView else {
            return nil
        }
        let clipHeight = clipView.bounds.height
        let documentHeight = documentView.bounds.height
        guard documentHeight > clipHeight + PDFPagingPolicy.documentSizeTolerance else {
            return nil
        }

        let scrollerValue = scrollView.verticalScroller?.doubleValue
        let isAtTop = clipView.bounds.minY <= PDFPagingPolicy.trackpadEdgeSlop
            || scrollerValue.map { $0 <= PDFPagingPolicy.trackpadScrollerTopLimit } == true
        let isAtBottom = clipView.bounds.maxY >= documentHeight - PDFPagingPolicy.trackpadEdgeSlop
            || scrollerValue.map { $0 >= PDFPagingPolicy.trackpadScrollerBottomLimit } == true

        if isAtTop, event.scrollingDeltaY > 0 {
            return .previous
        }
        if isAtBottom, event.scrollingDeltaY < 0 {
            return .next
        }
        return nil
    }

    func pdfTrackpadPageTurnThreshold() -> CGFloat {
        guard let scrollView = firstScrollView(in: pdfView),
              let documentView = scrollView.documentView else {
            return PDFPagingPolicy.trackpadFallbackPageTurnThreshold
        }
        let clipHeight = scrollView.contentView.bounds.height
        let documentHeight = documentView.bounds.height
        return PDFPagingPolicy.trackpadPageTurnThreshold(clipHeight: clipHeight, documentHeight: documentHeight)
    }

    func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let scrollView = firstScrollView(in: subview) {
                return scrollView
            }
        }
        return nil
    }

    func isMouseEventInsidePDFArea(_ event: NSEvent) -> Bool {
        let pointInWindow = event.locationInWindow
        let point = pdfContainer.convert(pointInWindow, from: nil)
        return pdfContainer.bounds.contains(point)
    }

    func handlePageKey(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "f" {
            showSearchOverlay()
            return true
        }
        if handleReaderCommandShortcut(event) {
            return true
        }

        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .option, .control]
        guard event.modifierFlags.intersection(disallowedModifiers).isEmpty else { return false }
        guard !isEditingTextInput else { return false }

        switch event.keyCode {
        case 123:
            prevPage()
            return true
        case 124:
            nextPage()
            return true
        default:
            return false
        }
    }

    func handleReaderCommandShortcut(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              event.modifierFlags.intersection([.option, .control]).isEmpty,
              !isEditingTextInput,
              !isFirstResponderInsideAIView,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        switch key {
        case "a":
            selectAllReaderContent()
            return true
        case "c":
            copyReaderSelectionToClipboard()
            return true
        default:
            return false
        }
    }

    func selectAllReaderContent() {
        if currentDocumentKind == .pdf {
            guard let page = pdfView.currentPage,
                  let selection = page.selection(for: page.bounds(for: pdfView.displayBox)) else {
                return
            }
            pdfView.setCurrentSelection(selection, animate: false)
            selectionChanged()
            return
        }

        webView.evaluateJavaScript("""
        (() => {
          const viewportTop = 0;
          const viewportBottom = window.innerHeight || document.documentElement.clientHeight || 0;
          const viewportLeft = 0;
          const viewportRight = window.innerWidth || document.documentElement.clientWidth || 0;
          const isVisibleRect = (rect) =>
            rect.width > 0 &&
            rect.height > 0 &&
            rect.bottom >= viewportTop &&
            rect.top <= viewportBottom &&
            rect.right >= viewportLeft &&
            rect.left <= viewportRight;
          const isSelectableTextNode = (node) => {
            if (!node.nodeValue || !node.nodeValue.trim()) return false;
            const parent = node.parentElement;
            if (!parent) return false;
            const style = window.getComputedStyle(parent);
            if (style.display === 'none' || style.visibility === 'hidden') return false;
            const range = document.createRange();
            range.selectNodeContents(node);
            const visible = Array.from(range.getClientRects()).some(isVisibleRect);
            range.detach?.();
            return visible;
          };
          const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
            acceptNode: (node) => isSelectableTextNode(node)
              ? NodeFilter.FILTER_ACCEPT
              : NodeFilter.FILTER_REJECT
          });
          let first = null;
          let last = null;
          let node;
          while ((node = walker.nextNode())) {
            if (!first) first = node;
            last = node;
          }
          const selection = window.getSelection();
          selection.removeAllRanges();
          if (!first || !last) return "";
          const range = document.createRange();
          range.setStart(first, 0);
          range.setEnd(last, last.nodeValue.length);
          selection.addRange(range);
          return String(selection || "");
        })();
        """) { [weak self] result, _ in
            let text = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self?.currentWebSelectedText = text.count > 1 ? text : ""
            self?.currentWebSelectionContext = text
            self?.aiPanel.setSelectedText(self?.currentWebSelectedText ?? "")
        }
    }

    func copyReaderSelectionToClipboard() {
        if currentDocumentKind == .pdf {
            copyTextToClipboard(pdfView.currentSelection?.string)
            return
        }

        webView.evaluateJavaScript("String(window.getSelection ? window.getSelection() : '')") { [weak self] result, _ in
            let text = result as? String
            self?.copyTextToClipboard(text)
        }
    }

    func copyTextToClipboard(_ text: String?) {
        let value = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    var isFirstResponderInsideAIView: Bool {
        guard let responder = window?.firstResponder as? NSView else { return false }
        return responder === aiPanel || responder.isDescendant(of: aiPanel)
    }

    var isEditingTextInput: Bool {
        guard let responder = window?.firstResponder else { return false }
        if let textView = responder as? NSTextView {
            return textView.isEditable
        }
        if let textField = responder as? NSTextField {
            return textField.isEditable
        }
        return false
    }
}
