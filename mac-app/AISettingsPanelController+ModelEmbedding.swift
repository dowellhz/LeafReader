import Cocoa

extension AISettingsPanelController {
    @objc func modelChanged(_ sender: NSPopUpButton) {
        guard let modelID = sender.selectedItem?.representedObject as? String,
              let model = AISettingsStore.models.first(where: { $0.id == modelID }) else { return }
        let key = AISettingsStore.apiKey(for: model)
        secureKeyField?.stringValue = key
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
        let visible = modelID == AISettingsStore.customModelID
        customModelContainer?.isHidden = !visible
        customEndpointLabel?.isHidden = !visible
        customEndpointField?.isHidden = !visible
        customModelLabel?.isHidden = !visible
        customModelField?.isHidden = !visible
        customEndpointField?.isEnabled = visible
        customModelField?.isEnabled = visible
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
        alert.applyLeafWhiteStyle()
        alert.beginSheetModal(for: panel)
    }
}
