import Cocoa
import PDFKit

extension ReaderWindowController {
    @objc func showPDFDisplayModeMenu(_ sender: NSButton) {
        guard currentDocumentKind == .pdf else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false

        let readingMode = currentPDFReadingMode()
        menu.addItem(pdfDisplayModeMenuItem(
            title: AppText.localized("逐页浏览", "Paged"),
            action: #selector(selectPDFPagedMode(_:)),
            isSelected: readingMode == .paged
        ))
        menu.addItem(pdfDisplayModeMenuItem(
            title: AppText.localized("连续垂直滚动", "Continuous Vertical Scroll"),
            action: #selector(selectPDFContinuousMode(_:)),
            isSelected: readingMode == .continuous
        ))
        menu.addItem(.separator())

        let isTwoPage = isPDFTwoPageModeEnabled()
        menu.addItem(pdfDisplayModeMenuItem(
            title: AppText.localized("单页布局", "Single-page Layout"),
            action: #selector(selectPDFSinglePageLayout(_:)),
            isSelected: !isTwoPage
        ))
        menu.addItem(pdfDisplayModeMenuItem(
            title: AppText.localized("双页布局", "Two-page Layout"),
            action: #selector(selectPDFTwoPageLayout(_:)),
            isSelected: isTwoPage
        ))

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc func togglePDFReadingMode() {
        guard currentDocumentKind == .pdf else { return }
        let nextMode: PDFReadingMode = currentPDFReadingMode() == .paged ? .continuous : .paged
        setPDFReadingMode(nextMode)
    }

    @objc private func selectPDFPagedMode(_ sender: Any?) {
        setPDFReadingMode(.paged)
    }

    @objc private func selectPDFContinuousMode(_ sender: Any?) {
        setPDFReadingMode(.continuous)
    }

    @objc func togglePDFPageLayout() {
        guard currentDocumentKind == .pdf else { return }
        setPDFTwoPageLayout(!isPDFTwoPageModeEnabled())
    }

    @objc private func selectPDFSinglePageLayout(_ sender: Any?) {
        setPDFTwoPageLayout(false)
    }

    @objc private func selectPDFTwoPageLayout(_ sender: Any?) {
        setPDFTwoPageLayout(true)
    }

    private func setPDFReadingMode(_ mode: PDFReadingMode) {
        setPDFReadingModePreference(mode)
        applyPDFPageLayout(animated: true)
        saveSession()
        window?.makeFirstResponder(pdfView)
    }

    private func setPDFTwoPageLayout(_ enabled: Bool) {
        setPDFTwoPageModeEnabled(enabled)
        applyPDFPageLayout(animated: true)
        saveSession()
        window?.makeFirstResponder(pdfView)
    }

    func applyPDFPageLayout(animated: Bool) {
        guard currentDocumentKind == .pdf else { return }
        let readingMode = currentPDFReadingMode()
        let isTwoPage = isPDFTwoPageModeEnabled()
        let targetMode: PDFDisplayMode
        switch (readingMode, isTwoPage) {
        case (.paged, false):
            targetMode = .singlePage
        case (.paged, true):
            targetMode = .twoUp
        case (.continuous, false):
            targetMode = .singlePageContinuous
        case (.continuous, true):
            targetMode = .twoUpContinuous
        }

        let viewportAnchor = currentPDFViewportAnchor()
        let anchorPage = viewportAnchor.flatMap { pdfView.document?.page(at: $0.pageIndex) } ?? pdfView.currentPage
        let currentScaleFactor = pdfView.scaleFactor
        let needsDisplayModeChange = pdfView.displayMode != targetMode
        let needsDirectionChange = pdfView.displayDirection != .vertical
        let needsBookModeChange = pdfView.displaysAsBook

        pdfView.allowsEdgePaging = readingMode.allowsEdgePaging
        accumulatedPDFTrackpadScroll = 0
        didTurnPageForCurrentPDFTrackpadGesture = false
        lastPDFTrackpadEdgeDirection = nil

        guard needsDisplayModeChange || needsDirectionChange || needsBookModeChange else {
            updatePDFPageLayoutButton()
            return
        }

        pageLayoutButton?.isEnabled = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? 0.08 : 0
            pdfView.autoScales = false
            pdfView.displayDirection = .vertical
            pdfView.displaysAsBook = false
            pdfView.displayMode = targetMode
            pdfView.scaleFactor = currentScaleFactor
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let anchorPage {
                self.pdfView.go(to: anchorPage)
                if let viewportAnchor {
                    self.pdfView.go(to: PDFDestination(page: anchorPage, at: viewportAnchor.point))
                }
            }
            self.pdfView.scaleFactor = currentScaleFactor
            self.pageLayoutButton?.isEnabled = true
            self.updatePageLabel()
            self.updateZoomLabel()
        }
        updatePDFPageLayoutButton()
    }

    func updatePDFPageLayoutButton() {
        let readingMode = currentPDFReadingMode()
        pageLayoutButton?.title = readingMode == .continuous
            ? AppText.localized("连续", "Scroll")
            : AppText.localized("逐页", "Paged")
        pageLayoutButton?.toolTip = readingMode == .continuous
            ? AppText.localized("当前为连续垂直滚动；点击切换显示模式和页面布局", "Continuous vertical scrolling; click to change display mode and page layout")
            : AppText.localized("当前为逐页浏览；点击切换显示模式和页面布局", "Paged viewing; click to change display mode and page layout")
        setCapsuleButtonSymbol(
            readingMode == .continuous ? "rectangle.stack" : "rectangle",
            on: pageLayoutButton,
            accessibilityDescription: pageLayoutButton?.toolTip ?? ""
        )
    }

    func currentPDFReadingMode() -> PDFReadingMode {
        let defaults = UserDefaults.standard
        let key = pdfReadingModeDefaultsKeyForCurrentBook()
        let rawValue = defaults.string(forKey: key)
            ?? defaults.string(forKey: Self.pdfReadingModeDefaultsKey)
        return rawValue.flatMap(PDFReadingMode.init(rawValue:)) ?? .paged
    }

    func setPDFReadingModePreference(_ mode: PDFReadingMode) {
        let defaults = UserDefaults.standard
        defaults.set(mode.rawValue, forKey: pdfReadingModeDefaultsKeyForCurrentBook())
        defaults.set(mode.rawValue, forKey: Self.pdfReadingModeDefaultsKey)
    }

    func isPDFTwoPageModeEnabled() -> Bool {
        let defaults = UserDefaults.standard
        let key = pdfTwoPageModeDefaultsKeyForCurrentBook()
        if defaults.object(forKey: key) != nil {
            return defaults.bool(forKey: key)
        }
        return defaults.bool(forKey: Self.pdfTwoPageModeDefaultsKey)
    }

    func setPDFTwoPageModeEnabled(_ enabled: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(enabled, forKey: pdfTwoPageModeDefaultsKeyForCurrentBook())
        defaults.set(enabled, forKey: Self.pdfTwoPageModeDefaultsKey)
    }

    func pdfReadingModeDefaultsKeyForCurrentBook() -> String {
        documentScopedPDFPreferenceKey(Self.pdfReadingModeDefaultsKey)
    }

    func pdfTwoPageModeDefaultsKeyForCurrentBook() -> String {
        documentScopedPDFPreferenceKey(Self.pdfTwoPageModeDefaultsKey)
    }

    private func documentScopedPDFPreferenceKey(_ baseKey: String) -> String {
        guard let currentFileMD5, !currentFileMD5.isEmpty else {
            return baseKey
        }
        return "\(baseKey).\(currentFileMD5)"
    }

    private func pdfDisplayModeMenuItem(title: String, action: Selector, isSelected: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = isSelected ? .on : .off
        item.isEnabled = true
        return item
    }
}
