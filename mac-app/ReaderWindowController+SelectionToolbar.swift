import Cocoa
import PDFKit

extension ReaderWindowController {
    enum SelectionToolbarAction {
        case translate
        case explain
        case addWord
        case summarize
        case speak
        case note
        case copy
        case configureModel
    }

    func selectedReaderTextForToolbar() -> String {
        if currentDocumentKind == .pdf {
            return pdfView.currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        return currentWebSelectedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func showSelectionToolbarForPDFSelection(_ selection: PDFSelection, text: String) {
        guard let page = selection.pages.first else {
            hideSelectionToolbar()
            return
        }
        let pageBounds = selection.bounds(for: page)
        guard pageBounds.width > 0, pageBounds.height > 0 else {
            hideSelectionToolbar()
            return
        }
        let viewRect = pdfView.convert(pageBounds, from: page)
        let rectInContent = pdfView.convert(viewRect, to: contentArea)
        showSelectionToolbar(near: rectInContent, text: text)
    }

    func showSelectionToolbarForWebSelection(rect: NSRect?, text: String) {
        guard let rect, rect.width > 0, rect.height > 0 else {
            hideSelectionToolbar()
            return
        }
        showSelectionToolbar(near: rect, text: text, preferredEdge: .below)
    }

    func showSelectionToolbar(near sourceRect: NSRect, text: String, preferredEdge: SelectionToolbarEdge = .above) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            hideSelectionToolbar()
            return
        }
        selectionActionToolbar.applyTheme(ReaderTheme.selected)
        configureSelectionToolbarActions(for: text)
        let size = selectionActionToolbar.preferredSize
        let readerFrame = pdfContainer.frame
        let minimumX = readerFrame.minX + 12
        let maximumX = max(minimumX, readerFrame.maxX - size.width - 12)
        let centeredX = sourceRect.midX - size.width / 2
        let x = min(max(centeredX, minimumX), maximumX)
        let aboveY = sourceRect.maxY + 10
        let belowY = sourceRect.minY - size.height - 10
        let maximumY = readerFrame.maxY - size.height - 12
        let y: CGFloat
        switch preferredEdge {
        case .above:
            y = aboveY <= maximumY ? aboveY : max(readerFrame.minY + 12, belowY)
        case .below:
            y = belowY >= readerFrame.minY + 12 ? belowY : min(aboveY, maximumY)
        }
        showSelectionToolbarWindow(frameInContent: NSRect(origin: CGPoint(x: x, y: y), size: size))
    }

    func hideSelectionToolbar() {
        selectionActionToolbar.isHidden = true
        selectionActionToolbarWindow?.orderOut(nil)
    }

    func runSelectionToolbarAction(_ action: SelectionToolbarAction) {
        let text = selectedReaderTextForToolbar()
        guard text.count > 1 else {
            hideSelectionToolbar()
            NSSound.beep()
            return
        }

        switch action {
        case .translate:
            prepareAIForSelectionAction(text: text)
            aiPanel.translateCurrentContent()
        case .explain:
            prepareAIForSelectionAction(text: text)
            aiPanel.startQuestion()
        case .addWord:
            guard selectionToolbarContextAction(for: text) == .addWord else {
                NSSound.beep()
                return
            }
            prepareAIForSelectionAction(text: text)
            aiPanel.startQuestion()
        case .summarize:
            prepareAIForSelectionAction(text: text)
            aiPanel.summarizeCurrentContent()
        case .speak:
            speakVocabularyTexts([text])
        case .note:
            createReadingNoteFromCurrentSelection(text: text)
        case .copy:
            copyTextToClipboard(text)
        case .configureModel:
            openModelSettings()
        }
        hideSelectionToolbar()
    }

    func selectionToolbarContextAction(for text: String) -> SelectionActionToolbar.ContextAction {
        vocabularySpeakerWord(text) == nil ? .summarize : .addWord
    }

    func configureSelectionToolbarActions(for text: String) {
        let isVocabulary = vocabularySpeakerWord(text) != nil
        let capabilityState = ReaderCapabilityState.make(
            isOnline: NetworkConnectivityMonitor.shared.isOnline,
            hasModelAPIKey: AISettingsStore.hasAPIKeyForSelectedModel,
            isLocalDictionaryInstalled: ECDICTDictionary.shared.isInstalled
        )
        let configuration = SelectionToolbarConfiguration.make(
            isVocabularySelection: isVocabulary,
            queryCapability: capabilityState.queryCapability,
            shouldShowSpeakAction: shouldShowSelectionSpeakAction(for: text)
        )
        selectionActionToolbar.applyConfiguration(configuration)
    }

    @objc func networkConnectivityChanged(_ notification: Notification) {
        guard !selectionActionToolbar.isHidden else { return }
        let text = selectedReaderTextForToolbar()
        guard !text.isEmpty else {
            hideSelectionToolbar()
            return
        }
        if currentDocumentKind == .pdf, let selection = pdfView.currentSelection {
            showSelectionToolbarForPDFSelection(selection, text: text)
            return
        }
        showSelectionToolbarForWebSelection(rect: currentWebSelectionRect, text: text)
    }

    private func shouldShowSelectionSpeakAction(for text: String) -> Bool {
        guard isReadAloudActive else { return true }
        return VocabularyTextPolicy.shouldUseSystemTTSForShortSelection(text)
    }

    private func prepareAIForSelectionAction(text: String) {
        aiPanel.setSelectedText(text)
        setAIPanelCollapsed(false, animated: true)
    }

    private func showSelectionToolbarWindow(frameInContent: NSRect) {
        guard let parentWindow = window else { return }
        let toolbarWindow = selectionActionToolbarWindow ?? makeSelectionToolbarWindow()
        selectionActionToolbarWindow = toolbarWindow
        selectionActionToolbar.frame = NSRect(origin: .zero, size: frameInContent.size)
        selectionActionToolbar.isHidden = false
        if toolbarWindow.parent !== parentWindow {
            toolbarWindow.parent?.removeChildWindow(toolbarWindow)
            parentWindow.addChildWindow(toolbarWindow, ordered: .above)
        }
        let originInWindow = contentArea.convert(frameInContent.origin, to: nil)
        let originOnScreen = parentWindow.convertPoint(toScreen: originInWindow)
        toolbarWindow.setFrame(NSRect(origin: originOnScreen, size: frameInContent.size), display: true)
        toolbarWindow.level = parentWindow.level
        toolbarWindow.orderFront(nil)
    }

    private func makeSelectionToolbarWindow() -> NSWindow {
        let toolbarWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: selectionActionToolbar.preferredSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        toolbarWindow.backgroundColor = .clear
        toolbarWindow.isOpaque = false
        toolbarWindow.hasShadow = false
        toolbarWindow.isReleasedWhenClosed = false
        toolbarWindow.ignoresMouseEvents = false
        toolbarWindow.collectionBehavior = [.fullScreenAuxiliary, .transient]
        toolbarWindow.contentView = selectionActionToolbar
        return toolbarWindow
    }

    enum SelectionToolbarEdge {
        case above
        case below
    }
}
