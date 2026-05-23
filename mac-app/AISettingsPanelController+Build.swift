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

        let embeddingSection = makeEmbeddingSection(
            selectedEndpoint: selectedEmbeddingEndpoint,
            settingsFontSize: settingsFontSize,
            primaryText: primaryText,
            secondaryText: secondaryText,
            theme: theme
        )
        let embeddingProviderPopup = embeddingSection.providerPopup
        let embeddingEndpointContainer = embeddingSection.endpointContainer
        let embeddingEndpointLabel = embeddingSection.endpointLabel
        let embeddingEndpointField = embeddingSection.endpointField
        let embeddingModelField = embeddingSection.modelField
        let embeddingKeyField = embeddingSection.keyField
        let autoEmbeddingIndexCheckbox = embeddingSection.autoIndexCheckbox
        let speechSection = makeSpeechSection(
            settingsFontSize: settingsFontSize,
            primaryText: primaryText,
            secondaryText: secondaryText
        )
        let speechRuntimePopup = speechSection.runtimePopup
        let speechVoicePopup = speechSection.voicePopup
        let speechSpeedPopup = speechSection.speedPopup
        let kokoroSpeechStatusLabel = speechSection.kokoroStatusLabel
        let kittenSpeechStatusLabel = speechSection.kittenStatusLabel
        let kokoroSpeechProgressIndicator = speechSection.kokoroProgressIndicator
        let kittenSpeechProgressIndicator = speechSection.kittenProgressIndicator
        let kokoroSpeechDownloadButton = speechSection.kokoroDownloadButton
        let kittenSpeechDownloadButton = speechSection.kittenDownloadButton
        let kokoroSpeechPauseButton = speechSection.kokoroPauseButton
        let kittenSpeechPauseButton = speechSection.kittenPauseButton
        let kokoroSpeechCancelButton = speechSection.kokoroCancelButton
        let kittenSpeechCancelButton = speechSection.kittenCancelButton
        let kokoroSpeechDeleteButton = speechSection.kokoroDeleteButton
        let kittenSpeechDeleteButton = speechSection.kittenDeleteButton

        let testChatButton = settingsActionButton(title: AppText.localized("测试模型连接", "Test Chat"), target: self, action: #selector(testChatConnection(_:)))
        testChatButton.font = AppFont.semibold(ofSize: settingsFontSize)

        let cacheSection = makeCacheSection(
            settingsFontSize: settingsFontSize,
            primaryText: primaryText,
            secondaryText: secondaryText
        )
        let cacheStatusLabel = cacheSection.cacheStatusLabel
        let currentIndexStatusLabel = cacheSection.currentIndexStatusLabel

        let cancelButton = settingsActionButton(title: AppText.cancel, target: self, action: #selector(cancel(_:)))
        let saveButton = settingsActionButton(title: AppText.confirm, target: self, action: #selector(save(_:)), isPrimary: true)
        saveButton.keyEquivalent = "\r"

        modelPopup.target = self
        modelPopup.action = #selector(modelChanged(_:))
        themePopup.target = self
        themePopup.action = #selector(themeChanged(_:))
        modelPopup.identifier = Identifiers.modelPopup
        languagePopup.identifier = Identifiers.languagePopup
        themePopup.identifier = Identifiers.themePopup
        keyField.identifier = Identifiers.keyField

        for view in [titleIcon, titleLabel, closeButton, tabControl, scrollView, cancelButton, saveButton] {
            content.addSubview(view)
        }
        for view in [customEndpointLabel, customEndpointField, customModelLabel, customModelField] {
            customModelContainer.addSubview(view)
        }
        for view in [languageLabel, languagePopup, languageHelpLabel, themeLabel, themePopup, themeHelpLabel, pdfDimmingLabel, pdfDimmingSlider, speakSelectedWordLabel, speakSelectedWordCheckbox, saveAIConversationLabel, saveAIConversationCheckbox] {
            basicPage.addSubview(view)
        }
        for view in [modelLabel, modelPopup, modelHelpLabel, customModelContainer, keyLabel, keyField, keyHelpLabel, testChatButton] {
            modelPage.addSubview(view)
        }
        for view in embeddingSection.pageViews {
            embeddingPage.addSubview(view)
        }
        for view in speechSection.pageViews {
            speechPage.addSubview(view)
        }
        for view in cacheSection.pageViews {
            cachePage.addSubview(view)
        }

        let keyTopWithCustom = keyLabel.topAnchor.constraint(equalTo: customModelContainer.bottomAnchor, constant: 22)
        let keyTopWithoutCustom = keyLabel.topAnchor.constraint(equalTo: modelPopup.bottomAnchor, constant: 34)
        let labelColumnWidth = layout.labelColumnWidth
        let fieldWidth = layout.fieldWidth
        let formWidth = layout.formWidth
        let controlHeight = layout.controlHeight
        let inputHeight = layout.inputHeight
        let embeddingLayout = embeddingConstraints(
            for: embeddingSection,
            page: embeddingPage,
            labelColumnWidth: labelColumnWidth,
            fieldWidth: fieldWidth,
            inputHeight: inputHeight,
            controlHeight: controlHeight
        )
        let embeddingModelTopWithCustomEndpoint = embeddingLayout.modelTopWithCustomEndpoint
        let embeddingModelTopWithoutCustomEndpoint = embeddingLayout.modelTopWithoutCustomEndpoint
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

        NSLayoutConstraint.activate(embeddingLayout.constraints)
        NSLayoutConstraint.activate(speechConstraints(
            for: speechSection,
            page: speechPage,
            labelColumnWidth: labelColumnWidth,
            fieldWidth: fieldWidth,
            controlHeight: controlHeight
        ))
        NSLayoutConstraint.activate(cacheConstraints(
            for: cacheSection,
            page: cachePage,
            formWidth: formWidth
        ))
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
        self.speechVoicePopup = speechVoicePopup
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
