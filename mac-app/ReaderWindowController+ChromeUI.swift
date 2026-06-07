import Cocoa

extension ReaderWindowController {
    func configureLoadingOverlay() {
        loadingOverlay.translatesAutoresizingMaskIntoConstraints = false
        loadingOverlay.isHidden = true
        loadingOverlay.wantsLayer = true
        loadingOverlay.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.86).cgColor

        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .regular
        loadingIndicator.isDisplayedWhenStopped = false

        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        loadingLabel.font = AppFont.semibold(ofSize: 13)
        loadingLabel.textColor = NSColor(red: 0.32, green: 0.36, blue: 0.44, alpha: 1)
        loadingLabel.alignment = .center
        loadingLabel.lineBreakMode = .byTruncatingMiddle

        loadingOverlay.addSubview(loadingIndicator)
        loadingOverlay.addSubview(loadingLabel)
    }

    func iconButton(symbol: String, action: Selector) -> NSButton {
        let button = NSButton(title: "", target: self, action: action)
        button.isBordered = false
        setSystemImage(symbol, on: button)
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = ReaderTheme.selected.primaryTextColor
        return button
    }

    func plainButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.font = AppFont.semibold(ofSize: 18)
        return button
    }

    func capsuleButton(title: String, symbol: String, action: Selector, showsLeadingSymbol: Bool = false) -> NSButton {
        let button = CapsuleChromeButton(title: title, target: self, action: action)
        button.identifier = Self.capsuleButtonIdentifier
        button.controlSize = .regular
        button.font = AppFont.semibold(ofSize: 13)
        button.theme = ReaderTheme.selected
        if showsLeadingSymbol {
            setCapsuleButtonSymbol(symbol, on: button, accessibilityDescription: title)
        }
        return button
    }

    func setCapsuleButtonSymbol(_ symbol: String, on button: NSButton, accessibilityDescription: String) {
        if let capsule = button as? CapsuleChromeButton {
            capsule.leadingSymbolName = symbol
            capsule.leadingSymbolDescription = accessibilityDescription
        } else {
            setSystemImage(symbol, on: button, accessibilityDescription: accessibilityDescription)
        }
    }

    func setSystemImage(_ symbol: String, on button: NSButton, accessibilityDescription: String? = nil) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibilityDescription)
        if button.image == nil, button.title.isEmpty {
            button.title = accessibilityDescription ?? ""
        }
    }

    func divider() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = toolbarBorderColor(for: ReaderTheme.selected).cgColor
        return view
    }

    func refreshLanguageUI() {
        (NSApp.delegate as? AppDelegate)?.refreshMainMenu()
        aiPanel.refreshLanguage()
        fullScreenButton.title = window?.styleMask.contains(.fullScreen) == true ? AppText.windowed : AppText.fullScreen
        coverButton.title = AppText.cover
        tocButton.title = AppText.localized("目录", "TOC")
        recentButton.title = AppText.localized("书架", "Shelf")
        notesButton.title = AppText.localized("笔记", "Notes")
        vocabularyButton.title = AppText.localized("背单词", "Vocab")
        prevButton.title = AppText.prev
        nextButton.title = AppText.next
        farthestPositionButton.title = AppText.localized("上次位置", "Last")
        selectionActionToolbar.refreshLanguage()
        selectionActionToolbar.applyTheme(ReaderTheme.selected)
        refreshEmbeddingStatusLanguage()
        updatePDFPageLayoutButton()
        updatePDFMarginCropButton()
        for button in [coverButton, tocButton, recentButton, notesButton, vocabularyButton, prevButton, nextButton, farthestPositionButton, pageLayoutButton, cropButton] {
            if let capsule = button as? CapsuleChromeButton {
                capsule.theme = ReaderTheme.selected
            }
        }
        if pdfView.document == nil {
            pageLabel.stringValue = AppText.noPDF
            updatePageLabelTextColor()
        }
        fullScreenButton.image = NSImage(
            systemSymbolName: window?.styleMask.contains(.fullScreen) == true ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
            accessibilityDescription: fullScreenButton.title
        )
    }
}
