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

private final class SettingsTabsView: NSView {
    var onSelectionChanged: ((Int) -> Void)?

    private let labels: [String]
    private var buttons: [NSButton] = []
    private var selectedIndex = 0

    init(labels: [String]) {
        self.labels = labels
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        labels = []
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.985, green: 0.988, blue: 0.995, alpha: 1).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(red: 0.82, green: 0.84, blue: 0.88, alpha: 1).cgColor
        layer?.cornerRadius = 16
        layer?.masksToBounds = true

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])

        for (index, text) in labels.enumerated() {
            let button = NSButton(title: text, target: self, action: #selector(selectTab(_:)))
            button.tag = index
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 12
            button.layer?.masksToBounds = true
            button.translatesAutoresizingMaskIntoConstraints = false
            buttons.append(button)
            stack.addArrangedSubview(button)
        }
        updateAppearance()
    }

    @objc private func selectTab(_ sender: NSButton) {
        selectedIndex = sender.tag
        updateAppearance()
        onSelectionChanged?(selectedIndex)
    }

    private func updateAppearance() {
        for (index, button) in buttons.enumerated() {
            let selected = index == selectedIndex
            button.layer?.backgroundColor = selected
                ? NSColor.white.cgColor
                : NSColor.clear.cgColor
            button.attributedTitle = NSAttributedString(
                string: labels[index],
                attributes: [
                    .font: AppFont.semibold(ofSize: 18),
                    .foregroundColor: selected
                        ? NSColor(red: 0.02, green: 0.48, blue: 0.98, alpha: 1)
                        : NSColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1)
                ]
            )
        }
    }
}

private final class VerticalOnlyClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrained = super.constrainBoundsRect(proposedBounds)
        constrained.origin.x = 0
        return constrained
    }

    override var bounds: NSRect {
        get {
            var current = super.bounds
            current.origin.x = 0
            return current
        }
        set {
            var next = newValue
            next.origin.x = 0
            super.bounds = next
        }
    }
}

final class AISettingsPanelController {
    var onSaved: (() -> Void)?
    var currentVectorIndexStatus: (() -> String)?
    var onStartVectorIndex: (() -> Void)?
    var onToggleVectorIndexPaused: (() -> Void)?
    var onCancelVectorIndex: (() -> Void)?
    var onClearCurrentVectorIndex: (() -> Void)?
    var onClearCurrentWordRecords: (() -> Void)?

    private weak var parentWindow: NSWindow?
    private var panel: SettingsPanel?
    private weak var settingsTabControl: NSSegmentedControl?
    private weak var settingsScrollView: NSScrollView?
    private weak var basicPage: NSView?
    private weak var modelPage: NSView?
    private weak var embeddingPage: NSView?
    private weak var cachePage: NSView?
    private weak var modelPopup: NSPopUpButton?
    private weak var languagePopup: NSPopUpButton?
    private weak var themePopup: NSPopUpButton?
    private weak var secureKeyField: NSSecureTextField?
    private weak var customModelContainer: NSView?
    private weak var customEndpointLabel: NSTextField?
    private weak var customEndpointField: NSTextField?
    private weak var customModelLabel: NSTextField?
    private weak var customModelField: NSTextField?
    private weak var embeddingProviderPopup: NSPopUpButton?
    private weak var embeddingEndpointContainer: NSView?
    private weak var embeddingEndpointLabel: NSTextField?
    private weak var embeddingEndpointField: NSTextField?
    private weak var embeddingModelField: NSTextField?
    private weak var embeddingKeyField: NSSecureTextField?
    private weak var speakSelectedWordCheckbox: NSButton?
    private weak var autoEmbeddingIndexCheckbox: NSButton?
    private weak var cacheStatusLabel: NSTextField?
    private weak var currentIndexStatusLabel: NSTextField?
    private var keyTopWithCustomConstraint: NSLayoutConstraint?
    private var keyTopWithoutCustomConstraint: NSLayoutConstraint?
    private var embeddingModelTopWithCustomEndpointConstraint: NSLayoutConstraint?
    private var embeddingModelTopWithoutCustomEndpointConstraint: NSLayoutConstraint?
    private var isClosing = false
    private var shouldNotifySavedAfterClose = false
    private var appActivationObserver: NSObjectProtocol?

    deinit {
        removeAppActivationObserver()
    }

    func show(attachedTo window: NSWindow) {
        parentWindow = window
        let selectedModel = AISettingsStore.selectedModel
        let settingsFontSize: CGFloat = 14
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
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.appearance = isDark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary]

        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = panelBackground.cgColor
        content.layer?.borderWidth = 1.5
        content.layer?.borderColor = (isDark
            ? NSColor(red: 0.32, green: 0.38, blue: 0.46, alpha: 1)
            : NSColor(red: 0.78, green: 0.82, blue: 0.90, alpha: 1)
        ).cgColor
        content.layer?.cornerRadius = 18
        content.layer?.masksToBounds = false
        content.layer?.shadowColor = NSColor.black.cgColor
        content.layer?.shadowOpacity = isDark ? 0.42 : 0.24
        content.layer?.shadowRadius = 32
        content.layer?.shadowOffset = CGSize(width: 0, height: -12)
        content.frame = NSRect(origin: .zero, size: panel.contentRect(forFrameRect: panel.frame).size)
        content.autoresizingMask = [.width, .height]
        content.translatesAutoresizingMaskIntoConstraints = true
        panel.contentView = content

        let titleLabel = label(AppText.settings, size: settingsFontSize, weight: .semibold, color: primaryText)
        let closeButton = NSButton(title: "", target: self, action: #selector(cancel(_:)))
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: AppText.close)
        closeButton.isBordered = false
        closeButton.contentTintColor = primaryText
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let tabControl = NSSegmentedControl(
            labels: [
            AppText.localized("基础", "General"),
            AppText.localized("模型", "Model"),
            AppText.localized("向量", "Vector"),
            AppText.localized("缓存", "Cache")
            ],
            trackingMode: .selectOne,
            target: self,
            action: #selector(settingsSegmentChanged(_:))
        )
        tabControl.selectedSegment = 0
        tabControl.segmentStyle = .rounded
        tabControl.controlSize = .large
        tabControl.font = AppFont.semibold(ofSize: 18)
        tabControl.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.verticalScrollElasticity = .allowed
        scrollView.horizontalScrollElasticity = .none
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentView = VerticalOnlyClipView()

        let formContent = NSView()
        formContent.translatesAutoresizingMaskIntoConstraints = false
        formContent.setContentHuggingPriority(.required, for: .horizontal)
        formContent.setContentCompressionResistancePriority(.required, for: .horizontal)
        scrollView.documentView = formContent

        let basicPage = NSView()
        basicPage.translatesAutoresizingMaskIntoConstraints = false
        let modelPage = NSView()
        modelPage.translatesAutoresizingMaskIntoConstraints = false
        let embeddingPage = NSView()
        embeddingPage.translatesAutoresizingMaskIntoConstraints = false
        let cachePage = NSView()
        cachePage.translatesAutoresizingMaskIntoConstraints = false
        for page in [basicPage, modelPage, embeddingPage, cachePage] {
            formContent.addSubview(page)
        }
        modelPage.isHidden = true
        embeddingPage.isHidden = true
        cachePage.isHidden = true

        let modelLabel = label(AppText.model, size: settingsFontSize, weight: .semibold, color: primaryText)
        let modelHelpLabel = label(AppText.modelHelp, size: settingsFontSize, color: secondaryText)
        modelHelpLabel.isHidden = true
        let modelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        modelPopup.controlSize = .large
        modelPopup.font = AppFont.semibold(ofSize: settingsFontSize)
        modelPopup.translatesAutoresizingMaskIntoConstraints = false
        for model in AISettingsStore.models {
            modelPopup.addItem(withTitle: model.displayName)
            modelPopup.lastItem?.representedObject = model.id
            modelPopup.lastItem?.isEnabled = true
        }
        modelPopup.isEnabled = true
        modelPopup.menu?.autoenablesItems = false
        if let index = AISettingsStore.models.firstIndex(where: { $0.id == selectedModel.id }) {
            modelPopup.selectItem(at: index)
        }

        let customEndpointLabel = label(AppText.localized("自定义 / Azure URL", "Custom / Azure URL"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let customEndpointField = inputField(AISettingsStore.customEndpointString, placeholder: "https://resource.openai.azure.com/openai/deployments/deployment/chat/completions?api-version=2024-10-21", fontSize: settingsFontSize, textColor: primaryText, backgroundColor: fieldBackground(isDark: isDark))
        let customModelLabel = label(AppText.localized("模型 ID / Azure 部署名", "Model ID / Azure Deployment"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let customModelField = inputField(AISettingsStore.customModelName, placeholder: "gpt-4o-mini", fontSize: settingsFontSize, textColor: primaryText, backgroundColor: fieldBackground(isDark: isDark))
        let customModelContainer = settingsCard(isDark: isDark)

        let keyLabel = label("API Key", size: settingsFontSize, weight: .semibold, color: primaryText)
        let keyHelpLabel = label(AppText.keyHelp, size: settingsFontSize, color: secondaryText)
        keyHelpLabel.isHidden = true
        let keyField = APIKeySecureTextField(string: AISettingsStore.apiKey(for: selectedModel))
        configureKeyField(keyField, placeholder: AppText.apiKeyPlaceholder, fontSize: settingsFontSize, textColor: primaryText, backgroundColor: fieldBackground(isDark: isDark))

        let languageLabel = label(AppText.language, size: settingsFontSize, weight: .semibold, color: primaryText)
        let languageHelpLabel = label(AppText.languageHelp, size: settingsFontSize, color: secondaryText)
        languageHelpLabel.isHidden = true
        let languagePopup = popup(items: AppText.Language.allCases.map { ($0.title, $0.rawValue) }, selected: AppText.selectedLanguage.rawValue, fontSize: settingsFontSize)

        let themeLabel = label(AppText.localized("模式", "Mode"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let themeHelpLabel = label(ReaderTheme.selected.helpText, size: settingsFontSize, color: secondaryText)
        themeHelpLabel.isHidden = true
        let themePopup = popup(items: ReaderTheme.allCases.map { ($0.title, $0.rawValue) }, selected: ReaderTheme.selected.rawValue, fontSize: settingsFontSize)
        let speakSelectedWordCheckbox = NSButton(
            checkboxWithTitle: AppText.localized("学英语时播放单词发音", "Play word audio in Learn English"),
            target: nil,
            action: nil
        )
        speakSelectedWordCheckbox.font = AppFont.semibold(ofSize: settingsFontSize)
        speakSelectedWordCheckbox.lineBreakMode = .byTruncatingTail
        speakSelectedWordCheckbox.state = AISettingsStore.speakSelectedWordEnabled ? .on : .off
        speakSelectedWordCheckbox.translatesAutoresizingMaskIntoConstraints = false

        let selectedEmbeddingEndpoint = AISettingsStore.selectedEmbeddingEndpointOption
        let embeddingLabel = label(AppText.localized("向量服务", "Embedding Service"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let embeddingProviderPopup = popup(items: AISettingsStore.embeddingEndpointOptions.map { ($0.title, $0.id) }, selected: selectedEmbeddingEndpoint.id, fontSize: settingsFontSize)
        let embeddingEndpointLabel = label(AppText.localized("接口 URL", "Endpoint URL"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let embeddingEndpointField = inputField(AISettingsStore.embeddingEndpointString, placeholder: "https://api.openai.com/v1/embeddings", fontSize: settingsFontSize, textColor: primaryText, backgroundColor: fieldBackground(isDark: isDark))
        let embeddingEndpointContainer = settingsCard(isDark: isDark)
        let embeddingModelNameLabel = label(AppText.localized("向量模型", "Embedding Model"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let embeddingModelField = inputField(AISettingsStore.embeddingModelName, placeholder: AISettingsStore.fallbackEmbeddingModelName, fontSize: settingsFontSize, textColor: primaryText, backgroundColor: fieldBackground(isDark: isDark))
        let embeddingKeyLabel = label(AppText.localized("向量 API Key", "Embedding API Key"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let embeddingKeyField = APIKeySecureTextField(string: AISettingsStore.embeddingAPIKey)
        configureKeyField(embeddingKeyField, placeholder: AppText.apiKeyPlaceholder, fontSize: settingsFontSize, textColor: primaryText, backgroundColor: fieldBackground(isDark: isDark))
        let embeddingHelpLabel = label(AppText.localized("用于 PDF、EPUB 和 DOCX 向量检索。聊天模型和向量模型可以使用不同 API Key。默认使用 OpenAI text-embedding-3-small，也可填兼容接口。", "Used for PDF, EPUB, and DOCX vector retrieval. Chat and embedding models can use different API keys. Defaults to OpenAI text-embedding-3-small; compatible endpoints can be used."), size: settingsFontSize, color: secondaryText)
        let autoEmbeddingIndexCheckbox = NSButton(checkboxWithTitle: AppText.localized("打开书后自动生成向量索引", "Automatically build vector index after opening a book"), target: nil, action: nil)
        autoEmbeddingIndexCheckbox.font = AppFont.semibold(ofSize: settingsFontSize)
        autoEmbeddingIndexCheckbox.lineBreakMode = .byTruncatingTail
        autoEmbeddingIndexCheckbox.state = AISettingsStore.autoEmbeddingIndexEnabled ? .on : .off
        autoEmbeddingIndexCheckbox.translatesAutoresizingMaskIntoConstraints = false

        let testChatButton = NSButton(title: AppText.localized("测试模型连接", "Test Chat"), target: self, action: #selector(testChatConnection(_:)))
        testChatButton.bezelStyle = .rounded
        testChatButton.controlSize = .large
        testChatButton.font = AppFont.semibold(ofSize: settingsFontSize)
        testChatButton.lineBreakMode = .byTruncatingTail
        testChatButton.translatesAutoresizingMaskIntoConstraints = false
        let testEmbeddingButton = NSButton(title: AppText.localized("测试向量连接", "Test Embedding"), target: self, action: #selector(testEmbeddingConnection(_:)))
        testEmbeddingButton.bezelStyle = .rounded
        testEmbeddingButton.controlSize = .large
        testEmbeddingButton.font = AppFont.semibold(ofSize: settingsFontSize)
        testEmbeddingButton.lineBreakMode = .byTruncatingTail
        testEmbeddingButton.translatesAutoresizingMaskIntoConstraints = false

        let cacheLabel = label(AppText.localized("AI 向量缓存", "AI Vector Cache"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let cacheStatusLabel = label(vectorCacheStatusText(), size: settingsFontSize, color: secondaryText)
        let clearVectorCacheButton = NSButton(title: AppText.localized("清除 AI 向量缓存", "Clear AI Vector Cache"), target: self, action: #selector(clearVectorCache(_:)))
        clearVectorCacheButton.bezelStyle = .rounded
        clearVectorCacheButton.controlSize = .large
        clearVectorCacheButton.font = AppFont.semibold(ofSize: settingsFontSize)
        clearVectorCacheButton.lineBreakMode = .byTruncatingTail
        clearVectorCacheButton.translatesAutoresizingMaskIntoConstraints = false

        let currentIndexLabel = label(AppText.localized("当前书索引", "Current Book Index"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let currentIndexStatusLabel = label(currentVectorIndexStatus?() ?? AppText.localized("未打开文档", "No document open"), size: settingsFontSize, color: secondaryText)
        currentIndexStatusLabel.maximumNumberOfLines = 2
        currentIndexStatusLabel.lineBreakMode = .byWordWrapping
        let startIndexButton = NSButton(title: AppText.localized("开始/继续生成", "Start / Resume"), target: self, action: #selector(startCurrentVectorIndex(_:)))
        startIndexButton.bezelStyle = .rounded
        startIndexButton.controlSize = .large
        startIndexButton.font = AppFont.semibold(ofSize: settingsFontSize)
        startIndexButton.translatesAutoresizingMaskIntoConstraints = false
        let pauseIndexButton = NSButton(title: AppText.localized("暂停/继续", "Pause / Resume"), target: self, action: #selector(toggleCurrentVectorIndex(_:)))
        pauseIndexButton.bezelStyle = .rounded
        pauseIndexButton.controlSize = .large
        pauseIndexButton.font = AppFont.semibold(ofSize: settingsFontSize)
        pauseIndexButton.translatesAutoresizingMaskIntoConstraints = false
        let cancelIndexButton = NSButton(title: AppText.localized("取消生成", "Cancel"), target: self, action: #selector(cancelCurrentVectorIndex(_:)))
        cancelIndexButton.bezelStyle = .rounded
        cancelIndexButton.controlSize = .large
        cancelIndexButton.font = AppFont.semibold(ofSize: settingsFontSize)
        cancelIndexButton.translatesAutoresizingMaskIntoConstraints = false
        let clearCurrentIndexButton = NSButton(title: AppText.localized("清除当前书索引", "Clear Current Book"), target: self, action: #selector(clearCurrentVectorIndex(_:)))
        clearCurrentIndexButton.bezelStyle = .rounded
        clearCurrentIndexButton.controlSize = .large
        clearCurrentIndexButton.font = AppFont.semibold(ofSize: settingsFontSize)
        clearCurrentIndexButton.translatesAutoresizingMaskIntoConstraints = false
        let clearCurrentWordsButton = NSButton(title: AppText.localized("清除当前书单词记录", "Clear Current Book Words"), target: self, action: #selector(clearCurrentWordRecords(_:)))
        clearCurrentWordsButton.bezelStyle = .rounded
        clearCurrentWordsButton.controlSize = .large
        clearCurrentWordsButton.font = AppFont.semibold(ofSize: settingsFontSize)
        clearCurrentWordsButton.translatesAutoresizingMaskIntoConstraints = false
        let currentIndexCard = settingsCard(isDark: isDark)
        let vectorCacheCard = settingsCard(isDark: isDark)

        let cancelButton = NSButton(title: AppText.cancel, target: self, action: #selector(cancel(_:)))
        styleSettingsActionButton(
            cancelButton,
            backgroundColor: .white,
            titleColor: NSColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1),
            borderColor: NSColor(red: 0.80, green: 0.83, blue: 0.88, alpha: 1)
        )
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        let saveButton = NSButton(title: AppText.confirm, target: self, action: #selector(save(_:)))
        styleSettingsActionButton(
            saveButton,
            backgroundColor: NSColor(red: 0.02, green: 0.48, blue: 0.98, alpha: 1),
            titleColor: .white,
            borderColor: NSColor(red: 0.02, green: 0.48, blue: 0.98, alpha: 1)
        )
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

        for view in [titleLabel, closeButton, tabControl, scrollView, cancelButton, saveButton] {
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
        for view in [cacheLabel, cacheStatusLabel, clearVectorCacheButton] {
            vectorCacheCard.addSubview(view)
        }
        for view in [languageLabel, languagePopup, languageHelpLabel, themeLabel, themePopup, themeHelpLabel, speakSelectedWordCheckbox] {
            basicPage.addSubview(view)
        }
        for view in [modelLabel, modelPopup, modelHelpLabel, customModelContainer, keyLabel, keyField, keyHelpLabel, testChatButton] {
            modelPage.addSubview(view)
        }
        for view in [embeddingLabel, embeddingProviderPopup, embeddingEndpointContainer, embeddingModelNameLabel, embeddingModelField, embeddingKeyLabel, embeddingKeyField, embeddingHelpLabel, autoEmbeddingIndexCheckbox, testEmbeddingButton] {
            embeddingPage.addSubview(view)
        }
        for view in [currentIndexCard, vectorCacheCard] {
            cachePage.addSubview(view)
        }

        let keyTopWithCustom = keyLabel.topAnchor.constraint(equalTo: customModelContainer.bottomAnchor, constant: 22)
        let keyTopWithoutCustom = keyLabel.topAnchor.constraint(equalTo: modelPopup.bottomAnchor, constant: 34)
        let labelColumnWidth: CGFloat = 110
        let fieldWidth: CGFloat = 440
        let formWidth = labelColumnWidth + fieldWidth
        let controlHeight: CGFloat = 40
        let inputHeight: CGFloat = 36
        let embeddingModelTopWithCustomEndpoint = embeddingModelNameLabel.topAnchor.constraint(equalTo: embeddingEndpointContainer.bottomAnchor, constant: 10)
        let embeddingModelTopWithoutCustomEndpoint = embeddingModelNameLabel.topAnchor.constraint(equalTo: embeddingProviderPopup.bottomAnchor, constant: 8)
        keyTopWithCustomConstraint = keyTopWithCustom
        keyTopWithoutCustomConstraint = keyTopWithoutCustom
        embeddingModelTopWithCustomEndpointConstraint = embeddingModelTopWithCustomEndpoint
        embeddingModelTopWithoutCustomEndpointConstraint = embeddingModelTopWithoutCustomEndpoint

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 34),
            titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 44),
            titleLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -54),
            closeButton.topAnchor.constraint(equalTo: content.topAnchor, constant: 30),
            closeButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -36),
            closeButton.widthAnchor.constraint(equalToConstant: 34),
            closeButton.heightAnchor.constraint(equalToConstant: 34),

            tabControl.topAnchor.constraint(equalTo: content.topAnchor, constant: 82),
            tabControl.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            tabControl.widthAnchor.constraint(equalToConstant: 440),
            tabControl.heightAnchor.constraint(equalToConstant: 40),

            scrollView.topAnchor.constraint(equalTo: content.topAnchor, constant: 154),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 44),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -44),
            scrollView.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -22),
            formContent.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
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

            speakSelectedWordCheckbox.topAnchor.constraint(equalTo: themePopup.bottomAnchor, constant: 16),
            speakSelectedWordCheckbox.leadingAnchor.constraint(equalTo: themePopup.leadingAnchor),
            speakSelectedWordCheckbox.widthAnchor.constraint(equalToConstant: fieldWidth),
            speakSelectedWordCheckbox.bottomAnchor.constraint(lessThanOrEqualTo: basicPage.bottomAnchor, constant: -8),

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

            currentIndexCard.topAnchor.constraint(equalTo: cachePage.topAnchor, constant: 4),
            currentIndexCard.leadingAnchor.constraint(equalTo: cachePage.leadingAnchor),
            currentIndexCard.widthAnchor.constraint(equalToConstant: formWidth),
            currentIndexCard.heightAnchor.constraint(equalToConstant: 218),
            currentIndexLabel.topAnchor.constraint(equalTo: currentIndexCard.topAnchor, constant: 16),
            currentIndexLabel.leadingAnchor.constraint(equalTo: currentIndexCard.leadingAnchor, constant: 18),
            currentIndexStatusLabel.topAnchor.constraint(equalTo: currentIndexLabel.bottomAnchor, constant: 6),
            currentIndexStatusLabel.leadingAnchor.constraint(equalTo: currentIndexLabel.leadingAnchor),
            currentIndexStatusLabel.widthAnchor.constraint(equalToConstant: formWidth - 36),
            startIndexButton.topAnchor.constraint(equalTo: currentIndexStatusLabel.bottomAnchor, constant: 10),
            startIndexButton.leadingAnchor.constraint(equalTo: currentIndexLabel.leadingAnchor),
            startIndexButton.widthAnchor.constraint(equalToConstant: 150),
            startIndexButton.heightAnchor.constraint(equalToConstant: controlHeight),
            pauseIndexButton.centerYAnchor.constraint(equalTo: startIndexButton.centerYAnchor),
            pauseIndexButton.leadingAnchor.constraint(equalTo: startIndexButton.trailingAnchor, constant: 8),
            pauseIndexButton.widthAnchor.constraint(equalToConstant: 112),
            pauseIndexButton.heightAnchor.constraint(equalToConstant: controlHeight),
            cancelIndexButton.centerYAnchor.constraint(equalTo: startIndexButton.centerYAnchor),
            cancelIndexButton.leadingAnchor.constraint(equalTo: pauseIndexButton.trailingAnchor, constant: 8),
            cancelIndexButton.widthAnchor.constraint(equalToConstant: 104),
            cancelIndexButton.heightAnchor.constraint(equalToConstant: controlHeight),
            clearCurrentIndexButton.topAnchor.constraint(equalTo: startIndexButton.bottomAnchor, constant: 10),
            clearCurrentIndexButton.leadingAnchor.constraint(equalTo: currentIndexLabel.leadingAnchor),
            clearCurrentIndexButton.widthAnchor.constraint(equalToConstant: 170),
            clearCurrentIndexButton.heightAnchor.constraint(equalToConstant: controlHeight),
            clearCurrentWordsButton.centerYAnchor.constraint(equalTo: clearCurrentIndexButton.centerYAnchor),
            clearCurrentWordsButton.leadingAnchor.constraint(equalTo: clearCurrentIndexButton.trailingAnchor, constant: 8),
            clearCurrentWordsButton.widthAnchor.constraint(equalToConstant: 190),
            clearCurrentWordsButton.heightAnchor.constraint(equalToConstant: controlHeight),

            vectorCacheCard.topAnchor.constraint(equalTo: currentIndexCard.bottomAnchor, constant: 14),
            vectorCacheCard.leadingAnchor.constraint(equalTo: cachePage.leadingAnchor),
            vectorCacheCard.widthAnchor.constraint(equalToConstant: formWidth),
            vectorCacheCard.heightAnchor.constraint(equalToConstant: 122),
            cacheLabel.topAnchor.constraint(equalTo: vectorCacheCard.topAnchor, constant: 16),
            cacheLabel.leadingAnchor.constraint(equalTo: vectorCacheCard.leadingAnchor, constant: 18),
            cacheStatusLabel.topAnchor.constraint(equalTo: cacheLabel.bottomAnchor, constant: 6),
            cacheStatusLabel.leadingAnchor.constraint(equalTo: cacheLabel.leadingAnchor),
            cacheStatusLabel.widthAnchor.constraint(equalToConstant: formWidth - 36),
            clearVectorCacheButton.topAnchor.constraint(equalTo: cacheStatusLabel.bottomAnchor, constant: 8),
            clearVectorCacheButton.leadingAnchor.constraint(equalTo: cacheLabel.leadingAnchor),
            clearVectorCacheButton.widthAnchor.constraint(equalToConstant: 180),
            clearVectorCacheButton.heightAnchor.constraint(equalToConstant: controlHeight),
            clearVectorCacheButton.bottomAnchor.constraint(lessThanOrEqualTo: vectorCacheCard.bottomAnchor, constant: -14),
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
        self.cachePage = cachePage
        self.modelPopup = modelPopup
        self.languagePopup = languagePopup
        self.themePopup = themePopup
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
        self.autoEmbeddingIndexCheckbox = autoEmbeddingIndexCheckbox
        self.cacheStatusLabel = cacheStatusLabel
        self.currentIndexStatusLabel = currentIndexStatusLabel
        updateCustomModelFields(for: selectedModel.id)
        updateEmbeddingEndpointFields(for: selectedEmbeddingEndpoint.id, fillDefaults: false)

        installAppActivationObserver()
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
        centerPanel(panel, attachedTo: parent)
        parent.addChildWindow(panel, ordered: .above)
        centerPanel(panel, attachedTo: parent)
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.makeKey()
    }

    private func installAppActivationObserver() {
        removeAppActivationObserver()
        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            self?.reactivatePanelIfNeeded()
        }
    }

    private func removeAppActivationObserver() {
        if let appActivationObserver {
            NotificationCenter.default.removeObserver(appActivationObserver)
            self.appActivationObserver = nil
        }
    }

    private func reactivatePanelIfNeeded() {
        guard let panel, panel.isVisible else { return }
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.makeKey()
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    private func centerPanel(_ panel: NSWindow, attachedTo parent: NSWindow) {
        let parentFrame = parent.frame
        let visibleFrame = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let origin = NSPoint(
            x: parentFrame.midX - panel.frame.width / 2,
            y: parentFrame.midY - panel.frame.height / 2
        )
        panel.setFrameOrigin(clampedPanelOrigin(origin, panelSize: panel.frame.size, visibleFrame: visibleFrame))
    }

    private func clampedPanelOrigin(_ origin: NSPoint, panelSize: NSSize, visibleFrame: NSRect?) -> NSPoint {
        guard let visibleFrame else { return origin }
        let minX = visibleFrame.minX + 12
        let maxX = visibleFrame.maxX - panelSize.width - 12
        let minY = visibleFrame.minY + 12
        let maxY = visibleFrame.maxY - panelSize.height - 12
        return NSPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }

    @objc private func save(_ sender: NSButton) {
        guard let panel else { return }
        guard saveCurrentSettings(in: panel) else { return }
        closePanel(notifySaved: true)
    }

    private func saveCurrentSettings(in panel: NSWindow) -> Bool {
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
        AISettingsStore.saveSpeakSelectedWordEnabled(speakSelectedWordCheckbox?.state == .on)
        AISettingsStore.saveAutoEmbeddingIndexEnabled(autoEmbeddingIndexCheckbox?.state == .on)
        return true
    }

    @objc private func cancel(_ sender: NSButton) {
        closePanel(notifySaved: false)
    }

    @objc private func settingsSegmentChanged(_ sender: NSSegmentedControl) {
        settingsTabChanged(index: sender.selectedSegment)
    }

    private func settingsTabChanged(index: Int) {
        basicPage?.isHidden = index != 0
        modelPage?.isHidden = index != 1
        embeddingPage?.isHidden = index != 2
        cachePage?.isHidden = index != 3
        currentIndexStatusLabel?.stringValue = currentVectorIndexStatus?() ?? AppText.localized("未打开文档", "No document open")
        if let scrollView = settingsScrollView {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            scrollView.verticalScrollElasticity = index == 3 ? .allowed : .none
            scrollView.hasVerticalScroller = index == 3
        }
    }

    @objc private func startCurrentVectorIndex(_ sender: NSButton) {
        guard let panel, saveCurrentSettings(in: panel) else { return }
        onStartVectorIndex?()
        refreshCurrentVectorIndexStatus()
    }

    @objc private func toggleCurrentVectorIndex(_ sender: NSButton) {
        onToggleVectorIndexPaused?()
        refreshCurrentVectorIndexStatus()
    }

    @objc private func cancelCurrentVectorIndex(_ sender: NSButton) {
        onCancelVectorIndex?()
        refreshCurrentVectorIndexStatus()
    }

    @objc private func clearCurrentVectorIndex(_ sender: NSButton) {
        onClearCurrentVectorIndex?()
        refreshCurrentVectorIndexStatus()
        cacheStatusLabel?.stringValue = vectorCacheStatusText()
    }

    @objc private func clearCurrentWordRecords(_ sender: NSButton) {
        onClearCurrentWordRecords?()
    }

    private func refreshCurrentVectorIndexStatus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.currentIndexStatusLabel?.stringValue = self?.currentVectorIndexStatus?() ?? AppText.localized("未打开文档", "No document open")
        }
    }

    private func closePanel(notifySaved: Bool) {
        guard let panel, !isClosing else { return }
        isClosing = true
        shouldNotifySavedAfterClose = notifySaved
        removeAppActivationObserver()
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
            "这会删除本机已缓存的文档向量索引。之后再次使用文档问答时，会按需重新生成。",
            "This deletes locally cached document vector indexes. They will be regenerated on demand when document Q&A is used again."
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppText.localized("清除", "Clear"))
        alert.addButton(withTitle: AppText.cancel)
        guard let panel else { return }
        alert.beginSheetModal(for: panel) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            PDFEmbeddingStore()?.deleteAll()
            self?.cacheStatusLabel?.stringValue = self?.vectorCacheStatusText() ?? ""
        }
    }

    @objc private func testChatConnection(_ sender: NSButton) {
        guard let panel else { return }
        guard saveCurrentSettings(in: panel) else { return }
        sender.isEnabled = false
        AIClient().send(messages: [
            ChatMessage(role: "system", content: "Reply with OK only."),
            ChatMessage(role: "user", content: "connection test")
        ]) { [weak self, weak sender] result in
            DispatchQueue.main.async {
                sender?.isEnabled = true
                self?.showConnectionResult(result, successMessage: AppText.localized("模型连接正常。", "Chat model connection works."))
            }
        }
    }

    @objc private func testEmbeddingConnection(_ sender: NSButton) {
        guard let panel else { return }
        guard saveCurrentSettings(in: panel) else { return }
        guard let config = EmbeddingClient.configFromCurrentAISettings() else {
            let result: Result<String, Error> = .failure(NSError(domain: "embedding", code: -1, userInfo: [
                NSLocalizedDescriptionKey: AppText.localized("请先配置向量 API Key，或选择本地向量接口。", "Configure an embedding API key first, or choose a local embedding endpoint.")
            ]))
            showConnectionResult(result, successMessage: "")
            return
        }
        sender.isEnabled = false
        EmbeddingClient().embed(texts: ["Leaf Reader connection test."], config: config) { [weak self, weak sender] result in
            DispatchQueue.main.async {
                sender?.isEnabled = true
                self?.showConnectionResult(result.map { "\($0.first?.count ?? 0)" }, successMessage: AppText.localized("向量连接正常。", "Embedding connection works."))
            }
        }
    }

    private func showConnectionResult<T>(_ result: Result<T, Error>, successMessage: String) {
        let alert = NSAlert()
        switch result {
        case .success:
            alert.messageText = AppText.localized("测试成功", "Test Succeeded")
            alert.informativeText = successMessage
            alert.alertStyle = .informational
            alert.icon = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
        case .failure(let error):
            alert.messageText = AppText.localized("测试失败", "Test Failed")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.icon = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        }
        alert.addButton(withTitle: AppText.confirm)
        alert.window.appearance = NSAppearance(named: .aqua)
        alert.window.backgroundColor = .white
        if let panel {
            alert.beginSheetModal(for: panel)
        } else {
            alert.runModal()
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

    private func updateEmbeddingEndpointFields(for optionID: String, fillDefaults: Bool) {
        guard let option = AISettingsStore.embeddingEndpointOptions.first(where: { $0.id == optionID }) else { return }
        let isCustom = option.id == AISettingsStore.customEmbeddingEndpointID
        embeddingEndpointContainer?.isHidden = !isCustom
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
        alert.beginSheetModal(for: panel)
    }

    private func vectorCacheStatusText() -> String {
        guard let store = PDFEmbeddingStore() else {
            return AppText.localized("缓存不可用", "Cache unavailable")
        }
        let size = formatBytes(store.cacheSizeBytes())
        let count = store.documentCount()
        return AppText.localized(
            "当前占用 \(size)，已缓存 \(count) 本文档。超过 1GB 会自动删除最久未使用的文档缓存。",
            "Using \(size), \(count) cached document(s). When it exceeds 1GB, the least recently used document cache is removed automatically."
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
        label.font = AppFont.semibold(ofSize: size)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func inputField(_ text: String, placeholder: String, fontSize: CGFloat, textColor: NSColor, backgroundColor: NSColor) -> NSTextField {
        let field = SettingsTextField(string: text)
        field.placeholderString = placeholder
        field.controlSize = .regular
        field.font = AppFont.semibold(ofSize: fontSize)
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
        comboBox.controlSize = .regular
        comboBox.font = AppFont.semibold(ofSize: fontSize)
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
        field.controlSize = .regular
        field.font = AppFont.semibold(ofSize: fontSize)
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
        popup.font = AppFont.semibold(ofSize: fontSize)
        popup.translatesAutoresizingMaskIntoConstraints = false
        for item in items {
            popup.addItem(withTitle: item.0)
            popup.lastItem?.representedObject = item.1
            popup.lastItem?.isEnabled = true
        }
        popup.isEnabled = true
        popup.menu?.autoenablesItems = false
        if let index = items.firstIndex(where: { $0.1 == selected }) {
            popup.selectItem(at: index)
        }
        return popup
    }

    private func settingsCard(isDark: Bool) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = (isDark
            ? NSColor(red: 0.08, green: 0.10, blue: 0.13, alpha: 1)
            : NSColor(red: 0.985, green: 0.988, blue: 0.995, alpha: 1)
        ).cgColor
        view.layer?.borderWidth = 1
        view.layer?.borderColor = (isDark
            ? NSColor(red: 0.22, green: 0.27, blue: 0.33, alpha: 1)
            : NSColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1)
        ).cgColor
        view.layer?.cornerRadius = 10
        view.layer?.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    private func fieldBackground(isDark: Bool) -> NSColor {
        isDark ? NSColor(red: 0.08, green: 0.10, blue: 0.13, alpha: 1) : .white
    }

    private func styleSettingsActionButton(
        _ button: NSButton,
        backgroundColor: NSColor,
        titleColor: NSColor,
        borderColor: NSColor
    ) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = backgroundColor.cgColor
        button.layer?.cornerRadius = 8
        button.layer?.borderWidth = 1
        button.layer?.borderColor = borderColor.cgColor
        button.layer?.masksToBounds = true
        button.font = AppFont.semibold(ofSize: 14)
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .font: AppFont.semibold(ofSize: 14),
                .foregroundColor: titleColor
            ]
        )
        button.lineBreakMode = .byTruncatingTail
    }
}
