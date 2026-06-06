import Cocoa

extension AISettingsPanelController {
    @objc func modelChanged(_ sender: NSPopUpButton) {
        guard let modelID = sender.selectedItem?.representedObject as? String,
              let model = AISettingsStore.models.first(where: { $0.id == modelID }) else { return }
        let key = AISettingsStore.apiKey(for: model)
        secureKeyField?.stringValue = key
        secureKeyField?.isEnabled = model.acceptsAPIKey
        updateCustomModelFields(for: modelID)
    }

    @objc func embeddingProviderChanged(_ sender: NSPopUpButton) {
        if !currentEmbeddingOptionID.isEmpty {
            pendingEmbeddingKeys[currentEmbeddingOptionID] = embeddingKeyField?.stringValue ?? ""
        }
        if let selectedID = sender.selectedItem?.representedObject as? String,
           selectedID != AISettingsStore.customEmbeddingEndpointID,
           embeddingEndpointField?.isEnabled == true {
            lastCustomEmbeddingEndpoint = embeddingEndpointField?.stringValue ?? ""
            lastCustomEmbeddingModel = embeddingModelField?.stringValue ?? ""
        }
        guard let optionID = sender.selectedItem?.representedObject as? String else { return }
        currentEmbeddingOptionID = optionID
        updateEmbeddingEndpointFields(for: optionID, fillDefaults: true)
    }

    func updateCustomModelFields(for modelID: String) {
        let isCustom = modelID == AISettingsStore.customModelID
        let isOllama = modelID == AISettingsStore.ollamaModelID
        let isLocalOpenAI = modelID == AISettingsStore.localOpenAIModelID
        let showsEndpoint = isCustom || isLocalOpenAI
        let visible = showsEndpoint || isOllama
        customModelContainer?.isHidden = !visible
        customEndpointLabel?.isHidden = !showsEndpoint
        customEndpointField?.isHidden = !showsEndpoint
        customModelLabel?.isHidden = !visible
        customModelField?.isHidden = !visible
        customEndpointField?.isEnabled = showsEndpoint
        customModelField?.isEnabled = visible
        customEndpointLabel?.stringValue = isLocalOpenAI
            ? AppText.localized("本地 URL", "Local URL")
            : AppText.localized("自定义 / Azure URL", "Custom / Azure URL")
        customModelLabel?.stringValue = (isOllama || isLocalOpenAI)
            ? AppText.localized("模型 ID", "Model ID")
            : AppText.localized("模型 ID / Azure 部署名", "Model ID / Azure Deployment")
        customEndpointField?.placeholderString = isLocalOpenAI
            ? "http://127.0.0.1:8000/v1"
            : "https://resource.openai.azure.com/openai/deployments/deployment/chat/completions?api-version=2024-10-21"
        customModelField?.placeholderString = isOllama ? "llama3.1" : (isLocalOpenAI ? "gemma-4-e4b-it-4bit" : "gpt-4o-mini")
        if isOllama {
            customModelField?.stringValue = AISettingsStore.ollamaModelName
        } else if isLocalOpenAI {
            customEndpointField?.stringValue = AISettingsStore.localOpenAIEndpointString
            customModelField?.stringValue = AISettingsStore.localOpenAIModelName
        } else if isCustom {
            customEndpointField?.stringValue = AISettingsStore.customEndpointString
            customModelField?.stringValue = AISettingsStore.customModelName
        }
        customModelContainerHeightConstraint?.constant = isOllama ? 62 : 116
        customModelLabelTopToEndpointConstraint?.isActive = showsEndpoint
        customModelLabelTopToContainerConstraint?.isActive = false
        customModelLabelCenterYToContainerConstraint?.isActive = isOllama
        keyTopWithCustomConstraint?.isActive = visible
        keyTopWithoutCustomConstraint?.isActive = !visible
        panel?.contentView?.layoutSubtreeIfNeeded()
    }

    func updateEmbeddingEndpointFields(for optionID: String, fillDefaults: Bool) {
        guard let option = AISettingsStore.embeddingEndpointOptions.first(where: { $0.id == optionID }) else { return }
        let isCustom = option.id == AISettingsStore.customEmbeddingEndpointID
        embeddingEndpointContainer?.isHidden = false
        embeddingEndpointLabel?.isHidden = false
        embeddingEndpointField?.isHidden = false
        embeddingEndpointField?.isEnabled = isCustom
        embeddingModelTopWithCustomEndpointConstraint?.isActive = true
        embeddingModelTopWithoutCustomEndpointConstraint?.isActive = false

        if isCustom {
            if fillDefaults {
                embeddingEndpointField?.stringValue = lastCustomEmbeddingEndpoint
                embeddingModelField?.stringValue = lastCustomEmbeddingModel
            }
        } else {
            embeddingEndpointField?.stringValue = option.endpoint
            if fillDefaults || embeddingModelField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                embeddingModelField?.stringValue = option.defaultModel
            }
        }
        if fillDefaults {
            let savedKey = pendingEmbeddingKeys[option.id] ?? AISettingsStore.embeddingAPIKey(for: option.id)
            embeddingKeyField?.stringValue = savedKey
        }
        panel?.contentView?.layoutSubtreeIfNeeded()
    }

    func selectedEmbeddingEndpointForSave() -> AISettingsStore.EmbeddingEndpointOption? {
        guard let optionID = embeddingProviderPopup?.selectedItem?.representedObject as? String,
              let option = AISettingsStore.embeddingEndpointOptions.first(where: { $0.id == optionID }) else {
            return nil
        }
        if option.id == AISettingsStore.customEmbeddingEndpointID {
            return AISettingsStore.EmbeddingEndpointOption(id: option.id, title: option.title, endpoint: embeddingEndpointField?.stringValue ?? "", defaultModel: "")
        }
        return option
    }

    func showValidationAlert(message: String, in panel: NSWindow) {
        let alert = NSAlert()
        alert.messageText = AppText.localized("设置无效", "Invalid Settings")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppText.confirm)
        alert.applyLeafStyle()
        alert.beginSheetModal(for: panel)
    }
}
