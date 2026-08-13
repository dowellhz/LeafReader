import Cocoa

struct AISettingsModelSection {
    let modelLabel: NSTextField
    let modelPopup: NSPopUpButton
    let modelHelpLabel: NSTextField
    let customModelContainer: NSView
    let customEndpointLabel: NSTextField
    let customEndpointField: NSTextField
    let customModelLabel: NSTextField
    let customModelField: NSTextField
    let keyLabel: NSTextField
    let keyField: APIKeySecureTextField
    let keyHelpLabel: NSTextField
    let testChatButton: NSButton

    var pageViews: [NSView] {
        [modelLabel, modelPopup, modelHelpLabel, customModelContainer, keyLabel, keyField, keyHelpLabel, testChatButton]
    }
}

struct AISettingsModelLayout {
    let constraints: [NSLayoutConstraint]
    let keyTopWithCustom: NSLayoutConstraint
    let keyTopWithoutCustom: NSLayoutConstraint
    let customModelContainerHeight: NSLayoutConstraint
    let customModelLabelTopToEndpoint: NSLayoutConstraint
    let customModelLabelTopToContainer: NSLayoutConstraint
    let customModelLabelCenterYToContainer: NSLayoutConstraint
}

extension AISettingsPanelController {
    func makeModelSection(
        selectedModel: AIModelConfig,
        settingsFontSize: CGFloat,
        primaryText: NSColor,
        secondaryText: NSColor
    ) -> AISettingsModelSection {
        let modelLabel = label(AppText.model, size: settingsFontSize, weight: .semibold, color: primaryText)
        let modelHelpLabel = label(AppText.modelHelp, size: settingsFontSize, color: secondaryText)
        modelHelpLabel.isHidden = true
        let modelPopup = popup(
            items: AISettingsStore.models.map { ($0.displayName, $0.id) },
            selected: selectedModel.id,
            fontSize: settingsFontSize
        )
        modelPopup.target = self
        modelPopup.action = #selector(modelChanged(_:))
        modelPopup.identifier = Identifiers.modelPopup

        let customEndpointLabel = label(AppText.localized("自定义 / Azure URL", "Custom / Azure URL"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let customEndpointField = inputField(
            AISettingsStore.customEndpointString,
            placeholder: "https://resource.openai.azure.com/openai/deployments/deployment/chat/completions?api-version=2024-10-21",
            fontSize: settingsFontSize,
            textColor: primaryText,
            backgroundColor: fieldBackground()
        )
        let customModelLabel = label(AppText.localized("模型 ID / Azure 部署名", "Model ID / Azure Deployment"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let initialModelFieldValue: String
        if selectedModel.id == AISettingsStore.ollamaModelID {
            initialModelFieldValue = AISettingsStore.ollamaModelName
        } else if selectedModel.id == AISettingsStore.localOpenAIModelID {
            initialModelFieldValue = AISettingsStore.localOpenAIModelName
        } else {
            initialModelFieldValue = AISettingsStore.customModelName
        }
        let customModelField = inputField(
            initialModelFieldValue,
            placeholder: "gpt-4o-mini",
            fontSize: settingsFontSize,
            textColor: primaryText,
            backgroundColor: fieldBackground()
        )
        let customModelContainer = settingsCard()
        for view in [customEndpointLabel, customEndpointField, customModelLabel, customModelField] {
            customModelContainer.addSubview(view)
        }

        let keyLabel = label("API Key", size: settingsFontSize, weight: .semibold, color: primaryText)
        let keyHelpLabel = label(AppText.keyHelp, size: settingsFontSize, color: secondaryText)
        keyHelpLabel.isHidden = true
        let keyField = APIKeySecureTextField(string: AISettingsStore.apiKey(for: selectedModel))
        configureKeyField(
            keyField,
            placeholder: AppText.apiKeyPlaceholder,
            fontSize: settingsFontSize,
            textColor: primaryText,
            backgroundColor: fieldBackground()
        )
        keyField.identifier = Identifiers.keyField
        let testChatButton = settingsActionButton(
            title: AppText.localized("测试模型连接", "Test Chat"),
            target: self,
            action: #selector(testChatConnection(_:))
        )
        testChatButton.font = AppFont.semibold(ofSize: settingsFontSize)

        return AISettingsModelSection(
            modelLabel: modelLabel,
            modelPopup: modelPopup,
            modelHelpLabel: modelHelpLabel,
            customModelContainer: customModelContainer,
            customEndpointLabel: customEndpointLabel,
            customEndpointField: customEndpointField,
            customModelLabel: customModelLabel,
            customModelField: customModelField,
            keyLabel: keyLabel,
            keyField: keyField,
            keyHelpLabel: keyHelpLabel,
            testChatButton: testChatButton
        )
    }

    func modelConstraints(
        for section: AISettingsModelSection,
        page: NSView,
        labelColumnWidth: CGFloat,
        fieldWidth: CGFloat,
        inputHeight: CGFloat,
        controlHeight: CGFloat
    ) -> AISettingsModelLayout {
        let keyTopWithCustom = section.keyLabel.topAnchor.constraint(equalTo: section.customModelContainer.bottomAnchor, constant: 22)
        let keyTopWithoutCustom = section.keyLabel.topAnchor.constraint(equalTo: section.modelPopup.bottomAnchor, constant: 34)
        let customModelContainerHeight = section.customModelContainer.heightAnchor.constraint(equalToConstant: 116)
        let customModelLabelTopToEndpoint = section.customModelLabel.topAnchor.constraint(equalTo: section.customEndpointLabel.bottomAnchor, constant: 22)
        let customModelLabelTopToContainer = section.customModelLabel.topAnchor.constraint(equalTo: section.customModelContainer.topAnchor, constant: 14)
        let customModelLabelCenterYToContainer = section.customModelLabel.centerYAnchor.constraint(equalTo: section.customModelContainer.centerYAnchor)
        customModelLabelTopToContainer.isActive = false
        customModelLabelCenterYToContainer.isActive = false

        let constraints = [
            section.modelLabel.topAnchor.constraint(equalTo: page.topAnchor, constant: 4),
            section.modelLabel.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            section.modelLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            section.modelPopup.topAnchor.constraint(equalTo: page.topAnchor, constant: 4),
            section.modelPopup.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: labelColumnWidth),
            section.modelPopup.widthAnchor.constraint(equalToConstant: fieldWidth),
            section.modelPopup.heightAnchor.constraint(equalToConstant: controlHeight),
            section.modelHelpLabel.topAnchor.constraint(equalTo: section.modelPopup.bottomAnchor, constant: 4),
            section.modelHelpLabel.leadingAnchor.constraint(equalTo: section.modelPopup.leadingAnchor),
            section.modelHelpLabel.widthAnchor.constraint(equalToConstant: fieldWidth),
            section.customModelContainer.topAnchor.constraint(equalTo: section.modelPopup.bottomAnchor, constant: 14),
            section.customModelContainer.leadingAnchor.constraint(equalTo: section.modelPopup.leadingAnchor),
            section.customModelContainer.widthAnchor.constraint(equalToConstant: fieldWidth),
            customModelContainerHeight,
            section.customEndpointLabel.topAnchor.constraint(equalTo: section.customModelContainer.topAnchor, constant: 14),
            section.customEndpointLabel.leadingAnchor.constraint(equalTo: section.customModelContainer.leadingAnchor, constant: 14),
            section.customEndpointLabel.widthAnchor.constraint(equalToConstant: 180),
            section.customEndpointField.centerYAnchor.constraint(equalTo: section.customEndpointLabel.centerYAnchor),
            section.customEndpointField.leadingAnchor.constraint(equalTo: section.customModelContainer.leadingAnchor, constant: 204),
            section.customEndpointField.trailingAnchor.constraint(equalTo: section.customModelContainer.trailingAnchor, constant: -14),
            section.customEndpointField.heightAnchor.constraint(equalToConstant: inputHeight),
            customModelLabelTopToEndpoint,
            section.customModelLabel.leadingAnchor.constraint(equalTo: section.customEndpointLabel.leadingAnchor),
            section.customModelLabel.widthAnchor.constraint(equalToConstant: 180),
            section.customModelField.centerYAnchor.constraint(equalTo: section.customModelLabel.centerYAnchor),
            section.customModelField.leadingAnchor.constraint(equalTo: section.customEndpointField.leadingAnchor),
            section.customModelField.trailingAnchor.constraint(equalTo: section.customEndpointField.trailingAnchor),
            section.customModelField.heightAnchor.constraint(equalToConstant: inputHeight),
            keyTopWithCustom,
            section.keyLabel.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            section.keyLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            section.keyField.topAnchor.constraint(equalTo: section.keyLabel.topAnchor),
            section.keyField.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: labelColumnWidth),
            section.keyField.widthAnchor.constraint(equalToConstant: fieldWidth),
            section.keyField.heightAnchor.constraint(equalToConstant: inputHeight),
            section.keyHelpLabel.topAnchor.constraint(equalTo: section.keyField.bottomAnchor, constant: 4),
            section.keyHelpLabel.leadingAnchor.constraint(equalTo: section.keyField.leadingAnchor),
            section.keyHelpLabel.widthAnchor.constraint(equalToConstant: fieldWidth),
            section.testChatButton.topAnchor.constraint(equalTo: section.keyField.bottomAnchor, constant: 18),
            section.testChatButton.leadingAnchor.constraint(equalTo: section.keyField.leadingAnchor),
            section.testChatButton.widthAnchor.constraint(equalToConstant: 136),
            section.testChatButton.heightAnchor.constraint(equalToConstant: controlHeight),
            section.testChatButton.bottomAnchor.constraint(lessThanOrEqualTo: page.bottomAnchor, constant: -8)
        ]
        return AISettingsModelLayout(
            constraints: constraints,
            keyTopWithCustom: keyTopWithCustom,
            keyTopWithoutCustom: keyTopWithoutCustom,
            customModelContainerHeight: customModelContainerHeight,
            customModelLabelTopToEndpoint: customModelLabelTopToEndpoint,
            customModelLabelTopToContainer: customModelLabelTopToContainer,
            customModelLabelCenterYToContainer: customModelLabelCenterYToContainer
        )
    }
}
