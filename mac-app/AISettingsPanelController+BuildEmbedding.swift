import Cocoa

struct AISettingsEmbeddingSection {
    let label: NSTextField
    let providerPopup: NSPopUpButton
    let endpointContainer: NSView
    let endpointLabel: NSTextField
    let endpointField: NSTextField
    let modelNameLabel: NSTextField
    let modelField: NSTextField
    let keyLabel: NSTextField
    let keyField: APIKeySecureTextField
    let autoIndexCheckbox: NSButton
    let autoIndexLabel: NSTextField
    let testButton: NSButton

    var pageViews: [NSView] {
        [
            label,
            providerPopup,
            endpointContainer,
            modelNameLabel,
            modelField,
            keyLabel,
            keyField,
            autoIndexCheckbox,
            autoIndexLabel,
            testButton
        ]
    }
}

struct AISettingsEmbeddingConstraints {
    let modelTopWithCustomEndpoint: NSLayoutConstraint
    let modelTopWithoutCustomEndpoint: NSLayoutConstraint
    let constraints: [NSLayoutConstraint]
}

extension AISettingsPanelController {
    func makeEmbeddingSection(
        selectedEndpoint: AISettingsStore.EmbeddingEndpointOption,
        settingsFontSize: CGFloat,
        primaryText: NSColor,
        theme: ReaderTheme
    ) -> AISettingsEmbeddingSection {
        let serviceLabel = label(AppText.localized("向量服务", "Embedding Service"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let providerPopup = popup(
            items: AISettingsStore.embeddingEndpointOptions.map { ($0.title, $0.id) },
            selected: selectedEndpoint.id,
            fontSize: settingsFontSize
        )
        providerPopup.target = self
        providerPopup.action = #selector(embeddingProviderChanged(_:))
        providerPopup.identifier = Identifiers.embeddingProviderPopup

        let endpointLabel = label(AppText.localized("接口 URL", "Endpoint URL"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let endpointField = inputField(
            AISettingsStore.embeddingEndpointString,
            placeholder: "https://api.openai.com/v1/embeddings",
            fontSize: settingsFontSize,
            textColor: primaryText,
            backgroundColor: fieldBackground()
        )
        endpointField.identifier = Identifiers.embeddingEndpointField

        let endpointContainer = settingsCard()
        endpointContainer.addSubview(endpointLabel)
        endpointContainer.addSubview(endpointField)

        let modelNameLabel = label(AppText.localized("向量模型", "Embedding Model"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let modelField = inputField(
            AISettingsStore.embeddingModelName,
            placeholder: AISettingsStore.fallbackEmbeddingModelName,
            fontSize: settingsFontSize,
            textColor: primaryText,
            backgroundColor: fieldBackground()
        )
        modelField.identifier = Identifiers.embeddingModelField

        let keyLabel = label(AppText.localized("向量 API Key", "Embedding API Key"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let keyField = APIKeySecureTextField(string: AISettingsStore.embeddingAPIKeyMigratingLegacyIfNeeded(for: selectedEndpoint.id))
        configureKeyField(
            keyField,
            placeholder: AppText.apiKeyPlaceholder,
            fontSize: settingsFontSize,
            textColor: primaryText,
            backgroundColor: fieldBackground()
        )
        keyField.identifier = Identifiers.embeddingKeyField

        let autoIndexCheckbox = settingsCheckbox(
            isOn: AISettingsStore.autoEmbeddingIndexEnabled,
            theme: theme,
            fontSize: settingsFontSize
        )
        let autoIndexLabel = label(AppText.localized("自动 AI 缓存", "Auto AI Cache"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let testButton = settingsActionButton(
            title: AppText.localized("测试向量连接", "Test Embedding"),
            target: self,
            action: #selector(testEmbeddingConnection(_:))
        )
        testButton.font = AppFont.semibold(ofSize: settingsFontSize)

        return AISettingsEmbeddingSection(
            label: serviceLabel,
            providerPopup: providerPopup,
            endpointContainer: endpointContainer,
            endpointLabel: endpointLabel,
            endpointField: endpointField,
            modelNameLabel: modelNameLabel,
            modelField: modelField,
            keyLabel: keyLabel,
            keyField: keyField,
            autoIndexCheckbox: autoIndexCheckbox,
            autoIndexLabel: autoIndexLabel,
            testButton: testButton
        )
    }

    func embeddingConstraints(
        for section: AISettingsEmbeddingSection,
        page: NSView,
        labelColumnWidth: CGFloat,
        fieldWidth: CGFloat,
        inputHeight: CGFloat,
        controlHeight: CGFloat
    ) -> AISettingsEmbeddingConstraints {
        let modelTopWithCustomEndpoint = section.modelNameLabel.topAnchor.constraint(equalTo: section.endpointContainer.bottomAnchor, constant: 10)
        let modelTopWithoutCustomEndpoint = section.modelNameLabel.topAnchor.constraint(equalTo: section.providerPopup.bottomAnchor, constant: 8)
        return AISettingsEmbeddingConstraints(
            modelTopWithCustomEndpoint: modelTopWithCustomEndpoint,
            modelTopWithoutCustomEndpoint: modelTopWithoutCustomEndpoint,
            constraints: [
                section.label.topAnchor.constraint(equalTo: page.topAnchor, constant: 4),
                section.label.leadingAnchor.constraint(equalTo: page.leadingAnchor),
                section.label.widthAnchor.constraint(equalToConstant: labelColumnWidth),
                section.providerPopup.topAnchor.constraint(equalTo: section.label.topAnchor),
                section.providerPopup.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: labelColumnWidth),
                section.providerPopup.widthAnchor.constraint(equalToConstant: fieldWidth),
                section.providerPopup.heightAnchor.constraint(equalToConstant: controlHeight),
                section.endpointContainer.topAnchor.constraint(equalTo: section.providerPopup.bottomAnchor, constant: 10),
                section.endpointContainer.leadingAnchor.constraint(equalTo: section.providerPopup.leadingAnchor),
                section.endpointContainer.widthAnchor.constraint(equalToConstant: fieldWidth),
                section.endpointContainer.heightAnchor.constraint(equalToConstant: 68),
                section.endpointLabel.centerYAnchor.constraint(equalTo: section.endpointContainer.centerYAnchor),
                section.endpointLabel.leadingAnchor.constraint(equalTo: section.endpointContainer.leadingAnchor, constant: 14),
                section.endpointLabel.widthAnchor.constraint(equalToConstant: 128),
                section.endpointField.centerYAnchor.constraint(equalTo: section.endpointContainer.centerYAnchor),
                section.endpointField.leadingAnchor.constraint(equalTo: section.endpointContainer.leadingAnchor, constant: 150),
                section.endpointField.trailingAnchor.constraint(equalTo: section.endpointContainer.trailingAnchor, constant: -14),
                section.endpointField.heightAnchor.constraint(equalToConstant: inputHeight),
                modelTopWithCustomEndpoint,
                section.modelNameLabel.leadingAnchor.constraint(equalTo: page.leadingAnchor),
                section.modelNameLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
                section.modelField.topAnchor.constraint(equalTo: section.modelNameLabel.topAnchor),
                section.modelField.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: labelColumnWidth),
                section.modelField.widthAnchor.constraint(equalToConstant: fieldWidth),
                section.modelField.heightAnchor.constraint(equalToConstant: inputHeight),
                section.keyLabel.topAnchor.constraint(equalTo: section.modelField.bottomAnchor, constant: 8),
                section.keyLabel.leadingAnchor.constraint(equalTo: page.leadingAnchor),
                section.keyLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
                section.keyField.topAnchor.constraint(equalTo: section.keyLabel.topAnchor),
                section.keyField.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: labelColumnWidth),
                section.keyField.widthAnchor.constraint(equalToConstant: fieldWidth),
                section.keyField.heightAnchor.constraint(equalToConstant: inputHeight),
                section.autoIndexCheckbox.topAnchor.constraint(equalTo: section.keyField.bottomAnchor, constant: 12),
                section.autoIndexCheckbox.leadingAnchor.constraint(equalTo: section.keyField.leadingAnchor),
                section.autoIndexCheckbox.widthAnchor.constraint(equalToConstant: 28),
                section.autoIndexCheckbox.heightAnchor.constraint(equalToConstant: 28),
                section.autoIndexLabel.centerYAnchor.constraint(equalTo: section.autoIndexCheckbox.centerYAnchor),
                section.autoIndexLabel.leadingAnchor.constraint(equalTo: section.autoIndexCheckbox.trailingAnchor, constant: 8),
                section.autoIndexLabel.trailingAnchor.constraint(lessThanOrEqualTo: section.keyField.trailingAnchor),
                section.testButton.topAnchor.constraint(equalTo: section.autoIndexCheckbox.bottomAnchor, constant: 14),
                section.testButton.leadingAnchor.constraint(equalTo: section.keyField.leadingAnchor),
                section.testButton.widthAnchor.constraint(equalToConstant: 136),
                section.testButton.heightAnchor.constraint(equalToConstant: controlHeight),
                section.testButton.bottomAnchor.constraint(lessThanOrEqualTo: page.bottomAnchor, constant: -8)
            ]
        )
    }
}
