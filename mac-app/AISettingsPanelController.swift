import Cocoa

private final class SettingsTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              let editor = currentEditor(),
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        switch key {
        case "a":
            editor.selectAll(nil)
            return true
        case "c":
            copySelection(from: editor)
            return true
        case "x":
            copySelection(from: editor)
            editor.delete(nil)
            return true
        case "v":
            pasteClipboard(into: editor)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    private func copySelection(from editor: NSText) {
        let selectedRange = editor.selectedRange
        guard selectedRange.length > 0,
              let range = Range(selectedRange, in: editor.string) else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(editor.string[range]), forType: .string)
    }

    private func pasteClipboard(into editor: NSText) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        editor.replaceCharacters(in: editor.selectedRange, with: text)
    }
}

final class AISettingsPanelController {
    var onSaved: (() -> Void)?

    private weak var parentWindow: NSWindow?
    private var panel: SettingsPanel?
    private weak var modelPopup: NSPopUpButton?
    private weak var languagePopup: NSPopUpButton?
    private weak var themePopup: NSPopUpButton?
    private weak var secureKeyField: NSSecureTextField?
    private weak var customEndpointLabel: NSTextField?
    private weak var customEndpointField: NSTextField?
    private weak var customModelLabel: NSTextField?
    private weak var customModelField: NSTextField?
    private weak var embeddingProviderPopup: NSPopUpButton?
    private weak var embeddingEndpointLabel: NSTextField?
    private weak var embeddingEndpointField: NSTextField?
    private weak var embeddingModelField: NSTextField?
    private weak var embeddingKeyField: NSSecureTextField?
    private weak var cacheStatusLabel: NSTextField?
    private var keyTopWithCustomConstraint: NSLayoutConstraint?
    private var keyTopWithoutCustomConstraint: NSLayoutConstraint?
    private var embeddingModelTopWithCustomEndpointConstraint: NSLayoutConstraint?
    private var embeddingModelTopWithoutCustomEndpointConstraint: NSLayoutConstraint?
    private var isClosing = false
    private var shouldNotifySavedAfterClose = false

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
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 720),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.appearance = isDark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true

        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = panelBackground.cgColor
        content.layer?.borderWidth = 1.5
        content.layer?.borderColor = (isDark
            ? NSColor(red: 0.32, green: 0.38, blue: 0.46, alpha: 1)
            : NSColor(red: 0.78, green: 0.82, blue: 0.90, alpha: 1)
        ).cgColor
        content.layer?.cornerRadius = 12
        content.layer?.masksToBounds = false
        content.layer?.shadowColor = NSColor.black.cgColor
        content.layer?.shadowOpacity = isDark ? 0.34 : 0.22
        content.layer?.shadowRadius = 28
        content.layer?.shadowOffset = CGSize(width: 0, height: -10)
        content.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = content

        let titleLabel = label(AppText.settings, size: settingsFontSize, weight: .semibold, color: primaryText)
        let closeButton = NSButton(title: "", target: self, action: #selector(cancel(_:)))
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: AppText.close)
        closeButton.isBordered = false
        closeButton.contentTintColor = primaryText
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.verticalScrollElasticity = .allowed
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let formContent = NSView()
        formContent.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = formContent

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

        let customEndpointLabel = label(AppText.localized("自定义 / Azure URL", "Custom / Azure URL"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let customEndpointField = inputField(AISettingsStore.customEndpointString, placeholder: "https://resource.openai.azure.com/openai/deployments/deployment/chat/completions?api-version=2024-10-21", fontSize: settingsFontSize, textColor: primaryText, backgroundColor: fieldBackground(isDark: isDark))
        let customModelLabel = label(AppText.localized("模型 ID / Azure 部署名", "Model ID / Azure Deployment"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let customModelField = inputField(AISettingsStore.customModelName, placeholder: "gpt-4o-mini", fontSize: settingsFontSize, textColor: primaryText, backgroundColor: fieldBackground(isDark: isDark))

        let keyLabel = label("API Key", size: settingsFontSize, weight: .semibold, color: primaryText)
        let keyHelpLabel = label(AppText.keyHelp, size: settingsFontSize, color: secondaryText)
        let keyField = APIKeySecureTextField(string: AISettingsStore.apiKey(for: selectedModel))
        configureKeyField(keyField, placeholder: AppText.apiKeyPlaceholder, fontSize: settingsFontSize, textColor: primaryText, backgroundColor: fieldBackground(isDark: isDark))

        let languageLabel = label(AppText.language, size: settingsFontSize, weight: .semibold, color: primaryText)
        let languageHelpLabel = label(AppText.languageHelp, size: settingsFontSize, color: secondaryText)
        let languagePopup = popup(items: AppText.Language.allCases.map { ($0.title, $0.rawValue) }, selected: AppText.selectedLanguage.rawValue, fontSize: settingsFontSize)

        let themeLabel = label(AppText.localized("模式", "Mode"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let themeHelpLabel = label(ReaderTheme.selected.helpText, size: settingsFontSize, color: secondaryText)
        let themePopup = popup(items: ReaderTheme.allCases.map { ($0.title, $0.rawValue) }, selected: ReaderTheme.selected.rawValue, fontSize: settingsFontSize)

        let selectedEmbeddingEndpoint = AISettingsStore.selectedEmbeddingEndpointOption
        let embeddingLabel = label(AppText.localized("向量服务", "Embedding Service"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let embeddingProviderPopup = popup(items: AISettingsStore.embeddingEndpointOptions.map { ($0.title, $0.id) }, selected: selectedEmbeddingEndpoint.id, fontSize: settingsFontSize)
        let embeddingEndpointLabel = label(AppText.localized("接口 URL", "Endpoint URL"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let embeddingEndpointField = inputField(AISettingsStore.embeddingEndpointString, placeholder: "https://api.openai.com/v1/embeddings", fontSize: settingsFontSize, textColor: primaryText, backgroundColor: fieldBackground(isDark: isDark))
        let embeddingModelNameLabel = label(AppText.localized("向量模型", "Embedding Model"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let embeddingModelField = inputField(AISettingsStore.embeddingModelName, placeholder: AISettingsStore.fallbackEmbeddingModelName, fontSize: settingsFontSize, textColor: primaryText, backgroundColor: fieldBackground(isDark: isDark))
        let embeddingKeyLabel = label(AppText.localized("向量 API Key", "Embedding API Key"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let embeddingKeyField = APIKeySecureTextField(string: AISettingsStore.embeddingAPIKey)
        configureKeyField(embeddingKeyField, placeholder: AppText.apiKeyPlaceholder, fontSize: settingsFontSize, textColor: primaryText, backgroundColor: fieldBackground(isDark: isDark))
        let embeddingHelpLabel = label(AppText.localized("用于 PDF 向量检索。聊天模型和向量模型可以使用不同 API Key。默认使用 OpenAI text-embedding-3-small，也可填兼容接口。", "Used for PDF vector retrieval. Chat and embedding models can use different API keys. Defaults to OpenAI text-embedding-3-small; compatible endpoints can be used."), size: settingsFontSize, color: secondaryText)

        let cacheLabel = label(AppText.localized("AI 向量缓存", "AI Vector Cache"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let cacheStatusLabel = label(vectorCacheStatusText(), size: settingsFontSize, color: secondaryText)
        let clearVectorCacheButton = NSButton(title: AppText.localized("清除 AI 向量缓存", "Clear AI Vector Cache"), target: self, action: #selector(clearVectorCache(_:)))
        clearVectorCacheButton.bezelStyle = .rounded
        clearVectorCacheButton.controlSize = .regular
        clearVectorCacheButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        clearVectorCacheButton.translatesAutoresizingMaskIntoConstraints = false

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
        embeddingProviderPopup.target = self
        embeddingProviderPopup.action = #selector(embeddingProviderChanged(_:))
        modelPopup.identifier = NSUserInterfaceItemIdentifier("modelPopup")
        languagePopup.identifier = NSUserInterfaceItemIdentifier("languagePopup")
        themePopup.identifier = NSUserInterfaceItemIdentifier("themePopup")
        keyField.identifier = NSUserInterfaceItemIdentifier("keyField")
        embeddingProviderPopup.identifier = NSUserInterfaceItemIdentifier("embeddingProviderPopup")
        embeddingEndpointField.identifier = NSUserInterfaceItemIdentifier("embeddingEndpointField")
        embeddingModelField.identifier = NSUserInterfaceItemIdentifier("embeddingModelField")
        embeddingKeyField.identifier = NSUserInterfaceItemIdentifier("embeddingKeyField")

        for view in [titleLabel, closeButton, scrollView, cancelButton, saveButton] {
            content.addSubview(view)
        }
        for view in [modelLabel, modelPopup, modelHelpLabel, customEndpointLabel, customEndpointField, customModelLabel, customModelField, keyLabel, keyField, keyHelpLabel, languageLabel, languagePopup, languageHelpLabel, themeLabel, themePopup, themeHelpLabel, embeddingLabel, embeddingProviderPopup, embeddingEndpointLabel, embeddingEndpointField, embeddingModelNameLabel, embeddingModelField, embeddingKeyLabel, embeddingKeyField, embeddingHelpLabel, cacheLabel, cacheStatusLabel, clearVectorCacheButton] {
            formContent.addSubview(view)
        }

        let keyTopWithCustom = keyLabel.topAnchor.constraint(equalTo: customModelField.bottomAnchor, constant: 18)
        let keyTopWithoutCustom = keyLabel.topAnchor.constraint(equalTo: modelHelpLabel.bottomAnchor, constant: 22)
        let formMinHeight = formContent.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor)
        formMinHeight.priority = .defaultLow
        let fieldWidthMultiplier: CGFloat = 0.70
        let labelColumnWidth: CGFloat = 132
        let embeddingModelTopWithCustomEndpoint = embeddingModelNameLabel.topAnchor.constraint(equalTo: embeddingEndpointField.bottomAnchor, constant: 10)
        let embeddingModelTopWithoutCustomEndpoint = embeddingModelNameLabel.topAnchor.constraint(equalTo: embeddingProviderPopup.bottomAnchor, constant: 10)
        keyTopWithCustomConstraint = keyTopWithCustom
        keyTopWithoutCustomConstraint = keyTopWithoutCustom
        embeddingModelTopWithCustomEndpointConstraint = embeddingModelTopWithCustomEndpoint
        embeddingModelTopWithoutCustomEndpointConstraint = embeddingModelTopWithoutCustomEndpoint

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 40),
            titleLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -40),
            closeButton.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            closeButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 18),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 40),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -40),
            scrollView.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -18),
            formContent.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            formContent.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            formContent.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            formContent.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            formMinHeight,

            modelLabel.topAnchor.constraint(equalTo: formContent.topAnchor, constant: 4),
            modelLabel.leadingAnchor.constraint(equalTo: formContent.leadingAnchor),
            modelLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            modelPopup.topAnchor.constraint(equalTo: formContent.topAnchor, constant: 4),
            modelPopup.leadingAnchor.constraint(equalTo: formContent.leadingAnchor, constant: labelColumnWidth),
            modelPopup.widthAnchor.constraint(equalTo: formContent.widthAnchor, multiplier: fieldWidthMultiplier),
            modelPopup.heightAnchor.constraint(equalToConstant: 44),
            modelHelpLabel.topAnchor.constraint(equalTo: modelPopup.bottomAnchor, constant: 8),
            modelHelpLabel.leadingAnchor.constraint(equalTo: modelPopup.leadingAnchor),
            modelHelpLabel.trailingAnchor.constraint(equalTo: formContent.trailingAnchor, constant: -8),

            customEndpointLabel.topAnchor.constraint(equalTo: modelHelpLabel.bottomAnchor, constant: 18),
            customEndpointLabel.leadingAnchor.constraint(equalTo: formContent.leadingAnchor),
            customEndpointLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            customEndpointField.topAnchor.constraint(equalTo: customEndpointLabel.topAnchor),
            customEndpointField.leadingAnchor.constraint(equalTo: formContent.leadingAnchor, constant: labelColumnWidth),
            customEndpointField.widthAnchor.constraint(equalTo: formContent.widthAnchor, multiplier: fieldWidthMultiplier),
            customEndpointField.heightAnchor.constraint(equalToConstant: 34),
            customModelLabel.topAnchor.constraint(equalTo: customEndpointField.bottomAnchor, constant: 10),
            customModelLabel.leadingAnchor.constraint(equalTo: formContent.leadingAnchor),
            customModelLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            customModelField.topAnchor.constraint(equalTo: customModelLabel.topAnchor),
            customModelField.leadingAnchor.constraint(equalTo: formContent.leadingAnchor, constant: labelColumnWidth),
            customModelField.widthAnchor.constraint(equalTo: formContent.widthAnchor, multiplier: fieldWidthMultiplier),
            customModelField.heightAnchor.constraint(equalToConstant: 34),

            keyTopWithCustom,
            keyLabel.leadingAnchor.constraint(equalTo: formContent.leadingAnchor),
            keyLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            keyField.topAnchor.constraint(equalTo: keyLabel.topAnchor),
            keyField.leadingAnchor.constraint(equalTo: formContent.leadingAnchor, constant: labelColumnWidth),
            keyField.widthAnchor.constraint(equalTo: formContent.widthAnchor, multiplier: fieldWidthMultiplier),
            keyField.heightAnchor.constraint(equalToConstant: 34),
            keyHelpLabel.topAnchor.constraint(equalTo: keyField.bottomAnchor, constant: 8),
            keyHelpLabel.leadingAnchor.constraint(equalTo: keyField.leadingAnchor),
            keyHelpLabel.trailingAnchor.constraint(equalTo: formContent.trailingAnchor, constant: -8),

            languageLabel.topAnchor.constraint(equalTo: keyHelpLabel.bottomAnchor, constant: 22),
            languageLabel.leadingAnchor.constraint(equalTo: formContent.leadingAnchor),
            languageLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            languagePopup.topAnchor.constraint(equalTo: languageLabel.topAnchor),
            languagePopup.leadingAnchor.constraint(equalTo: formContent.leadingAnchor, constant: labelColumnWidth),
            languagePopup.widthAnchor.constraint(equalTo: formContent.widthAnchor, multiplier: fieldWidthMultiplier),
            languagePopup.heightAnchor.constraint(equalToConstant: 44),
            languageHelpLabel.topAnchor.constraint(equalTo: languagePopup.bottomAnchor, constant: 8),
            languageHelpLabel.leadingAnchor.constraint(equalTo: languagePopup.leadingAnchor),
            languageHelpLabel.trailingAnchor.constraint(equalTo: formContent.trailingAnchor, constant: -8),

            themeLabel.topAnchor.constraint(equalTo: languageHelpLabel.bottomAnchor, constant: 20),
            themeLabel.leadingAnchor.constraint(equalTo: formContent.leadingAnchor),
            themeLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            themePopup.topAnchor.constraint(equalTo: themeLabel.topAnchor),
            themePopup.leadingAnchor.constraint(equalTo: formContent.leadingAnchor, constant: labelColumnWidth),
            themePopup.widthAnchor.constraint(equalTo: formContent.widthAnchor, multiplier: fieldWidthMultiplier),
            themePopup.heightAnchor.constraint(equalToConstant: 44),
            themeHelpLabel.topAnchor.constraint(equalTo: themePopup.bottomAnchor, constant: 8),
            themeHelpLabel.leadingAnchor.constraint(equalTo: themePopup.leadingAnchor),
            themeHelpLabel.trailingAnchor.constraint(equalTo: formContent.trailingAnchor, constant: -8),

            embeddingLabel.topAnchor.constraint(equalTo: themeHelpLabel.bottomAnchor, constant: 20),
            embeddingLabel.leadingAnchor.constraint(equalTo: formContent.leadingAnchor),
            embeddingLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            embeddingProviderPopup.topAnchor.constraint(equalTo: embeddingLabel.topAnchor),
            embeddingProviderPopup.leadingAnchor.constraint(equalTo: formContent.leadingAnchor, constant: labelColumnWidth),
            embeddingProviderPopup.widthAnchor.constraint(equalTo: formContent.widthAnchor, multiplier: fieldWidthMultiplier),
            embeddingProviderPopup.heightAnchor.constraint(equalToConstant: 44),
            embeddingEndpointLabel.topAnchor.constraint(equalTo: embeddingProviderPopup.bottomAnchor, constant: 10),
            embeddingEndpointLabel.leadingAnchor.constraint(equalTo: formContent.leadingAnchor),
            embeddingEndpointLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            embeddingEndpointField.topAnchor.constraint(equalTo: embeddingEndpointLabel.topAnchor),
            embeddingEndpointField.leadingAnchor.constraint(equalTo: formContent.leadingAnchor, constant: labelColumnWidth),
            embeddingEndpointField.widthAnchor.constraint(equalTo: formContent.widthAnchor, multiplier: fieldWidthMultiplier),
            embeddingEndpointField.heightAnchor.constraint(equalToConstant: 34),
            embeddingModelTopWithCustomEndpoint,
            embeddingModelNameLabel.leadingAnchor.constraint(equalTo: formContent.leadingAnchor),
            embeddingModelNameLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            embeddingModelField.topAnchor.constraint(equalTo: embeddingModelNameLabel.topAnchor),
            embeddingModelField.leadingAnchor.constraint(equalTo: formContent.leadingAnchor, constant: labelColumnWidth),
            embeddingModelField.widthAnchor.constraint(equalTo: formContent.widthAnchor, multiplier: fieldWidthMultiplier),
            embeddingModelField.heightAnchor.constraint(equalToConstant: 34),
            embeddingKeyLabel.topAnchor.constraint(equalTo: embeddingModelField.bottomAnchor, constant: 10),
            embeddingKeyLabel.leadingAnchor.constraint(equalTo: formContent.leadingAnchor),
            embeddingKeyLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            embeddingKeyField.topAnchor.constraint(equalTo: embeddingKeyLabel.topAnchor),
            embeddingKeyField.leadingAnchor.constraint(equalTo: formContent.leadingAnchor, constant: labelColumnWidth),
            embeddingKeyField.widthAnchor.constraint(equalTo: formContent.widthAnchor, multiplier: fieldWidthMultiplier),
            embeddingKeyField.heightAnchor.constraint(equalToConstant: 34),
            embeddingHelpLabel.topAnchor.constraint(equalTo: embeddingKeyField.bottomAnchor, constant: 8),
            embeddingHelpLabel.leadingAnchor.constraint(equalTo: embeddingKeyField.leadingAnchor),
            embeddingHelpLabel.trailingAnchor.constraint(equalTo: formContent.trailingAnchor, constant: -8),

            cacheLabel.topAnchor.constraint(equalTo: embeddingHelpLabel.bottomAnchor, constant: 20),
            cacheLabel.leadingAnchor.constraint(equalTo: formContent.leadingAnchor),
            cacheStatusLabel.topAnchor.constraint(equalTo: cacheLabel.bottomAnchor, constant: 8),
            cacheStatusLabel.leadingAnchor.constraint(equalTo: formContent.leadingAnchor),
            cacheStatusLabel.trailingAnchor.constraint(equalTo: formContent.trailingAnchor, constant: -8),
            clearVectorCacheButton.topAnchor.constraint(equalTo: cacheStatusLabel.bottomAnchor, constant: 10),
            clearVectorCacheButton.leadingAnchor.constraint(equalTo: formContent.leadingAnchor),
            clearVectorCacheButton.widthAnchor.constraint(equalToConstant: 180),
            clearVectorCacheButton.heightAnchor.constraint(equalToConstant: 32),
            clearVectorCacheButton.bottomAnchor.constraint(equalTo: formContent.bottomAnchor, constant: -8),

            saveButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -40),
            saveButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -28),
            saveButton.widthAnchor.constraint(equalToConstant: 104),
            saveButton.heightAnchor.constraint(equalToConstant: 38),
            cancelButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -16),
            cancelButton.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 104),
            cancelButton.heightAnchor.constraint(equalToConstant: 38)
        ])

        self.panel = panel
        self.modelPopup = modelPopup
        self.languagePopup = languagePopup
        self.themePopup = themePopup
        self.secureKeyField = keyField
        self.customEndpointLabel = customEndpointLabel
        self.customEndpointField = customEndpointField
        self.customModelLabel = customModelLabel
        self.customModelField = customModelField
        self.embeddingProviderPopup = embeddingProviderPopup
        self.embeddingEndpointLabel = embeddingEndpointLabel
        self.embeddingEndpointField = embeddingEndpointField
        self.embeddingModelField = embeddingModelField
        self.embeddingKeyField = embeddingKeyField
        self.cacheStatusLabel = cacheStatusLabel
        updateCustomModelFields(for: selectedModel.id)
        updateEmbeddingEndpointFields(for: selectedEmbeddingEndpoint.id, fillDefaults: false)

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

    private func showPanel(_ panel: NSWindow, attachedTo parent: NSWindow) {
        let parentFrame = parent.frame
        let origin = NSPoint(
            x: parentFrame.midX - panel.frame.width / 2,
            y: parentFrame.midY - panel.frame.height / 2
        )
        panel.setFrameOrigin(origin)
        parent.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func save(_ sender: NSButton) {
        guard let panel, let modelPopup, let keyField = secureKeyField else { return }
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
        let embeddingEndpoint = selectedEmbeddingEndpointForSave()?.endpoint ?? (embeddingEndpointField?.stringValue ?? "")
        AISettingsStore.saveEmbedding(
            endpoint: embeddingEndpoint,
            modelName: embeddingModelField?.stringValue ?? "",
            apiKey: embeddingKeyField?.stringValue ?? ""
        )
        closePanel(notifySaved: true)
    }

    @objc private func cancel(_ sender: NSButton) {
        closePanel(notifySaved: false)
    }

    private func closePanel(notifySaved: Bool) {
        guard let panel, !isClosing else { return }
        isClosing = true
        shouldNotifySavedAfterClose = notifySaved
        parentWindow?.removeChildWindow(panel)
        panel.orderOut(nil)
        self.panel = nil
        isClosing = false
        let shouldNotifySaved = shouldNotifySavedAfterClose
        shouldNotifySavedAfterClose = false
        if shouldNotifySaved {
            DispatchQueue.main.async { [weak self] in
                self?.onSaved?()
            }
        }
    }

    @objc private func clearVectorCache(_ sender: NSButton) {
        let alert = NSAlert()
        alert.messageText = AppText.localized("清除 AI 向量缓存？", "Clear AI vector cache?")
        alert.informativeText = AppText.localized(
            "这会删除本机已缓存的 PDF 向量索引。之后再次使用文档问答时，会按需重新生成。",
            "This deletes locally cached PDF vector indexes. They will be regenerated on demand when document Q&A is used again."
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppText.localized("清除", "Clear"))
        alert.addButton(withTitle: AppText.cancel)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            PDFEmbeddingStore()?.deleteAll()
            cacheStatusLabel?.stringValue = vectorCacheStatusText()
        }
    }

    @objc private func modelChanged(_ sender: NSPopUpButton) {
        guard let modelID = sender.selectedItem?.representedObject as? String,
              let model = AISettingsStore.models.first(where: { $0.id == modelID }) else { return }
        let key = AISettingsStore.apiKey(for: model)
        secureKeyField?.stringValue = key
        updateCustomModelFields(for: modelID)
    }

    @objc private func embeddingProviderChanged(_ sender: NSPopUpButton) {
        guard let optionID = sender.selectedItem?.representedObject as? String else { return }
        updateEmbeddingEndpointFields(for: optionID, fillDefaults: true)
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

    private func updateEmbeddingEndpointFields(for optionID: String, fillDefaults: Bool) {
        guard let option = AISettingsStore.embeddingEndpointOptions.first(where: { $0.id == optionID }) else { return }
        let isCustom = option.id == AISettingsStore.customEmbeddingEndpointID
        embeddingEndpointLabel?.isHidden = !isCustom
        embeddingEndpointField?.isHidden = !isCustom
        embeddingEndpointField?.isEnabled = isCustom
        embeddingModelTopWithCustomEndpointConstraint?.isActive = isCustom
        embeddingModelTopWithoutCustomEndpointConstraint?.isActive = !isCustom

        if isCustom {
            if fillDefaults {
                embeddingEndpointField?.stringValue = ""
                embeddingModelField?.stringValue = ""
                embeddingKeyField?.stringValue = ""
            }
        } else {
            embeddingEndpointField?.stringValue = option.endpoint
            if fillDefaults || embeddingModelField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                embeddingModelField?.stringValue = option.defaultModel
            }
        }
        panel?.contentView?.layoutSubtreeIfNeeded()
    }

    private func selectedEmbeddingEndpointForSave() -> AISettingsStore.EmbeddingEndpointOption? {
        guard let optionID = embeddingProviderPopup?.selectedItem?.representedObject as? String,
              let option = AISettingsStore.embeddingEndpointOptions.first(where: { $0.id == optionID }) else {
            return nil
        }
        if option.id == AISettingsStore.customEmbeddingEndpointID {
            return AISettingsStore.EmbeddingEndpointOption(id: option.id, title: option.title, endpoint: embeddingEndpointField?.stringValue ?? "", defaultModel: "")
        }
        return option
    }

    private func showValidationAlert(message: String, in panel: NSWindow) {
        let alert = NSAlert()
        alert.messageText = AppText.localized("设置无效", "Invalid Settings")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppText.confirm)
        alert.runModal()
    }

    private func vectorCacheStatusText() -> String {
        guard let store = PDFEmbeddingStore() else {
            return AppText.localized("缓存不可用", "Cache unavailable")
        }
        let size = formatBytes(store.cacheSizeBytes())
        let count = store.documentCount()
        return AppText.localized(
            "当前占用 \(size)，已缓存 \(count) 本 PDF。超过 1GB 会自动删除最久未使用的文档缓存。",
            "Using \(size), \(count) cached PDF(s). When it exceeds 1GB, the least recently used document cache is removed automatically."
        )
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        if index == 0 {
            return "\(Int(value)) \(units[index])"
        }
        return String(format: "%.1f %@", value, units[index])
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func inputField(_ text: String, placeholder: String, fontSize: CGFloat, textColor: NSColor, backgroundColor: NSColor) -> NSTextField {
        let field = SettingsTextField(string: text)
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

    private func comboField(items: [String], selected: String, placeholder: String, fontSize: CGFloat, textColor: NSColor, backgroundColor: NSColor) -> NSComboBox {
        let comboBox = NSComboBox()
        comboBox.addItems(withObjectValues: items)
        comboBox.stringValue = selected.isEmpty ? placeholder : selected
        comboBox.placeholderString = placeholder
        comboBox.completes = true
        comboBox.usesDataSource = false
        comboBox.numberOfVisibleItems = min(8, max(1, items.count))
        comboBox.controlSize = .small
        comboBox.font = NSFont.systemFont(ofSize: fontSize)
        comboBox.isBordered = true
        comboBox.drawsBackground = true
        comboBox.isEditable = true
        comboBox.isSelectable = true
        comboBox.textColor = textColor
        comboBox.backgroundColor = backgroundColor
        comboBox.translatesAutoresizingMaskIntoConstraints = false
        return comboBox
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
