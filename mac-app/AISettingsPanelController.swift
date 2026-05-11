import Cocoa

final class AISettingsPanelController {
    var onSaved: (() -> Void)?

    private weak var parentWindow: NSWindow?
    private var panel: SettingsPanel?
    private weak var modelPopup: NSPopUpButton?
    private weak var languagePopup: NSPopUpButton?
    private weak var themePopup: NSPopUpButton?
    private weak var secureKeyField: NSSecureTextField?
    private weak var plainKeyField: NSTextField?
    private weak var customEndpointLabel: NSTextField?
    private weak var customEndpointField: NSTextField?
    private weak var customModelLabel: NSTextField?
    private weak var customModelField: NSTextField?
    private var keyTopWithCustomConstraint: NSLayoutConstraint?
    private var keyTopWithoutCustomConstraint: NSLayoutConstraint?

    func show(attachedTo window: NSWindow) {
        parentWindow = window
        let selectedModel = AISettingsStore.selectedModel
        let settingsFontSize: CGFloat = 15
        let isDark = ReaderTheme.selected == .dark
        let panelBackground = isDark
            ? NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1)
            : NSColor.white
        let primaryText = isDark
            ? NSColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1)
            : NSColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1)
        let secondaryText = isDark
            ? NSColor(red: 0.58, green: 0.63, blue: 0.70, alpha: 1)
            : NSColor(red: 0.47, green: 0.50, blue: 0.58, alpha: 1)

        let panel = SettingsPanel(
            contentRect: NSRect(x: 0, y: 0, width: 740, height: 900),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.appearance = isDark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false

        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = panelBackground.cgColor
        content.layer?.borderWidth = isDark ? 1 : 0
        content.layer?.borderColor = NSColor(red: 0.22, green: 0.27, blue: 0.33, alpha: 1).cgColor
        content.layer?.cornerRadius = 12
        content.layer?.masksToBounds = false
        content.layer?.shadowColor = NSColor.black.cgColor
        content.layer?.shadowOpacity = 0.18
        content.layer?.shadowRadius = 24
        content.layer?.shadowOffset = CGSize(width: 0, height: -8)
        content.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = content

        let titleLabel = label(AppText.settings, size: settingsFontSize, weight: .semibold, color: primaryText)
        let closeButton = NSButton(title: "", target: self, action: #selector(cancel(_:)))
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: AppText.close)
        closeButton.isBordered = false
        closeButton.contentTintColor = primaryText
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let modelLabel = label(AppText.model, size: settingsFontSize, weight: .semibold, color: primaryText)
        let modelHelpLabel = label(AppText.modelHelp, size: settingsFontSize, color: secondaryText)
        let modelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        modelPopup.controlSize = .large
        modelPopup.font = NSFont.systemFont(ofSize: settingsFontSize)
        modelPopup.translatesAutoresizingMaskIntoConstraints = false
        for model in AISettingsStore.models {
            modelPopup.addItem(withTitle: model.displayName)
            modelPopup.lastItem?.representedObject = model.id
        }
        if let index = AISettingsStore.models.firstIndex(where: { $0.id == selectedModel.id }) {
            modelPopup.selectItem(at: index)
        }

        let customEndpointLabel = label(AppText.localized("自定义 URL", "Custom URL"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let customEndpointField = inputField(AISettingsStore.customEndpointString, placeholder: "https://api.example.com/v1/chat/completions", fontSize: settingsFontSize, textColor: primaryText, backgroundColor: fieldBackground(isDark: isDark))
        let customModelLabel = label(AppText.localized("模型 ID", "Model ID"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let customModelField = inputField(AISettingsStore.customModelName, placeholder: "gpt-4o-mini", fontSize: settingsFontSize, textColor: primaryText, backgroundColor: fieldBackground(isDark: isDark))

        let keyLabel = label("API Key", size: settingsFontSize, weight: .semibold, color: primaryText)
        let keyHelpLabel = label(AppText.keyHelp, size: settingsFontSize, color: secondaryText)
        let keyField = APIKeySecureTextField(string: AISettingsStore.apiKey(for: selectedModel))
        configureKeyField(keyField, placeholder: AppText.apiKeyPlaceholder, fontSize: settingsFontSize, textColor: primaryText, backgroundColor: fieldBackground(isDark: isDark))
        let plainKeyField = APIKeyTextField(string: AISettingsStore.apiKey(for: selectedModel))
        configureKeyField(plainKeyField, placeholder: AppText.apiKeyPlaceholder, fontSize: settingsFontSize, textColor: primaryText, backgroundColor: fieldBackground(isDark: isDark))
        plainKeyField.isHidden = true

        let eyeButton = NSButton(title: "", target: self, action: #selector(toggleAPIKeyVisibility(_:)))
        eyeButton.image = NSImage(systemSymbolName: "eye", accessibilityDescription: AppText.showAPIKey)
        eyeButton.isBordered = false
        eyeButton.contentTintColor = secondaryText
        eyeButton.translatesAutoresizingMaskIntoConstraints = false

        let languageLabel = label(AppText.language, size: settingsFontSize, weight: .semibold, color: primaryText)
        let languageHelpLabel = label(AppText.languageHelp, size: settingsFontSize, color: secondaryText)
        let languagePopup = popup(items: AppText.Language.allCases.map { ($0.title, $0.rawValue) }, selected: AppText.selectedLanguage.rawValue, fontSize: settingsFontSize)

        let themeLabel = label(AppText.localized("模式", "Mode"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let themeHelpLabel = label(ReaderTheme.selected.helpText, size: settingsFontSize, color: secondaryText)
        let themePopup = popup(items: ReaderTheme.allCases.map { ($0.title, $0.rawValue) }, selected: ReaderTheme.selected.rawValue, fontSize: settingsFontSize)

        let cancelButton = NSButton(title: AppText.cancel, target: self, action: #selector(cancel(_:)))
        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .large
        cancelButton.font = NSFont.systemFont(ofSize: settingsFontSize, weight: .medium)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        let saveButton = NSButton(title: AppText.confirm, target: self, action: #selector(save(_:)))
        saveButton.bezelStyle = .rounded
        saveButton.controlSize = .large
        saveButton.font = NSFont.systemFont(ofSize: settingsFontSize, weight: .semibold)
        saveButton.keyEquivalent = "\r"
        saveButton.identifier = NSUserInterfaceItemIdentifier("saveAISettings")
        saveButton.translatesAutoresizingMaskIntoConstraints = false

        modelPopup.target = self
        modelPopup.action = #selector(modelChanged(_:))
        modelPopup.identifier = NSUserInterfaceItemIdentifier("modelPopup")
        languagePopup.identifier = NSUserInterfaceItemIdentifier("languagePopup")
        themePopup.identifier = NSUserInterfaceItemIdentifier("themePopup")
        keyField.identifier = NSUserInterfaceItemIdentifier("keyField")
        plainKeyField.identifier = NSUserInterfaceItemIdentifier("plainKeyField")

        for view in [titleLabel, closeButton, modelLabel, modelPopup, modelHelpLabel, customEndpointLabel, customEndpointField, customModelLabel, customModelField, keyLabel, keyField, plainKeyField, eyeButton, keyHelpLabel, languageLabel, languagePopup, languageHelpLabel, themeLabel, themePopup, themeHelpLabel, cancelButton, saveButton] {
            content.addSubview(view)
        }

        let keyTopWithCustom = keyLabel.topAnchor.constraint(equalTo: customModelField.bottomAnchor, constant: 24)
        let keyTopWithoutCustom = keyLabel.topAnchor.constraint(equalTo: modelHelpLabel.bottomAnchor, constant: 30)
        keyTopWithCustomConstraint = keyTopWithCustom
        keyTopWithoutCustomConstraint = keyTopWithoutCustom

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 44),
            titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 48),
            titleLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -48),
            closeButton.topAnchor.constraint(equalTo: content.topAnchor, constant: 34),
            closeButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -34),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),

            modelLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 66),
            modelLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            modelPopup.topAnchor.constraint(equalTo: modelLabel.bottomAnchor, constant: 14),
            modelPopup.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            modelPopup.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            modelPopup.heightAnchor.constraint(equalToConstant: 54),
            modelHelpLabel.topAnchor.constraint(equalTo: modelPopup.bottomAnchor, constant: 12),
            modelHelpLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            modelHelpLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            customEndpointLabel.topAnchor.constraint(equalTo: modelHelpLabel.bottomAnchor, constant: 24),
            customEndpointLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            customEndpointField.topAnchor.constraint(equalTo: customEndpointLabel.bottomAnchor, constant: 10),
            customEndpointField.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            customEndpointField.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            customEndpointField.heightAnchor.constraint(equalToConstant: 34),
            customModelLabel.topAnchor.constraint(equalTo: customEndpointField.bottomAnchor, constant: 14),
            customModelLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            customModelField.topAnchor.constraint(equalTo: customModelLabel.bottomAnchor, constant: 10),
            customModelField.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            customModelField.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            customModelField.heightAnchor.constraint(equalToConstant: 34),

            keyTopWithCustom,
            keyLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            keyField.topAnchor.constraint(equalTo: keyLabel.bottomAnchor, constant: 10),
            keyField.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            keyField.trailingAnchor.constraint(equalTo: eyeButton.leadingAnchor, constant: -10),
            keyField.heightAnchor.constraint(equalToConstant: 34),
            plainKeyField.topAnchor.constraint(equalTo: keyField.topAnchor),
            plainKeyField.leadingAnchor.constraint(equalTo: keyField.leadingAnchor),
            plainKeyField.trailingAnchor.constraint(equalTo: keyField.trailingAnchor),
            plainKeyField.heightAnchor.constraint(equalTo: keyField.heightAnchor),
            eyeButton.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            eyeButton.centerYAnchor.constraint(equalTo: keyField.centerYAnchor),
            eyeButton.widthAnchor.constraint(equalToConstant: 28),
            eyeButton.heightAnchor.constraint(equalToConstant: 28),
            keyHelpLabel.topAnchor.constraint(equalTo: keyField.bottomAnchor, constant: 10),
            keyHelpLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            keyHelpLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            languageLabel.topAnchor.constraint(equalTo: keyHelpLabel.bottomAnchor, constant: 30),
            languageLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            languagePopup.topAnchor.constraint(equalTo: languageLabel.bottomAnchor, constant: 14),
            languagePopup.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            languagePopup.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            languagePopup.heightAnchor.constraint(equalToConstant: 54),
            languageHelpLabel.topAnchor.constraint(equalTo: languagePopup.bottomAnchor, constant: 12),
            languageHelpLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            languageHelpLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            themeLabel.topAnchor.constraint(equalTo: languageHelpLabel.bottomAnchor, constant: 26),
            themeLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            themePopup.topAnchor.constraint(equalTo: themeLabel.bottomAnchor, constant: 14),
            themePopup.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            themePopup.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            themePopup.heightAnchor.constraint(equalToConstant: 54),
            themeHelpLabel.topAnchor.constraint(equalTo: themePopup.bottomAnchor, constant: 12),
            themeHelpLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            themeHelpLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            saveButton.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            saveButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -36),
            saveButton.widthAnchor.constraint(equalToConstant: 118),
            saveButton.heightAnchor.constraint(equalToConstant: 44),
            cancelButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -16),
            cancelButton.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 118),
            cancelButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        self.panel = panel
        self.modelPopup = modelPopup
        self.languagePopup = languagePopup
        self.themePopup = themePopup
        self.secureKeyField = keyField
        self.plainKeyField = plainKeyField
        self.customEndpointLabel = customEndpointLabel
        self.customEndpointField = customEndpointField
        self.customModelLabel = customModelLabel
        self.customModelField = customModelField
        updateCustomModelFields(for: selectedModel.id)

        window.beginSheet(panel) { [weak self] _ in
            self?.panel = nil
        }
        DispatchQueue.main.async {
            panel.makeKey()
            panel.makeFirstResponder(keyField)
        }
    }

    @objc private func save(_ sender: NSButton) {
        guard let panel, let modelPopup, let keyField = currentKeyField() else { return }
        let modelID = modelPopup.selectedItem?.representedObject as? String ?? AISettingsStore.selectedModel.id
        let customEndpoint = customEndpointField?.stringValue ?? ""
        let customModelName = customModelField?.stringValue ?? ""
        if modelID == AISettingsStore.customModelID, let error = AISettingsStore.customValidationError(endpoint: customEndpoint, modelName: customModelName) {
            showValidationAlert(message: error, in: panel)
            return
        }

        if let rawLanguage = languagePopup?.selectedItem?.representedObject as? String,
           let language = AppText.Language(rawValue: rawLanguage) {
            AppText.selectedLanguage = language
        }
        if let rawTheme = themePopup?.selectedItem?.representedObject as? String,
           let theme = ReaderTheme(rawValue: rawTheme) {
            ReaderTheme.selected = theme
        }
        AISettingsStore.save(
            modelID: modelID,
            apiKey: keyField.stringValue,
            customEndpoint: customEndpoint,
            customModelName: customModelName
        )
        onSaved?()
        panel.sheetParent?.endSheet(panel)
    }

    @objc private func cancel(_ sender: NSButton) {
        guard let panel else { return }
        panel.sheetParent?.endSheet(panel)
    }

    @objc private func modelChanged(_ sender: NSPopUpButton) {
        guard let modelID = sender.selectedItem?.representedObject as? String,
              let model = AISettingsStore.models.first(where: { $0.id == modelID }) else { return }
        let key = AISettingsStore.apiKey(for: model)
        secureKeyField?.stringValue = key
        plainKeyField?.stringValue = key
        updateCustomModelFields(for: modelID)
    }

    @objc private func toggleAPIKeyVisibility(_ sender: NSButton) {
        guard let secureField = secureKeyField, let plainField = plainKeyField else { return }
        if plainField.isHidden {
            plainField.stringValue = secureField.stringValue
            plainField.isHidden = false
            secureField.isHidden = true
            sender.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: AppText.hideAPIKey)
            parentWindow?.makeFirstResponder(plainField)
        } else {
            secureField.stringValue = plainField.stringValue
            secureField.isHidden = false
            plainField.isHidden = true
            sender.image = NSImage(systemSymbolName: "eye", accessibilityDescription: AppText.showAPIKey)
            parentWindow?.makeFirstResponder(secureField)
        }
    }

    private func currentKeyField() -> NSTextField? {
        if let plainField = plainKeyField, !plainField.isHidden {
            return plainField
        }
        return secureKeyField
    }

    private func updateCustomModelFields(for modelID: String) {
        let visible = modelID == AISettingsStore.customModelID
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

    private func showValidationAlert(message: String, in panel: NSWindow) {
        let alert = NSAlert()
        alert.messageText = AppText.localized("设置无效", "Invalid Settings")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppText.confirm)
        alert.beginSheetModal(for: panel)
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func inputField(_ text: String, placeholder: String, fontSize: CGFloat, textColor: NSColor, backgroundColor: NSColor) -> NSTextField {
        let field = NSTextField(string: text)
        field.placeholderString = placeholder
        field.controlSize = .small
        field.font = NSFont.systemFont(ofSize: fontSize)
        field.isBordered = true
        field.drawsBackground = true
        field.isEditable = true
        field.isSelectable = true
        field.textColor = textColor
        field.backgroundColor = backgroundColor
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    private func configureKeyField(_ field: NSTextField, placeholder: String, fontSize: CGFloat, textColor: NSColor, backgroundColor: NSColor) {
        field.placeholderString = placeholder
        field.controlSize = .small
        field.font = NSFont.systemFont(ofSize: fontSize)
        field.isBordered = true
        field.drawsBackground = true
        field.isEditable = true
        field.isSelectable = true
        field.isEnabled = true
        field.textColor = textColor
        field.backgroundColor = backgroundColor
        field.translatesAutoresizingMaskIntoConstraints = false
    }

    private func popup(items: [(String, String)], selected: String, fontSize: CGFloat) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = .large
        popup.font = NSFont.systemFont(ofSize: fontSize)
        popup.translatesAutoresizingMaskIntoConstraints = false
        for item in items {
            popup.addItem(withTitle: item.0)
            popup.lastItem?.representedObject = item.1
        }
        if let index = items.firstIndex(where: { $0.1 == selected }) {
            popup.selectItem(at: index)
        }
        return popup
    }

    private func fieldBackground(isDark: Bool) -> NSColor {
        isDark ? NSColor(red: 0.08, green: 0.10, blue: 0.13, alpha: 1) : .white
    }
}
