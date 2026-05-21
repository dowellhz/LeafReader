import Cocoa

extension AISettingsPanelController {
    func show(attachedTo window: NSWindow, initialTab: SettingsTab = .general) {
        parentWindow = window
        let selectedModel = AISettingsStore.selectedModel
        let selectedEmbeddingEndpoint = AISettingsStore.selectedEmbeddingEndpointOption
        currentEmbeddingOptionID = selectedEmbeddingEndpoint.id
        pendingEmbeddingKeys[selectedEmbeddingEndpoint.id] = AISettingsStore.embeddingAPIKeyMigratingLegacyIfNeeded(for: selectedEmbeddingEndpoint.id)
        if selectedEmbeddingEndpoint.id == AISettingsStore.customEmbeddingEndpointID {
            lastCustomEmbeddingEndpoint = selectedEmbeddingEndpoint.endpoint
            lastCustomEmbeddingModel = AISettingsStore.embeddingModelName
        }
        let settingsFontSize: CGFloat = 14
        let theme = ReaderTheme.selected
        let isDark = theme == .dark
        let panelBackground: NSColor
        let primaryText: NSColor
        let secondaryText: NSColor
        switch theme {
        case .original:
            panelBackground = .white
            primaryText = NSColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1)
            secondaryText = NSColor(red: 0.47, green: 0.50, blue: 0.58, alpha: 1)
        case .eyeCare:
            panelBackground = NSColor(red: 0.91, green: 0.87, blue: 0.74, alpha: 1)
            primaryText = NSColor(red: 0.15, green: 0.13, blue: 0.09, alpha: 1)
            secondaryText = NSColor(red: 0.45, green: 0.39, blue: 0.27, alpha: 1)
        case .dark:
            panelBackground = NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1)
            primaryText = NSColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1)
            secondaryText = NSColor(red: 0.58, green: 0.63, blue: 0.70, alpha: 1)
        }
        let formBackground = settingsFormBackgroundColor(for: theme)
        let layout = AISettingsLayoutMetrics()

        let panel = makeSettingsPanel(isDark: isDark)
        let content = makeSettingsContentView(panel: panel, isDark: isDark, backgroundColor: panelBackground)

        let titleIcon = settingsTitleIcon(primaryText: primaryText)
        let titleLabel = label(AppText.settings, size: 22, weight: .semibold, color: primaryText)
        let closeButton = NSButton(title: "", target: self, action: #selector(cancel(_:)))
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: AppText.close)
        closeButton.isBordered = false
        closeButton.contentTintColor = primaryText
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let tabControl = SettingsTabsView(
            labels: [
            AppText.localized("基础", "General"),
            AppText.localized("模型", "Model"),
            AppText.localized("AI 分析", "AI Analysis"),
            AppText.localized("朗读", "Read Aloud"),
            AppText.localized("缓存", "Cache")
            ],
            selectedIndex: initialTab.rawValue
        )
        tabControl.onSelectionChanged = { [weak self] index in
            self?.settingsTabChanged(index: index)
        }
        tabControl.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.verticalScrollElasticity = .allowed
        scrollView.horizontalScrollElasticity = .none
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.wantsLayer = true
        scrollView.layer?.backgroundColor = formBackground.cgColor
        scrollView.layer?.borderWidth = 1
        scrollView.layer?.borderColor = settingsBorderColor(for: theme).cgColor
        scrollView.layer?.cornerRadius = 12
        scrollView.layer?.masksToBounds = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentView = VerticalOnlyClipView()
        scrollView.contentView.drawsBackground = true
        scrollView.contentView.backgroundColor = formBackground

        let formContent = NSView()
        formContent.wantsLayer = true
        formContent.layer?.backgroundColor = formBackground.cgColor
        formContent.translatesAutoresizingMaskIntoConstraints = false
        formContent.setContentHuggingPriority(.required, for: .horizontal)
        formContent.setContentCompressionResistancePriority(.required, for: .horizontal)
        scrollView.documentView = formContent

        let basicPage = themedPage(backgroundColor: formBackground)
        let modelPage = themedPage(backgroundColor: formBackground)
        let embeddingPage = themedPage(backgroundColor: formBackground)
        let speechPage = themedPage(backgroundColor: formBackground)
        let cachePage = themedPage(backgroundColor: formBackground)
        for page in [basicPage, modelPage, embeddingPage, speechPage, cachePage] {
            formContent.addSubview(page)
        }
        modelPage.isHidden = true
        embeddingPage.isHidden = true
        speechPage.isHidden = true
        cachePage.isHidden = true

        let modelLabel = label(AppText.model, size: settingsFontSize, weight: .semibold, color: primaryText)
        let modelHelpLabel = label(AppText.modelHelp, size: settingsFontSize, color: secondaryText)
        modelHelpLabel.isHidden = true
        let modelPopup = popup(
            items: AISettingsStore.models.map { ($0.displayName, $0.id) },
            selected: selectedModel.id,
            fontSize: settingsFontSize
        )

        let customEndpointLabel = label(AppText.localized("自定义 / Azure URL", "Custom / Azure URL"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let customEndpointField = inputField(AISettingsStore.customEndpointString, placeholder: "https://resource.openai.azure.com/openai/deployments/deployment/chat/completions?api-version=2024-10-21", fontSize: settingsFontSize, textColor: primaryText, backgroundColor: fieldBackground())
        let customModelLabel = label(AppText.localized("模型 ID / Azure 部署名", "Model ID / Azure Deployment"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let customModelField = inputField(AISettingsStore.customModelName, placeholder: "gpt-4o-mini", fontSize: settingsFontSize, textColor: primaryText, backgroundColor: fieldBackground())
        let customModelContainer = settingsCard()

        let keyLabel = label("API Key", size: settingsFontSize, weight: .semibold, color: primaryText)
        let keyHelpLabel = label(AppText.keyHelp, size: settingsFontSize, color: secondaryText)
        keyHelpLabel.isHidden = true
        let keyField = APIKeySecureTextField(string: AISettingsStore.apiKey(for: selectedModel))
        configureKeyField(keyField, placeholder: AppText.apiKeyPlaceholder, fontSize: settingsFontSize, textColor: primaryText, backgroundColor: fieldBackground())

        let languageLabel = label(AppText.language, size: settingsFontSize, weight: .semibold, color: primaryText)
        let languageHelpLabel = label(AppText.languageHelp, size: settingsFontSize, color: secondaryText)
        languageHelpLabel.isHidden = true
        let languagePopup = popup(items: AppText.Language.allCases.map { ($0.title, $0.rawValue) }, selected: AppText.selectedLanguage.rawValue, fontSize: settingsFontSize)

        let themeLabel = label(AppText.localized("模式", "Mode"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let themeHelpLabel = label(ReaderTheme.selected.helpText, size: settingsFontSize, color: secondaryText)
        themeHelpLabel.isHidden = true
        let themePopup = popup(items: ReaderTheme.allCases.map { ($0.title, $0.rawValue) }, selected: ReaderTheme.selected.rawValue, fontSize: settingsFontSize)
        let pdfDimmingLabel = label(AppText.localized("阅读区亮度", "Reading Area Brightness"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let pdfDimmingSlider = ThemedSettingsSlider(value: pdfBrightnessSliderValue(forDimmingStrength: ReaderTheme.pdfDimmingStrength), minValue: 0, maxValue: Self.pdfBrightnessSliderMaximum)
        pdfDimmingSlider.theme = theme
        pdfDimmingSlider.numberOfTickMarks = 7
        pdfDimmingSlider.target = self
        pdfDimmingSlider.action = #selector(pdfDimmingSliderChanged(_:))
        pdfDimmingSlider.translatesAutoresizingMaskIntoConstraints = false
        let speakSelectedWordLabel = label(AppText.localized("自动播放单词", "Auto Play Words"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let speakSelectedWordCheckbox = settingsCheckbox(isOn: AISettingsStore.speakSelectedWordEnabled, theme: theme, fontSize: settingsFontSize)
        let saveAIConversationLabel = label(AppText.localized("保存 AI 对话信息", "Save AI Chat"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let saveAIConversationCheckbox = settingsCheckbox(isOn: AISettingsStore.saveAIConversationEnabled, theme: theme, fontSize: settingsFontSize)

        let embeddingLabel = label(AppText.localized("向量服务", "Embedding Service"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let embeddingProviderPopup = popup(items: AISettingsStore.embeddingEndpointOptions.map { ($0.title, $0.id) }, selected: selectedEmbeddingEndpoint.id, fontSize: settingsFontSize)
        let embeddingEndpointLabel = label(AppText.localized("接口 URL", "Endpoint URL"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let embeddingEndpointField = inputField(AISettingsStore.embeddingEndpointString, placeholder: "https://api.openai.com/v1/embeddings", fontSize: settingsFontSize, textColor: primaryText, backgroundColor: fieldBackground())
        let embeddingEndpointContainer = settingsCard()
        let embeddingModelNameLabel = label(AppText.localized("向量模型", "Embedding Model"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let embeddingModelField = inputField(AISettingsStore.embeddingModelName, placeholder: AISettingsStore.fallbackEmbeddingModelName, fontSize: settingsFontSize, textColor: primaryText, backgroundColor: fieldBackground())
        let embeddingKeyLabel = label(AppText.localized("向量 API Key", "Embedding API Key"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let embeddingKeyField = APIKeySecureTextField(string: AISettingsStore.embeddingAPIKeyMigratingLegacyIfNeeded(for: selectedEmbeddingEndpoint.id))
        configureKeyField(embeddingKeyField, placeholder: AppText.apiKeyPlaceholder, fontSize: settingsFontSize, textColor: primaryText, backgroundColor: fieldBackground())
        let embeddingHelpLabel = label(AppText.localized("用于 PDF、EPUB 和 DOCX 向量检索。聊天模型和向量模型可以使用不同 API Key。默认使用 OpenAI text-embedding-3-small，也可填兼容接口。", "Used for PDF, EPUB, and DOCX vector retrieval. Chat and embedding models can use different API keys. Defaults to OpenAI text-embedding-3-small; compatible endpoints can be used."), size: settingsFontSize, color: secondaryText)
        let autoEmbeddingIndexCheckbox = settingsCheckbox(
            title: AppText.localized("打开书后自动生成 AI 分析数据", "Automatically build AI analysis data after opening a book"),
            isOn: AISettingsStore.autoEmbeddingIndexEnabled,
            theme: theme,
            fontSize: settingsFontSize
        )
        let speechLabel = label(AppText.localized("朗读", "Read Aloud"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let speechRuntimeLabel = label(AppText.localized("朗读模型", "TTS Model"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let speechRuntimePopup = popup(
            items: SpeechRuntimeResourceManager.Runtime.displayOrder.map { ($0.title, $0.id) },
            selected: AISettingsStore.selectedSpeechRuntimeID,
            fontSize: settingsFontSize
        )
        speechRuntimePopup.target = self
        speechRuntimePopup.action = #selector(speechRuntimeChanged(_:))
        let speechSpeedLabel = label(AppText.localized("语速", "Speed"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let speechSpeedPopup = popup(
            items: AISettingsStore.speechSpeedOptions.map { ($0.title, $0.id) },
            selected: AISettingsStore.selectedSpeechSpeedID,
            fontSize: settingsFontSize
        )
        speechSpeedPopup.target = self
        speechSpeedPopup.action = #selector(speechSpeedChanged(_:))
        let kokoroSpeechCard = settingsSpeechRowCard()
        let kittenSpeechCard = settingsSpeechRowCard()
        let kokoroSpeechLabel = label("Kokoro", size: settingsFontSize, weight: .semibold, color: primaryText)
        let kokoroSpeechStatusLabel = label(SpeechRuntimeResourceManager.statusText(for: .kokoro), size: settingsFontSize, color: secondaryText)
        let kokoroSpeechProgressIndicator = speechDownloadProgressIndicator()
        let kokoroSpeechDownloadButton = settingsActionButton(
            title: AppText.localized("下载 Kokoro", "Download Kokoro"),
            target: self,
            action: #selector(downloadKokoroSpeechRuntime(_:))
        )
        let kokoroSpeechPauseButton = settingsActionButton(
            title: AppText.localized("暂停", "Pause"),
            target: self,
            action: #selector(pauseKokoroSpeechRuntimeDownload(_:))
        )
        let kokoroSpeechCancelButton = settingsActionButton(
            title: AppText.localized("取消", "Cancel"),
            target: self,
            action: #selector(cancelKokoroSpeechRuntimeDownload(_:))
        )
        let kokoroSpeechDeleteButton = settingsActionButton(
            title: AppText.localized("删除", "Delete"),
            target: self,
            action: #selector(deleteKokoroSpeechRuntime(_:))
        )
        let kittenSpeechLabel = label("KittenTTS", size: settingsFontSize, weight: .semibold, color: primaryText)
        let kittenSpeechStatusLabel = label(SpeechRuntimeResourceManager.statusText(for: .kitten), size: settingsFontSize, color: secondaryText)
        let kittenSpeechProgressIndicator = speechDownloadProgressIndicator()
        let kittenSpeechDownloadButton = settingsActionButton(
            title: AppText.localized("下载 Kitten", "Download Kitten"),
            target: self,
            action: #selector(downloadKittenSpeechRuntime(_:))
        )
        let kittenSpeechPauseButton = settingsActionButton(
            title: AppText.localized("暂停", "Pause"),
            target: self,
            action: #selector(pauseKittenSpeechRuntimeDownload(_:))
        )
        let kittenSpeechCancelButton = settingsActionButton(
            title: AppText.localized("取消", "Cancel"),
            target: self,
            action: #selector(cancelKittenSpeechRuntimeDownload(_:))
        )
        let kittenSpeechDeleteButton = settingsActionButton(
            title: AppText.localized("删除", "Delete"),
            target: self,
            action: #selector(deleteKittenSpeechRuntime(_:))
        )
        kokoroSpeechDeleteButton.isEnabled = SpeechRuntimeResourceManager.isInstalled(.kokoro)
        kittenSpeechDeleteButton.isEnabled = SpeechRuntimeResourceManager.isInstalled(.kitten)
        kokoroSpeechProgressIndicator.isHidden = !SpeechRuntimeResourceManager.isDownloading(.kokoro)
        kittenSpeechProgressIndicator.isHidden = !SpeechRuntimeResourceManager.isDownloading(.kitten)
        kokoroSpeechDownloadButton.isHidden = SpeechRuntimeResourceManager.isInstalled(.kokoro) || SpeechRuntimeResourceManager.isDownloading(.kokoro)
        kittenSpeechDownloadButton.isHidden = SpeechRuntimeResourceManager.isInstalled(.kitten) || SpeechRuntimeResourceManager.isDownloading(.kitten)
        kokoroSpeechPauseButton.isHidden = !SpeechRuntimeResourceManager.isDownloading(.kokoro)
        kittenSpeechPauseButton.isHidden = !SpeechRuntimeResourceManager.isDownloading(.kitten)
        kokoroSpeechCancelButton.isHidden = !SpeechRuntimeResourceManager.isDownloading(.kokoro)
        kittenSpeechCancelButton.isHidden = !SpeechRuntimeResourceManager.isDownloading(.kitten)
        kokoroSpeechDeleteButton.isHidden = !SpeechRuntimeResourceManager.isInstalled(.kokoro)
        kittenSpeechDeleteButton.isHidden = !SpeechRuntimeResourceManager.isInstalled(.kitten)

        let testChatButton = settingsActionButton(title: AppText.localized("测试模型连接", "Test Chat"), target: self, action: #selector(testChatConnection(_:)))
        testChatButton.font = AppFont.semibold(ofSize: settingsFontSize)
        let testEmbeddingButton = settingsActionButton(title: AppText.localized("测试向量连接", "Test Embedding"), target: self, action: #selector(testEmbeddingConnection(_:)))
        testEmbeddingButton.font = AppFont.semibold(ofSize: settingsFontSize)

        let cacheLabel = label(AppText.localized("AI 阅读记录", "AI Reading Records"), size: 15, weight: .semibold, color: primaryText)
        let cacheStatusLabel = label(AppText.localized("正在统计缓存...", "Calculating cache..."), size: settingsFontSize, color: secondaryText)
        let cacheDisclosureButton = NSButton(title: "", target: self, action: #selector(clearVectorCache(_:)))
        cacheDisclosureButton.isBordered = false
        cacheDisclosureButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        cacheDisclosureButton.contentTintColor = primaryText
        cacheDisclosureButton.isHidden = true
        cacheDisclosureButton.translatesAutoresizingMaskIntoConstraints = false
        let clearVectorCacheButton = cacheActionButton(
            title: AppText.localized("清除 AI 阅读记录", "Clear AI Reading Records"),
            symbol: "trash",
            tint: NSColor(red: 1.00, green: 0.16, blue: 0.18, alpha: 1),
            target: self,
            action: #selector(clearVectorCache(_:))
        )
        clearVectorCacheButton.layer?.cornerRadius = 8
        clearVectorCacheButton.font = AppFont.semibold(ofSize: 14)
        clearVectorCacheButton.attributedTitle = NSAttributedString(
            string: AppText.localized("清除 AI 阅读记录", "Clear AI Reading Records"),
            attributes: [
                .font: AppFont.semibold(ofSize: 14),
                .foregroundColor: primaryText
            ]
        )

        let currentIndexLabel = label(AppText.localized("当前书 AI 分析数据", "Current Book AI Analysis Data"), size: 15, weight: .semibold, color: primaryText)
        let currentIndexStatusLabel = label(currentVectorIndexStatus?() ?? AppText.noPDF, size: settingsFontSize, color: secondaryText)
        currentIndexStatusLabel.maximumNumberOfLines = 2
        currentIndexStatusLabel.lineBreakMode = .byWordWrapping
        let startIndexButton = cacheActionButton(title: AppText.localized("重分析本书", "Reanalyze Book"), symbol: "play.circle", tint: NSColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1), target: self, action: #selector(startCurrentVectorIndex(_:)))
        let pauseIndexButton = cacheActionButton(title: AppText.localized("暂停/继续", "Pause / Resume"), symbol: "pause.circle", tint: NSColor(red: 1.00, green: 0.58, blue: 0.00, alpha: 1), target: self, action: #selector(toggleCurrentVectorIndex(_:)))
        let cancelIndexButton = cacheActionButton(title: AppText.localized("取消分析", "Cancel"), symbol: "minus.circle", tint: NSColor(red: 1.00, green: 0.22, blue: 0.28, alpha: 1), target: self, action: #selector(cancelCurrentVectorIndex(_:)))
        let clearCurrentIndexButton = cacheActionButton(title: AppText.localized("清除本书缓存", "Clear Book Cache"), symbol: "paintbrush", tint: NSColor(red: 0.60, green: 0.27, blue: 1.00, alpha: 1), target: self, action: #selector(clearCurrentVectorIndex(_:)))
        let clearCurrentWordsButton = cacheActionButton(title: AppText.localized("清除当前书单词记录", "Clear Current Book Words"), symbol: "trash", tint: NSColor(red: 0.00, green: 0.72, blue: 0.74, alpha: 1), target: self, action: #selector(clearCurrentWordRecords(_:)))
        let currentIndexCard = settingsCard()
        let vectorCacheCard = settingsCard()

        let cancelButton = settingsActionButton(title: AppText.cancel, target: self, action: #selector(cancel(_:)))
        let saveButton = settingsActionButton(title: AppText.confirm, target: self, action: #selector(save(_:)), isPrimary: true)
        saveButton.keyEquivalent = "\r"

        modelPopup.target = self
        modelPopup.action = #selector(modelChanged(_:))
        themePopup.target = self
        themePopup.action = #selector(themeChanged(_:))
        embeddingProviderPopup.target = self
        embeddingProviderPopup.action = #selector(embeddingProviderChanged(_:))
        modelPopup.identifier = Identifiers.modelPopup
        languagePopup.identifier = Identifiers.languagePopup
        themePopup.identifier = Identifiers.themePopup
        keyField.identifier = Identifiers.keyField
        embeddingProviderPopup.identifier = Identifiers.embeddingProviderPopup
        embeddingEndpointField.identifier = Identifiers.embeddingEndpointField
        embeddingModelField.identifier = Identifiers.embeddingModelField
        embeddingKeyField.identifier = Identifiers.embeddingKeyField

        for view in [titleIcon, titleLabel, closeButton, tabControl, scrollView, cancelButton, saveButton] {
            content.addSubview(view)
        }
        for view in [customEndpointLabel, customEndpointField, customModelLabel, customModelField] {
            customModelContainer.addSubview(view)
        }
        for view in [embeddingEndpointLabel, embeddingEndpointField] {
            embeddingEndpointContainer.addSubview(view)
        }
        for view in [currentIndexLabel, currentIndexStatusLabel, startIndexButton, pauseIndexButton, cancelIndexButton, clearCurrentIndexButton, clearCurrentWordsButton] {
            currentIndexCard.addSubview(view)
        }
        for view in [cacheLabel, cacheStatusLabel, cacheDisclosureButton, clearVectorCacheButton] {
            vectorCacheCard.addSubview(view)
        }
        for view in [languageLabel, languagePopup, languageHelpLabel, themeLabel, themePopup, themeHelpLabel, pdfDimmingLabel, pdfDimmingSlider, speakSelectedWordLabel, speakSelectedWordCheckbox, saveAIConversationLabel, saveAIConversationCheckbox] {
            basicPage.addSubview(view)
        }
        for view in [modelLabel, modelPopup, modelHelpLabel, customModelContainer, keyLabel, keyField, keyHelpLabel, testChatButton] {
            modelPage.addSubview(view)
        }
        for view in [embeddingLabel, embeddingProviderPopup, embeddingEndpointContainer, embeddingModelNameLabel, embeddingModelField, embeddingKeyLabel, embeddingKeyField, embeddingHelpLabel, autoEmbeddingIndexCheckbox, testEmbeddingButton] {
            embeddingPage.addSubview(view)
        }
        for view in [speechLabel, speechRuntimeLabel, speechRuntimePopup, speechSpeedLabel, speechSpeedPopup, kokoroSpeechCard, kittenSpeechCard, kokoroSpeechLabel, kokoroSpeechStatusLabel, kokoroSpeechProgressIndicator, kokoroSpeechDownloadButton, kokoroSpeechPauseButton, kokoroSpeechCancelButton, kokoroSpeechDeleteButton, kittenSpeechLabel, kittenSpeechStatusLabel, kittenSpeechProgressIndicator, kittenSpeechDownloadButton, kittenSpeechPauseButton, kittenSpeechCancelButton, kittenSpeechDeleteButton] {
            speechPage.addSubview(view)
        }
        for view in [currentIndexCard, vectorCacheCard] {
            cachePage.addSubview(view)
        }

        let keyTopWithCustom = keyLabel.topAnchor.constraint(equalTo: customModelContainer.bottomAnchor, constant: 22)
        let keyTopWithoutCustom = keyLabel.topAnchor.constraint(equalTo: modelPopup.bottomAnchor, constant: 34)
        let labelColumnWidth = layout.labelColumnWidth
        let fieldWidth = layout.fieldWidth
        let formWidth = layout.formWidth
        let controlHeight = layout.controlHeight
        let inputHeight = layout.inputHeight
        let embeddingModelTopWithCustomEndpoint = embeddingModelNameLabel.topAnchor.constraint(equalTo: embeddingEndpointContainer.bottomAnchor, constant: 10)
        let embeddingModelTopWithoutCustomEndpoint = embeddingModelNameLabel.topAnchor.constraint(equalTo: embeddingProviderPopup.bottomAnchor, constant: 8)
        keyTopWithCustomConstraint = keyTopWithCustom
        keyTopWithoutCustomConstraint = keyTopWithoutCustom
        embeddingModelTopWithCustomEndpointConstraint = embeddingModelTopWithCustomEndpoint
        embeddingModelTopWithoutCustomEndpointConstraint = embeddingModelTopWithoutCustomEndpoint

        let pdfDimmingLabelTopConstraint = pdfDimmingLabel.topAnchor.constraint(equalTo: themePopup.bottomAnchor, constant: 22)
        let speakSelectedWordTopToDimmingConstraint = speakSelectedWordLabel.topAnchor.constraint(equalTo: pdfDimmingSlider.bottomAnchor, constant: 22)
        let speakSelectedWordTopToThemeConstraint = speakSelectedWordLabel.topAnchor.constraint(equalTo: themePopup.bottomAnchor, constant: 22)
        let pdfDimmingCollapsedConstraints = [
            pdfDimmingLabel.heightAnchor.constraint(equalToConstant: 0),
            pdfDimmingSlider.heightAnchor.constraint(equalToConstant: 0)
        ]

        NSLayoutConstraint.activate([
            titleIcon.topAnchor.constraint(equalTo: content.topAnchor, constant: 32),
            titleIcon.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 44),
            titleIcon.widthAnchor.constraint(equalToConstant: 36),
            titleIcon.heightAnchor.constraint(equalToConstant: 36),
            titleLabel.centerYAnchor.constraint(equalTo: titleIcon.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: titleIcon.trailingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -54),
            closeButton.topAnchor.constraint(equalTo: content.topAnchor, constant: 30),
            closeButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -36),
            closeButton.widthAnchor.constraint(equalToConstant: 34),
            closeButton.heightAnchor.constraint(equalToConstant: 34),

            tabControl.topAnchor.constraint(equalTo: content.topAnchor, constant: 78),
            tabControl.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            tabControl.widthAnchor.constraint(equalToConstant: 540),
            tabControl.heightAnchor.constraint(equalToConstant: 40),

            scrollView.topAnchor.constraint(equalTo: content.topAnchor, constant: 134),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 44),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -44),
            scrollView.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -22),
            formContent.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor, constant: 22),
            formContent.centerXAnchor.constraint(equalTo: scrollView.contentView.centerXAnchor),
            formContent.leadingAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.leadingAnchor),
            formContent.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.contentView.trailingAnchor),
            formContent.widthAnchor.constraint(equalToConstant: formWidth),
            formContent.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
            basicPage.topAnchor.constraint(equalTo: formContent.topAnchor),
            basicPage.leadingAnchor.constraint(equalTo: formContent.leadingAnchor),
            basicPage.trailingAnchor.constraint(equalTo: formContent.trailingAnchor),
            basicPage.bottomAnchor.constraint(equalTo: formContent.bottomAnchor),
            modelPage.topAnchor.constraint(equalTo: formContent.topAnchor),
            modelPage.leadingAnchor.constraint(equalTo: formContent.leadingAnchor),
            modelPage.trailingAnchor.constraint(equalTo: formContent.trailingAnchor),
            modelPage.bottomAnchor.constraint(equalTo: formContent.bottomAnchor),
            embeddingPage.topAnchor.constraint(equalTo: formContent.topAnchor),
            embeddingPage.leadingAnchor.constraint(equalTo: formContent.leadingAnchor),
            embeddingPage.trailingAnchor.constraint(equalTo: formContent.trailingAnchor),
            embeddingPage.bottomAnchor.constraint(equalTo: formContent.bottomAnchor),
            speechPage.topAnchor.constraint(equalTo: formContent.topAnchor),
            speechPage.leadingAnchor.constraint(equalTo: formContent.leadingAnchor),
            speechPage.trailingAnchor.constraint(equalTo: formContent.trailingAnchor),
            speechPage.bottomAnchor.constraint(equalTo: formContent.bottomAnchor),
            cachePage.topAnchor.constraint(equalTo: formContent.topAnchor),
            cachePage.leadingAnchor.constraint(equalTo: formContent.leadingAnchor),
            cachePage.trailingAnchor.constraint(equalTo: formContent.trailingAnchor),
            cachePage.bottomAnchor.constraint(equalTo: formContent.bottomAnchor),

            languageLabel.topAnchor.constraint(equalTo: basicPage.topAnchor, constant: 4),
            languageLabel.leadingAnchor.constraint(equalTo: basicPage.leadingAnchor),
            languageLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            languagePopup.topAnchor.constraint(equalTo: languageLabel.topAnchor),
            languagePopup.leadingAnchor.constraint(equalTo: basicPage.leadingAnchor, constant: labelColumnWidth),
            languagePopup.widthAnchor.constraint(equalToConstant: fieldWidth),
            languagePopup.heightAnchor.constraint(equalToConstant: controlHeight),
            languageHelpLabel.topAnchor.constraint(equalTo: languagePopup.bottomAnchor, constant: 4),
            languageHelpLabel.leadingAnchor.constraint(equalTo: languagePopup.leadingAnchor),
            languageHelpLabel.widthAnchor.constraint(equalToConstant: fieldWidth),

            themeLabel.topAnchor.constraint(equalTo: languagePopup.bottomAnchor, constant: 34),
            themeLabel.leadingAnchor.constraint(equalTo: basicPage.leadingAnchor),
            themeLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            themePopup.topAnchor.constraint(equalTo: themeLabel.topAnchor),
            themePopup.leadingAnchor.constraint(equalTo: basicPage.leadingAnchor, constant: labelColumnWidth),
            themePopup.widthAnchor.constraint(equalToConstant: fieldWidth),
            themePopup.heightAnchor.constraint(equalToConstant: controlHeight),
            themeHelpLabel.topAnchor.constraint(equalTo: themePopup.bottomAnchor, constant: 4),
            themeHelpLabel.leadingAnchor.constraint(equalTo: themePopup.leadingAnchor),
            themeHelpLabel.widthAnchor.constraint(equalToConstant: fieldWidth),

            pdfDimmingLabelTopConstraint,
            pdfDimmingLabel.leadingAnchor.constraint(equalTo: basicPage.leadingAnchor),
            pdfDimmingLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            pdfDimmingSlider.centerYAnchor.constraint(equalTo: pdfDimmingLabel.centerYAnchor),
            pdfDimmingSlider.leadingAnchor.constraint(equalTo: basicPage.leadingAnchor, constant: labelColumnWidth),
            pdfDimmingSlider.widthAnchor.constraint(equalToConstant: fieldWidth),

            speakSelectedWordTopToDimmingConstraint,
            speakSelectedWordLabel.leadingAnchor.constraint(equalTo: basicPage.leadingAnchor),
            speakSelectedWordLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            speakSelectedWordCheckbox.centerYAnchor.constraint(equalTo: speakSelectedWordLabel.centerYAnchor),
            speakSelectedWordCheckbox.leadingAnchor.constraint(equalTo: basicPage.leadingAnchor, constant: labelColumnWidth),
            speakSelectedWordCheckbox.widthAnchor.constraint(equalToConstant: 32),
            saveAIConversationLabel.topAnchor.constraint(equalTo: speakSelectedWordLabel.bottomAnchor, constant: 22),
            saveAIConversationLabel.leadingAnchor.constraint(equalTo: basicPage.leadingAnchor),
            saveAIConversationLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            saveAIConversationCheckbox.centerYAnchor.constraint(equalTo: saveAIConversationLabel.centerYAnchor),
            saveAIConversationCheckbox.leadingAnchor.constraint(equalTo: basicPage.leadingAnchor, constant: labelColumnWidth),
            saveAIConversationCheckbox.widthAnchor.constraint(equalToConstant: 32),
            saveAIConversationCheckbox.bottomAnchor.constraint(lessThanOrEqualTo: basicPage.bottomAnchor, constant: -8),

            modelLabel.topAnchor.constraint(equalTo: modelPage.topAnchor, constant: 4),
            modelLabel.leadingAnchor.constraint(equalTo: modelPage.leadingAnchor),
            modelLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            modelPopup.topAnchor.constraint(equalTo: modelPage.topAnchor, constant: 4),
            modelPopup.leadingAnchor.constraint(equalTo: modelPage.leadingAnchor, constant: labelColumnWidth),
            modelPopup.widthAnchor.constraint(equalToConstant: fieldWidth),
            modelPopup.heightAnchor.constraint(equalToConstant: controlHeight),
            modelHelpLabel.topAnchor.constraint(equalTo: modelPopup.bottomAnchor, constant: 4),
            modelHelpLabel.leadingAnchor.constraint(equalTo: modelPopup.leadingAnchor),
            modelHelpLabel.widthAnchor.constraint(equalToConstant: fieldWidth),

            customModelContainer.topAnchor.constraint(equalTo: modelPopup.bottomAnchor, constant: 14),
            customModelContainer.leadingAnchor.constraint(equalTo: modelPopup.leadingAnchor),
            customModelContainer.widthAnchor.constraint(equalToConstant: fieldWidth),
            customModelContainer.heightAnchor.constraint(equalToConstant: 116),
            customEndpointLabel.topAnchor.constraint(equalTo: customModelContainer.topAnchor, constant: 14),
            customEndpointLabel.leadingAnchor.constraint(equalTo: customModelContainer.leadingAnchor, constant: 14),
            customEndpointLabel.widthAnchor.constraint(equalToConstant: 128),
            customEndpointField.centerYAnchor.constraint(equalTo: customEndpointLabel.centerYAnchor),
            customEndpointField.leadingAnchor.constraint(equalTo: customModelContainer.leadingAnchor, constant: 150),
            customEndpointField.trailingAnchor.constraint(equalTo: customModelContainer.trailingAnchor, constant: -14),
            customEndpointField.heightAnchor.constraint(equalToConstant: inputHeight),
            customModelLabel.topAnchor.constraint(equalTo: customEndpointLabel.bottomAnchor, constant: 22),
            customModelLabel.leadingAnchor.constraint(equalTo: customEndpointLabel.leadingAnchor),
            customModelLabel.widthAnchor.constraint(equalToConstant: 128),
            customModelField.centerYAnchor.constraint(equalTo: customModelLabel.centerYAnchor),
            customModelField.leadingAnchor.constraint(equalTo: customEndpointField.leadingAnchor),
            customModelField.trailingAnchor.constraint(equalTo: customEndpointField.trailingAnchor),
            customModelField.heightAnchor.constraint(equalToConstant: inputHeight),

            keyTopWithCustom,
            keyLabel.leadingAnchor.constraint(equalTo: modelPage.leadingAnchor),
            keyLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            keyField.topAnchor.constraint(equalTo: keyLabel.topAnchor),
            keyField.leadingAnchor.constraint(equalTo: modelPage.leadingAnchor, constant: labelColumnWidth),
            keyField.widthAnchor.constraint(equalToConstant: fieldWidth),
            keyField.heightAnchor.constraint(equalToConstant: inputHeight),
            keyHelpLabel.topAnchor.constraint(equalTo: keyField.bottomAnchor, constant: 4),
            keyHelpLabel.leadingAnchor.constraint(equalTo: keyField.leadingAnchor),
            keyHelpLabel.widthAnchor.constraint(equalToConstant: fieldWidth),

            testChatButton.topAnchor.constraint(equalTo: keyField.bottomAnchor, constant: 18),
            testChatButton.leadingAnchor.constraint(equalTo: keyField.leadingAnchor),
            testChatButton.widthAnchor.constraint(equalToConstant: 136),
            testChatButton.heightAnchor.constraint(equalToConstant: controlHeight),
            testChatButton.bottomAnchor.constraint(lessThanOrEqualTo: modelPage.bottomAnchor, constant: -8),

            embeddingLabel.topAnchor.constraint(equalTo: embeddingPage.topAnchor, constant: 4),
            embeddingLabel.leadingAnchor.constraint(equalTo: embeddingPage.leadingAnchor),
            embeddingLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            embeddingProviderPopup.topAnchor.constraint(equalTo: embeddingLabel.topAnchor),
            embeddingProviderPopup.leadingAnchor.constraint(equalTo: embeddingPage.leadingAnchor, constant: labelColumnWidth),
            embeddingProviderPopup.widthAnchor.constraint(equalToConstant: fieldWidth),
            embeddingProviderPopup.heightAnchor.constraint(equalToConstant: controlHeight),
            embeddingEndpointContainer.topAnchor.constraint(equalTo: embeddingProviderPopup.bottomAnchor, constant: 10),
            embeddingEndpointContainer.leadingAnchor.constraint(equalTo: embeddingProviderPopup.leadingAnchor),
            embeddingEndpointContainer.widthAnchor.constraint(equalToConstant: fieldWidth),
            embeddingEndpointContainer.heightAnchor.constraint(equalToConstant: 68),
            embeddingEndpointLabel.centerYAnchor.constraint(equalTo: embeddingEndpointContainer.centerYAnchor),
            embeddingEndpointLabel.leadingAnchor.constraint(equalTo: embeddingEndpointContainer.leadingAnchor, constant: 14),
            embeddingEndpointLabel.widthAnchor.constraint(equalToConstant: 128),
            embeddingEndpointField.centerYAnchor.constraint(equalTo: embeddingEndpointContainer.centerYAnchor),
            embeddingEndpointField.leadingAnchor.constraint(equalTo: embeddingEndpointContainer.leadingAnchor, constant: 150),
            embeddingEndpointField.trailingAnchor.constraint(equalTo: embeddingEndpointContainer.trailingAnchor, constant: -14),
            embeddingEndpointField.heightAnchor.constraint(equalToConstant: inputHeight),
            embeddingModelTopWithCustomEndpoint,
            embeddingModelNameLabel.leadingAnchor.constraint(equalTo: embeddingPage.leadingAnchor),
            embeddingModelNameLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            embeddingModelField.topAnchor.constraint(equalTo: embeddingModelNameLabel.topAnchor),
            embeddingModelField.leadingAnchor.constraint(equalTo: embeddingPage.leadingAnchor, constant: labelColumnWidth),
            embeddingModelField.widthAnchor.constraint(equalToConstant: fieldWidth),
            embeddingModelField.heightAnchor.constraint(equalToConstant: inputHeight),
            embeddingKeyLabel.topAnchor.constraint(equalTo: embeddingModelField.bottomAnchor, constant: 8),
            embeddingKeyLabel.leadingAnchor.constraint(equalTo: embeddingPage.leadingAnchor),
            embeddingKeyLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            embeddingKeyField.topAnchor.constraint(equalTo: embeddingKeyLabel.topAnchor),
            embeddingKeyField.leadingAnchor.constraint(equalTo: embeddingPage.leadingAnchor, constant: labelColumnWidth),
            embeddingKeyField.widthAnchor.constraint(equalToConstant: fieldWidth),
            embeddingKeyField.heightAnchor.constraint(equalToConstant: inputHeight),
            embeddingHelpLabel.topAnchor.constraint(equalTo: embeddingKeyField.bottomAnchor, constant: 6),
            embeddingHelpLabel.leadingAnchor.constraint(equalTo: embeddingKeyField.leadingAnchor),
            embeddingHelpLabel.widthAnchor.constraint(equalToConstant: fieldWidth),

            autoEmbeddingIndexCheckbox.topAnchor.constraint(equalTo: embeddingHelpLabel.bottomAnchor, constant: 10),
            autoEmbeddingIndexCheckbox.leadingAnchor.constraint(equalTo: embeddingKeyField.leadingAnchor),
            autoEmbeddingIndexCheckbox.widthAnchor.constraint(equalToConstant: fieldWidth),
            testEmbeddingButton.topAnchor.constraint(equalTo: autoEmbeddingIndexCheckbox.bottomAnchor, constant: 10),
            testEmbeddingButton.leadingAnchor.constraint(equalTo: embeddingKeyField.leadingAnchor),
            testEmbeddingButton.widthAnchor.constraint(equalToConstant: 136),
            testEmbeddingButton.heightAnchor.constraint(equalToConstant: controlHeight),
            testEmbeddingButton.bottomAnchor.constraint(lessThanOrEqualTo: embeddingPage.bottomAnchor, constant: -8),

            speechLabel.topAnchor.constraint(equalTo: speechPage.topAnchor, constant: 4),
            speechLabel.leadingAnchor.constraint(equalTo: speechPage.leadingAnchor),
            speechLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            speechRuntimeLabel.topAnchor.constraint(equalTo: speechLabel.topAnchor),
            speechRuntimeLabel.leadingAnchor.constraint(equalTo: speechPage.leadingAnchor),
            speechRuntimeLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            speechRuntimePopup.centerYAnchor.constraint(equalTo: speechRuntimeLabel.centerYAnchor),
            speechRuntimePopup.leadingAnchor.constraint(equalTo: speechPage.leadingAnchor, constant: labelColumnWidth),
            speechRuntimePopup.widthAnchor.constraint(equalToConstant: fieldWidth),
            speechRuntimePopup.heightAnchor.constraint(equalToConstant: controlHeight),
            speechSpeedLabel.topAnchor.constraint(equalTo: speechRuntimePopup.bottomAnchor, constant: 16),
            speechSpeedLabel.leadingAnchor.constraint(equalTo: speechRuntimeLabel.leadingAnchor),
            speechSpeedLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            speechSpeedPopup.centerYAnchor.constraint(equalTo: speechSpeedLabel.centerYAnchor),
            speechSpeedPopup.leadingAnchor.constraint(equalTo: speechRuntimePopup.leadingAnchor),
            speechSpeedPopup.widthAnchor.constraint(equalToConstant: fieldWidth),
            speechSpeedPopup.heightAnchor.constraint(equalToConstant: controlHeight),

            kittenSpeechCard.topAnchor.constraint(equalTo: speechSpeedPopup.bottomAnchor, constant: 28),
            kittenSpeechCard.leadingAnchor.constraint(equalTo: speechPage.leadingAnchor),
            kittenSpeechCard.trailingAnchor.constraint(equalTo: speechPage.trailingAnchor),
            kittenSpeechCard.heightAnchor.constraint(equalToConstant: 58),
            kokoroSpeechCard.topAnchor.constraint(equalTo: kittenSpeechCard.bottomAnchor, constant: 10),
            kokoroSpeechCard.leadingAnchor.constraint(equalTo: kittenSpeechCard.leadingAnchor),
            kokoroSpeechCard.trailingAnchor.constraint(equalTo: kittenSpeechCard.trailingAnchor),
            kokoroSpeechCard.heightAnchor.constraint(equalToConstant: 58),

            kokoroSpeechLabel.centerYAnchor.constraint(equalTo: kokoroSpeechCard.centerYAnchor),
            kokoroSpeechLabel.leadingAnchor.constraint(equalTo: kokoroSpeechCard.leadingAnchor, constant: 16),
            kokoroSpeechLabel.widthAnchor.constraint(equalToConstant: 92),
            kokoroSpeechStatusLabel.centerYAnchor.constraint(equalTo: kokoroSpeechLabel.centerYAnchor),
            kokoroSpeechStatusLabel.leadingAnchor.constraint(equalTo: kokoroSpeechLabel.trailingAnchor, constant: 16),
            kokoroSpeechStatusLabel.widthAnchor.constraint(equalToConstant: 126),
            kokoroSpeechProgressIndicator.centerYAnchor.constraint(equalTo: kokoroSpeechLabel.centerYAnchor),
            kokoroSpeechProgressIndicator.leadingAnchor.constraint(equalTo: kokoroSpeechStatusLabel.trailingAnchor, constant: 12),
            kokoroSpeechProgressIndicator.widthAnchor.constraint(equalToConstant: 110),
            kokoroSpeechProgressIndicator.heightAnchor.constraint(equalToConstant: 8),
            kokoroSpeechDownloadButton.centerYAnchor.constraint(equalTo: kokoroSpeechLabel.centerYAnchor),
            kokoroSpeechDownloadButton.trailingAnchor.constraint(equalTo: kokoroSpeechCard.trailingAnchor, constant: -16),
            kokoroSpeechDownloadButton.widthAnchor.constraint(equalToConstant: 124),
            kokoroSpeechDownloadButton.heightAnchor.constraint(equalToConstant: controlHeight),
            kokoroSpeechPauseButton.centerYAnchor.constraint(equalTo: kokoroSpeechLabel.centerYAnchor),
            kokoroSpeechPauseButton.trailingAnchor.constraint(equalTo: kokoroSpeechCancelButton.leadingAnchor, constant: -8),
            kokoroSpeechPauseButton.widthAnchor.constraint(equalToConstant: 76),
            kokoroSpeechPauseButton.heightAnchor.constraint(equalToConstant: controlHeight),
            kokoroSpeechCancelButton.centerYAnchor.constraint(equalTo: kokoroSpeechLabel.centerYAnchor),
            kokoroSpeechCancelButton.trailingAnchor.constraint(equalTo: kokoroSpeechCard.trailingAnchor, constant: -16),
            kokoroSpeechCancelButton.widthAnchor.constraint(equalToConstant: 76),
            kokoroSpeechCancelButton.heightAnchor.constraint(equalToConstant: controlHeight),
            kokoroSpeechDeleteButton.centerYAnchor.constraint(equalTo: kokoroSpeechLabel.centerYAnchor),
            kokoroSpeechDeleteButton.trailingAnchor.constraint(equalTo: kokoroSpeechCard.trailingAnchor, constant: -16),
            kokoroSpeechDeleteButton.widthAnchor.constraint(equalToConstant: 76),
            kokoroSpeechDeleteButton.heightAnchor.constraint(equalToConstant: controlHeight),
            kittenSpeechLabel.centerYAnchor.constraint(equalTo: kittenSpeechCard.centerYAnchor),
            kittenSpeechLabel.leadingAnchor.constraint(equalTo: kokoroSpeechLabel.leadingAnchor),
            kittenSpeechLabel.widthAnchor.constraint(equalToConstant: 92),
            kittenSpeechStatusLabel.centerYAnchor.constraint(equalTo: kittenSpeechLabel.centerYAnchor),
            kittenSpeechStatusLabel.leadingAnchor.constraint(equalTo: kittenSpeechLabel.trailingAnchor, constant: 16),
            kittenSpeechStatusLabel.widthAnchor.constraint(equalToConstant: 126),
            kittenSpeechProgressIndicator.centerYAnchor.constraint(equalTo: kittenSpeechLabel.centerYAnchor),
            kittenSpeechProgressIndicator.leadingAnchor.constraint(equalTo: kittenSpeechStatusLabel.trailingAnchor, constant: 12),
            kittenSpeechProgressIndicator.widthAnchor.constraint(equalToConstant: 110),
            kittenSpeechProgressIndicator.heightAnchor.constraint(equalToConstant: 8),
            kittenSpeechDownloadButton.centerYAnchor.constraint(equalTo: kittenSpeechLabel.centerYAnchor),
            kittenSpeechDownloadButton.trailingAnchor.constraint(equalTo: kittenSpeechCard.trailingAnchor, constant: -16),
            kittenSpeechDownloadButton.widthAnchor.constraint(equalToConstant: 124),
            kittenSpeechDownloadButton.heightAnchor.constraint(equalToConstant: controlHeight),
            kittenSpeechPauseButton.centerYAnchor.constraint(equalTo: kittenSpeechLabel.centerYAnchor),
            kittenSpeechPauseButton.trailingAnchor.constraint(equalTo: kittenSpeechCancelButton.leadingAnchor, constant: -8),
            kittenSpeechPauseButton.widthAnchor.constraint(equalToConstant: 76),
            kittenSpeechPauseButton.heightAnchor.constraint(equalToConstant: controlHeight),
            kittenSpeechCancelButton.centerYAnchor.constraint(equalTo: kittenSpeechLabel.centerYAnchor),
            kittenSpeechCancelButton.trailingAnchor.constraint(equalTo: kittenSpeechCard.trailingAnchor, constant: -16),
            kittenSpeechCancelButton.widthAnchor.constraint(equalToConstant: 76),
            kittenSpeechCancelButton.heightAnchor.constraint(equalToConstant: controlHeight),
            kittenSpeechDeleteButton.centerYAnchor.constraint(equalTo: kittenSpeechLabel.centerYAnchor),
            kittenSpeechDeleteButton.trailingAnchor.constraint(equalTo: kittenSpeechCard.trailingAnchor, constant: -16),
            kittenSpeechDeleteButton.widthAnchor.constraint(equalToConstant: 76),
            kittenSpeechDeleteButton.heightAnchor.constraint(equalToConstant: controlHeight),
            kokoroSpeechCard.bottomAnchor.constraint(lessThanOrEqualTo: speechPage.bottomAnchor, constant: -8),

            currentIndexCard.topAnchor.constraint(equalTo: cachePage.topAnchor, constant: 4),
            currentIndexCard.leadingAnchor.constraint(equalTo: cachePage.leadingAnchor),
            currentIndexCard.widthAnchor.constraint(equalToConstant: formWidth),
            currentIndexCard.heightAnchor.constraint(equalToConstant: 204),
            currentIndexLabel.topAnchor.constraint(equalTo: currentIndexCard.topAnchor, constant: 24),
            currentIndexLabel.leadingAnchor.constraint(equalTo: currentIndexCard.leadingAnchor, constant: 22),
            currentIndexStatusLabel.topAnchor.constraint(equalTo: currentIndexLabel.bottomAnchor, constant: 14),
            currentIndexStatusLabel.leadingAnchor.constraint(equalTo: currentIndexLabel.leadingAnchor),
            currentIndexStatusLabel.widthAnchor.constraint(equalToConstant: formWidth - 44),
            startIndexButton.topAnchor.constraint(equalTo: currentIndexStatusLabel.bottomAnchor, constant: 20),
            startIndexButton.leadingAnchor.constraint(equalTo: currentIndexLabel.leadingAnchor),
            startIndexButton.widthAnchor.constraint(equalToConstant: 194),
            startIndexButton.heightAnchor.constraint(equalToConstant: 44),
            pauseIndexButton.centerYAnchor.constraint(equalTo: startIndexButton.centerYAnchor),
            pauseIndexButton.leadingAnchor.constraint(equalTo: startIndexButton.trailingAnchor, constant: 16),
            pauseIndexButton.widthAnchor.constraint(equalToConstant: 194),
            pauseIndexButton.heightAnchor.constraint(equalToConstant: 44),
            cancelIndexButton.centerYAnchor.constraint(equalTo: startIndexButton.centerYAnchor),
            cancelIndexButton.leadingAnchor.constraint(equalTo: pauseIndexButton.trailingAnchor, constant: 16),
            cancelIndexButton.widthAnchor.constraint(equalToConstant: 194),
            cancelIndexButton.heightAnchor.constraint(equalToConstant: 44),
            clearCurrentIndexButton.topAnchor.constraint(equalTo: startIndexButton.bottomAnchor, constant: 12),
            clearCurrentIndexButton.leadingAnchor.constraint(equalTo: currentIndexLabel.leadingAnchor),
            clearCurrentIndexButton.widthAnchor.constraint(equalToConstant: 194),
            clearCurrentIndexButton.heightAnchor.constraint(equalToConstant: 44),
            clearCurrentWordsButton.centerYAnchor.constraint(equalTo: clearCurrentIndexButton.centerYAnchor),
            clearCurrentWordsButton.leadingAnchor.constraint(equalTo: clearCurrentIndexButton.trailingAnchor, constant: 16),
            clearCurrentWordsButton.widthAnchor.constraint(equalToConstant: 194),
            clearCurrentWordsButton.heightAnchor.constraint(equalToConstant: 44),

            vectorCacheCard.topAnchor.constraint(equalTo: currentIndexCard.bottomAnchor, constant: 18),
            vectorCacheCard.leadingAnchor.constraint(equalTo: cachePage.leadingAnchor),
            vectorCacheCard.widthAnchor.constraint(equalToConstant: formWidth),
            vectorCacheCard.heightAnchor.constraint(equalToConstant: 138),
            cacheLabel.topAnchor.constraint(equalTo: vectorCacheCard.topAnchor, constant: 18),
            cacheLabel.leadingAnchor.constraint(equalTo: vectorCacheCard.leadingAnchor, constant: 22),
            cacheStatusLabel.topAnchor.constraint(equalTo: cacheLabel.bottomAnchor, constant: 12),
            cacheStatusLabel.leadingAnchor.constraint(equalTo: cacheLabel.leadingAnchor),
            cacheStatusLabel.widthAnchor.constraint(equalToConstant: formWidth - 92),
            clearVectorCacheButton.topAnchor.constraint(equalTo: cacheStatusLabel.bottomAnchor, constant: 16),
            clearVectorCacheButton.leadingAnchor.constraint(equalTo: vectorCacheCard.leadingAnchor, constant: 22),
            clearVectorCacheButton.widthAnchor.constraint(equalToConstant: 194),
            clearVectorCacheButton.heightAnchor.constraint(equalToConstant: 44),
            cacheDisclosureButton.trailingAnchor.constraint(equalTo: vectorCacheCard.trailingAnchor, constant: -22),
            cacheDisclosureButton.centerYAnchor.constraint(equalTo: vectorCacheCard.centerYAnchor),
            cacheDisclosureButton.widthAnchor.constraint(equalToConstant: 32),
            cacheDisclosureButton.heightAnchor.constraint(equalToConstant: 32),
            vectorCacheCard.bottomAnchor.constraint(equalTo: cachePage.bottomAnchor, constant: -8),

            saveButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -44),
            saveButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -36),
            saveButton.widthAnchor.constraint(equalToConstant: 104),
            saveButton.heightAnchor.constraint(equalToConstant: 44),
            cancelButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -16),
            cancelButton.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 104),
            cancelButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        self.panel = panel
        self.settingsTabControl = tabControl
        self.settingsScrollView = scrollView
        self.basicPage = basicPage
        self.modelPage = modelPage
        self.embeddingPage = embeddingPage
        self.speechPage = speechPage
        self.cachePage = cachePage
        self.modelPopup = modelPopup
        self.languagePopup = languagePopup
        self.themePopup = themePopup
        self.pdfDimmingLabel = pdfDimmingLabel
        self.pdfDimmingSlider = pdfDimmingSlider
        self.pdfDimmingLabelTopConstraint = pdfDimmingLabelTopConstraint
        self.speakSelectedWordTopToDimmingConstraint = speakSelectedWordTopToDimmingConstraint
        self.speakSelectedWordTopToThemeConstraint = speakSelectedWordTopToThemeConstraint
        self.pdfDimmingCollapsedConstraints = pdfDimmingCollapsedConstraints
        self.secureKeyField = keyField
        self.customModelContainer = customModelContainer
        self.customEndpointLabel = customEndpointLabel
        self.customEndpointField = customEndpointField
        self.customModelLabel = customModelLabel
        self.customModelField = customModelField
        self.embeddingProviderPopup = embeddingProviderPopup
        self.embeddingEndpointContainer = embeddingEndpointContainer
        self.embeddingEndpointLabel = embeddingEndpointLabel
        self.embeddingEndpointField = embeddingEndpointField
        self.embeddingModelField = embeddingModelField
        self.embeddingKeyField = embeddingKeyField
        self.speakSelectedWordCheckbox = speakSelectedWordCheckbox
        self.saveAIConversationCheckbox = saveAIConversationCheckbox
        self.autoEmbeddingIndexCheckbox = autoEmbeddingIndexCheckbox
        self.speechRuntimePopup = speechRuntimePopup
        self.speechSpeedPopup = speechSpeedPopup
        self.kokoroSpeechStatusLabel = kokoroSpeechStatusLabel
        self.kittenSpeechStatusLabel = kittenSpeechStatusLabel
        self.kokoroSpeechProgressIndicator = kokoroSpeechProgressIndicator
        self.kittenSpeechProgressIndicator = kittenSpeechProgressIndicator
        self.kokoroSpeechDownloadButton = kokoroSpeechDownloadButton
        self.kittenSpeechDownloadButton = kittenSpeechDownloadButton
        self.kokoroSpeechPauseButton = kokoroSpeechPauseButton
        self.kittenSpeechPauseButton = kittenSpeechPauseButton
        self.kokoroSpeechCancelButton = kokoroSpeechCancelButton
        self.kittenSpeechCancelButton = kittenSpeechCancelButton
        self.kokoroSpeechDeleteButton = kokoroSpeechDeleteButton
        self.kittenSpeechDeleteButton = kittenSpeechDeleteButton
        self.cacheStatusLabel = cacheStatusLabel
        self.currentIndexStatusLabel = currentIndexStatusLabel
        refreshSpeechRuntimeStatus()
        updateCustomModelFields(for: selectedModel.id)
        updateEmbeddingEndpointFields(for: selectedEmbeddingEndpoint.id, fillDefaults: false)
        updatePDFDimmingControlsVisibility()
        settingsTabChanged(index: initialTab.rawValue)

        installAppActivationObserver()
        refreshVectorCacheStatus()
        startCacheRefreshTimer()
        showPanel(panel, attachedTo: window)
        DispatchQueue.main.async {
            panel.makeKey()
            if selectedModel.id == AISettingsStore.customModelID {
                panel.makeFirstResponder(customEndpointField)
            } else {
                panel.makeFirstResponder(keyField)
            }
        }
    }
}
