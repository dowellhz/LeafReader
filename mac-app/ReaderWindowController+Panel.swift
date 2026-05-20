import Cocoa
import PDFKit

extension ReaderWindowController {
    @objc func openAISettings() {
        openSettingsPanel(tab: .general)
    }

    @objc func openGeneralSettings() {
        openSettingsPanel(tab: .general)
    }

    @objc func openModelSettings() {
        openSettingsPanel(tab: .model)
    }

    @objc func openVectorSettings() {
        openSettingsPanel(tab: .vector)
    }

    @objc func openCacheSettings() {
        openSettingsPanel(tab: .cache)
    }

    func openSettingsPanel(tab: AISettingsPanelController.SettingsTab) {
        guard let window else { return }
        let controller = AISettingsPanelController()
        controller.onSaved = { [weak self] in
            self?.applySettingsChangesToReader()
        }
        controller.onAppearanceChanged = { [weak self] in
            self?.applySettingsChangesToReader()
        }
        controller.currentVectorIndexStatus = { [weak self] in
            self?.currentVectorIndexStatusText() ?? AppText.noPDF
        }
        controller.onStartVectorIndex = { [weak self] in
            self?.startCurrentVectorIndex()
        }
        controller.onToggleVectorIndexPaused = { [weak self] in
            self?.toggleEmbeddingBackfillPaused()
        }
        controller.onCancelVectorIndex = { [weak self] in
            self?.cancelEmbeddingBackfill()
        }
        controller.onClearCurrentVectorIndex = { [weak self] in
            self?.clearCurrentVectorIndex()
        }
        controller.onClearCurrentWordRecords = { [weak self] in
            self?.clearCurrentBookWordRecords()
        }
        aiSettingsPanelController = controller
        controller.show(attachedTo: window, initialTab: tab)
    }

    func applySettingsChangesToReader() {
        refreshLanguageUI()
        applyReaderTheme()
        applyAIConversationPersistenceSetting()
    }

    @objc func toggleAIPanel() {
        setAIPanelCollapsed(!isAIPanelCollapsed, animated: true)
    }

    func setAIPanelCollapsed(_ collapsed: Bool, animated: Bool) {
        if collapsed == isAIPanelCollapsed {
            if !collapsed {
                aiPanel.setContentVisible(true)
                runPendingAIPanelExpansionAction()
            }
            updateAIHandlePosition()
            return
        }

        if collapsed, aiPanel.frame.width > 80 {
            preferredAIWidth = clampedAIWidth(aiPanel.frame.width)
            savePreferredAIWidth()
        } else {
            preferredAIWidth = clampedAIWidth(preferredAIWidth)
            savePreferredAIWidth()
        }
        isAIPanelCollapsed = collapsed
        aiPanel.isHidden = false
        if collapsed {
            aiPanel.setContentVisible(false)
        }
        aiHandleButton.collapsedStyle = collapsed
        resizeHandle.isHidden = collapsed

        let targetAIWidth: CGFloat = collapsed ? 1 : clampedAIWidth(preferredAIWidth)
        let targetHandleLeading = aiHandleLeadingConstant(collapsed: collapsed, aiWidth: targetAIWidth)
        let applyFinalState = {
            if !collapsed {
                self.aiPanel.setContentVisible(true)
            }
            self.refreshPDFLayoutAfterPanelChange()
            if !collapsed {
                self.runPendingAIPanelExpansionAction()
            }
        }

        if animated {
            contentArea.layoutSubtreeIfNeeded()
            aiPanelWidthConstraint.constant = targetAIWidth
            aiHandleLeadingConstraint.constant = targetHandleLeading
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.contentArea.animator().layoutSubtreeIfNeeded()
                self.window?.contentView?.animator().layoutSubtreeIfNeeded()
            } completionHandler: {
                applyFinalState()
            }
        } else {
            aiPanelWidthConstraint.constant = targetAIWidth
            aiHandleLeadingConstraint.constant = targetHandleLeading
            contentArea.layoutSubtreeIfNeeded()
            window?.contentView?.layoutSubtreeIfNeeded()
            applyFinalState()
        }
    }

    func runPendingAIPanelExpansionAction() {
        guard let action = pendingAIPanelExpansionAction else { return }
        pendingAIPanelExpansionAction = nil
        action()
    }

    func clampedAIWidth(_ width: CGFloat) -> CGFloat {
        let maxWidth = max(300, contentArea.bounds.width - 320)
        return min(max(width, 300), min(520, maxWidth))
    }

    static func loadPreferredAIWidth() -> CGFloat {
        let width = UserDefaults.standard.double(forKey: preferredAIWidthDefaultsKey)
        guard width > 0 else { return 420 }
        return CGFloat(width)
    }

    func savePreferredAIWidth() {
        UserDefaults.standard.set(Double(preferredAIWidth), forKey: Self.preferredAIWidthDefaultsKey)
    }

    func schedulePreferredAIWidthSave() {
        preferredAIWidthSaveTask.schedule { [weak self] in
            self?.savePreferredAIWidth()
        }
    }

    func updateAIHandlePosition() {
        let aiWidth = isAIPanelCollapsed ? 1 : aiPanelWidthConstraint.constant
        aiHandleLeadingConstraint.constant = aiHandleLeadingConstant(collapsed: isAIPanelCollapsed, aiWidth: aiWidth)
        window?.contentView?.layoutSubtreeIfNeeded()
    }

    func aiHandleLeadingConstant(collapsed: Bool, aiWidth: CGFloat) -> CGFloat {
        collapsed ? -SideHandleButton.handleWidth : -(aiWidth + SideHandleButton.handleWidth)
    }

    func refreshPDFLayoutAfterPanelChange() {
        pdfContainer.layoutSubtreeIfNeeded()
        pdfView.layoutSubtreeIfNeeded()
        pdfView.needsDisplay = true
        pdfView.documentView?.needsDisplay = true
    }

    func schedulePDFLayoutAfterPanelResize() {
        aiPanelResizeLayoutTask.schedule { [weak self] in
            guard let self else { return }
            self.contentArea.layoutSubtreeIfNeeded()
            self.refreshPDFLayoutAfterPanelChange()
        }
    }

    func syncAIPanelLayoutAfterResize() {
        guard contentArea.bounds.width > 0 else { return }
        if isAIPanelCollapsed {
            aiPanelWidthConstraint.constant = 1
            aiPanel.setContentVisible(false)
            resizeHandle.isHidden = true
        } else {
            preferredAIWidth = clampedAIWidth(preferredAIWidth)
            aiPanelWidthConstraint.constant = preferredAIWidth
            schedulePreferredAIWidthSave()
            aiPanel.setContentVisible(true)
            resizeHandle.isHidden = false
        }
        aiHandleLeadingConstraint.constant = aiHandleLeadingConstant(
            collapsed: isAIPanelCollapsed,
            aiWidth: isAIPanelCollapsed ? 1 : aiPanelWidthConstraint.constant
        )
        aiHandleButton.isHidden = false
        resizeHandle.isHidden = isAIPanelCollapsed
        windowResizeLayoutTask.schedule { [weak self] in
            guard let self else { return }
            self.contentArea.layoutSubtreeIfNeeded()
            self.refreshPDFLayoutAfterPanelChange()
        }
    }

    func resizeAIPanel(deltaX: CGFloat) {
        guard !isAIPanelCollapsed else { return }
        preferredAIWidth = clampedAIWidth(preferredAIWidth - deltaX)
        schedulePreferredAIWidthSave()
        aiPanelWidthConstraint.constant = preferredAIWidth
        aiHandleLeadingConstraint.constant = aiHandleLeadingConstant(collapsed: false, aiWidth: preferredAIWidth)
        contentArea.needsLayout = true
        window?.contentView?.needsLayout = true
        schedulePDFLayoutAfterPanelResize()
    }

    func finishAIPanelResize() {
        aiPanelResizeLayoutTask.flush()
        preferredAIWidthSaveTask.flush()
    }

    func updateFullScreenButton() {
        let isFullScreen = window?.styleMask.contains(.fullScreen) == true
        fullScreenButton.title = isFullScreen ? AppText.windowed : AppText.fullScreen
        fullScreenButton.image = NSImage(
            systemSymbolName: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
            accessibilityDescription: fullScreenButton.title
        )
    }

    func windowDidResize(_ notification: Notification) {
        hideSelectionToolbar()
        updateFullScreenButton()
        syncAIPanelLayoutAfterResize()
    }

    func windowDidMove(_ notification: Notification) {
        hideSelectionToolbar()
    }

    func windowDidResignKey(_ notification: Notification) {
        hideSelectionToolbar()
    }

    @objc func applicationDidResignActive(_ notification: Notification) {
        hideSelectionToolbar()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        hideSelectionToolbar()
        updateFullScreenButton()
        windowResizeLayoutTask.cancel()
        syncAIPanelLayoutAfterResize()
        windowResizeLayoutTask.flush()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        hideSelectionToolbar()
        updateFullScreenButton()
        windowResizeLayoutTask.cancel()
        syncAIPanelLayoutAfterResize()
        windowResizeLayoutTask.flush()
    }

    func windowWillClose(_ notification: Notification) {
        selectionActionToolbarWindow?.orderOut(nil)
        if let selectionActionToolbarWindow {
            window?.removeChildWindow(selectionActionToolbarWindow)
        }
        selectionActionToolbarWindow = nil
        windowResizeLayoutTask.flush()
        aiPanelResizeLayoutTask.flush()
        preferredAIWidthSaveTask.flush()
        sessionSaveTask.cancel()
        flushCurrentBookWordRecordSaves()
        saveCurrentAIConversationBeforeDocumentChange()
    }
}
