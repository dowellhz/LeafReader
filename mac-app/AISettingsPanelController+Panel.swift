import Cocoa

extension AISettingsPanelController {
    func showPanel(_ panel: NSWindow, attachedTo parent: NSWindow) {
        ModalOverlayManager.shared.present(panel, attachedTo: parent)
    }

    func installAppActivationObserver() {
        removeAppActivationObserver()
        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            self?.reactivatePanelIfNeeded()
        }
    }

    func removeAppActivationObserver() {
        if let appActivationObserver {
            NotificationCenter.default.removeObserver(appActivationObserver)
            self.appActivationObserver = nil
        }
    }

    func reactivatePanelIfNeeded() {
        guard let panel, panel.isVisible else { return }
        ModalOverlayManager.shared.reactivate(panel)
    }

    @objc func save(_ sender: NSButton) {
        guard let panel else { return }
        guard saveCurrentSettings(in: panel) else { return }
        closePanel(notifySaved: true)
    }

    func saveCurrentSettings(in panel: NSWindow) -> Bool {
        guard let modelPopup, let keyField = secureKeyField else { return false }
        let modelID = modelPopup.selectedItem?.representedObject as? String ?? AISettingsStore.selectedModel.id
        let customEndpoint = customEndpointField?.stringValue ?? ""
        let customModelName = customModelField?.stringValue ?? ""
        if modelID == AISettingsStore.customModelID, let error = AISettingsStore.customValidationError(endpoint: customEndpoint, modelName: customModelName) {
            showValidationAlert(message: error, in: panel)
            return false
        }

        if let rawLanguage = languagePopup?.selectedItem?.representedObject as? String,
           let language = AppText.Language(rawValue: rawLanguage) {
            AppText.selectedLanguage = language
        }
        if let rawTheme = themePopup?.selectedItem?.representedObject as? String,
           let theme = ReaderTheme(rawValue: rawTheme) {
            ReaderTheme.selected = theme
        }
        if let pdfDimmingSlider {
            ReaderTheme.pdfDimmingStrength = pdfDimmingStrength(forBrightnessSliderValue: pdfDimmingSlider.doubleValue)
        }
        AISettingsStore.save(
            modelID: modelID,
            apiKey: keyField.stringValue,
            customEndpoint: customEndpoint,
            customModelName: customModelName
        )
        let embeddingEndpoint = selectedEmbeddingEndpointForSave()?.endpoint ?? (embeddingEndpointField?.stringValue ?? "")
        AISettingsStore.saveEmbedding(
            endpoint: embeddingEndpoint,
            modelName: embeddingModelField?.stringValue ?? "",
            apiKey: embeddingKeyField?.stringValue ?? "",
            optionID: embeddingProviderPopup?.selectedItem?.representedObject as? String
        )
        AISettingsStore.saveSpeakSelectedWordEnabled(speakSelectedWordCheckbox?.state == .on)
        AISettingsStore.saveAIConversationEnabled(saveAIConversationCheckbox?.state == .on)
        AISettingsStore.saveAutoEmbeddingIndexEnabled(autoEmbeddingIndexCheckbox?.state == .on)
        saveSelectedSpeechSettings(
            runtimeID: speechRuntimePopup?.selectedItem?.representedObject as? String,
            voiceID: speechVoicePopup?.selectedItem?.representedObject as? String,
            speedID: speechSpeedPopup?.selectedItem?.representedObject as? String
        )
        return true
    }

    @objc func cancel(_ sender: NSButton) {
        closePanel(notifySaved: false)
    }

    @objc func settingsSegmentChanged(_ sender: NSSegmentedControl) {
        settingsTabChanged(index: sender.selectedSegment)
    }

    func settingsTabChanged(index: Int) {
        (settingsTabControl as? SettingsTabsView)?.selectIndex(index)
        basicPage?.isHidden = index != 0
        modelPage?.isHidden = index != 1
        embeddingPage?.isHidden = index != 2
        speechPage?.isHidden = index != 3
        cachePage?.isHidden = index != 4
        currentIndexStatusLabel?.stringValue = currentVectorIndexStatus?() ?? AppText.noPDF
        if index == 4 {
            refreshVectorCacheStatus()
        }
        if let scrollView = settingsScrollView {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            let allowsScrolling = index == 4
            scrollView.verticalScrollElasticity = allowsScrolling ? .allowed : .none
            scrollView.hasVerticalScroller = allowsScrolling
        }
    }
}
