import Cocoa

final class AISettingsPanelController {
    enum SettingsTab: Int {
        case general = 0
        case model = 1
        case vector = 2
        case cache = 3
    }

    var onSaved: (() -> Void)?
    var currentVectorIndexStatus: (() -> String)?
    var onStartVectorIndex: (() -> Void)?
    var onToggleVectorIndexPaused: (() -> Void)?
    var onCancelVectorIndex: (() -> Void)?
    var onClearCurrentVectorIndex: (() -> Void)?
    var onClearCurrentWordRecords: (() -> Void)?

    let vectorCacheQueue = DispatchQueue(label: "com.linlu.leafreader.settings-vector-cache", qos: .utility)
    weak var parentWindow: NSWindow?
    var panel: SettingsPanel?
    weak var settingsTabControl: NSSegmentedControl?
    weak var settingsScrollView: NSScrollView?
    weak var basicPage: NSView?
    weak var modelPage: NSView?
    weak var embeddingPage: NSView?
    weak var cachePage: NSView?
    weak var modelPopup: NSPopUpButton?
    weak var languagePopup: NSPopUpButton?
    weak var themePopup: NSPopUpButton?
    weak var secureKeyField: NSSecureTextField?
    weak var customModelContainer: NSView?
    weak var customEndpointLabel: NSTextField?
    weak var customEndpointField: NSTextField?
    weak var customModelLabel: NSTextField?
    weak var customModelField: NSTextField?
    weak var embeddingProviderPopup: NSPopUpButton?
    weak var embeddingEndpointContainer: NSView?
    weak var embeddingEndpointLabel: NSTextField?
    weak var embeddingEndpointField: NSTextField?
    weak var embeddingModelField: NSTextField?
    weak var embeddingKeyField: NSSecureTextField?
    weak var speakSelectedWordCheckbox: NSButton?
    weak var saveAIConversationCheckbox: NSButton?
    weak var autoEmbeddingIndexCheckbox: NSButton?
    weak var cacheStatusLabel: NSTextField?
    weak var currentIndexStatusLabel: NSTextField?
    var cacheRefreshTimer: Timer?
    var keyTopWithCustomConstraint: NSLayoutConstraint?
    var keyTopWithoutCustomConstraint: NSLayoutConstraint?
    var embeddingModelTopWithCustomEndpointConstraint: NSLayoutConstraint?
    var embeddingModelTopWithoutCustomEndpointConstraint: NSLayoutConstraint?
    var isClosing = false
    var shouldNotifySavedAfterClose = false
    var appActivationObserver: NSObjectProtocol?
    var lastCustomEmbeddingEndpoint: String = ""
    var lastCustomEmbeddingModel: String = ""
    var currentEmbeddingOptionID: String = ""
    var pendingEmbeddingKeys: [String: String] = [:]

    deinit {
        cacheRefreshTimer?.invalidate()
        removeAppActivationObserver()
    }

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
        let layout = AISettingsLayoutMetrics()

        let panel = makeSettingsPanel(isDark: isDark)
        let content = makeSettingsContentView(panel: panel, isDark: isDark, backgroundColor: panelBackground)

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
        tabControl.selectedSegment = initialTab.rawValue
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
        let speakSelectedWordLabel = label(AppText.localized("自动播放单词", "Auto Play Words"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let speakSelectedWordCheckbox = NSButton(
            checkboxWithTitle: "",
            target: nil,
            action: nil
        )
        speakSelectedWordCheckbox.font = AppFont.semibold(ofSize: settingsFontSize)
        speakSelectedWordCheckbox.lineBreakMode = .byTruncatingTail
        speakSelectedWordCheckbox.state = AISettingsStore.speakSelectedWordEnabled ? .on : .off
        speakSelectedWordCheckbox.translatesAutoresizingMaskIntoConstraints = false
        let saveAIConversationLabel = label(AppText.localized("保存 AI 对话信息", "Save AI Chat"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let saveAIConversationCheckbox = NSButton(
            checkboxWithTitle: "",
            target: nil,
            action: nil
        )
        saveAIConversationCheckbox.font = AppFont.semibold(ofSize: settingsFontSize)
        saveAIConversationCheckbox.lineBreakMode = .byTruncatingTail
        saveAIConversationCheckbox.state = AISettingsStore.saveAIConversationEnabled ? .on : .off
        saveAIConversationCheckbox.translatesAutoresizingMaskIntoConstraints = false

        let embeddingLabel = label(AppText.localized("向量服务", "Embedding Service"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let embeddingProviderPopup = popup(items: AISettingsStore.embeddingEndpointOptions.map { ($0.title, $0.id) }, selected: selectedEmbeddingEndpoint.id, fontSize: settingsFontSize)
        let embeddingEndpointLabel = label(AppText.localized("接口 URL", "Endpoint URL"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let embeddingEndpointField = inputField(AISettingsStore.embeddingEndpointString, placeholder: "https://api.openai.com/v1/embeddings", fontSize: settingsFontSize, textColor: primaryText, backgroundColor: fieldBackground(isDark: isDark))
        let embeddingEndpointContainer = settingsCard(isDark: isDark)
        let embeddingModelNameLabel = label(AppText.localized("向量模型", "Embedding Model"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let embeddingModelField = inputField(AISettingsStore.embeddingModelName, placeholder: AISettingsStore.fallbackEmbeddingModelName, fontSize: settingsFontSize, textColor: primaryText, backgroundColor: fieldBackground(isDark: isDark))
        let embeddingKeyLabel = label(AppText.localized("向量 API Key", "Embedding API Key"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let embeddingKeyField = APIKeySecureTextField(string: AISettingsStore.embeddingAPIKeyMigratingLegacyIfNeeded(for: selectedEmbeddingEndpoint.id))
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

        let cacheLabel = label(AppText.localized("AI 向量缓存", "AI Vector Cache"), size: 15, weight: .semibold, color: primaryText)
        let cacheStatusLabel = label(AppText.localized("正在统计缓存...", "Calculating cache..."), size: settingsFontSize, color: secondaryText)
        let cacheDisclosureButton = NSButton(title: "", target: self, action: #selector(clearVectorCache(_:)))
        cacheDisclosureButton.isBordered = false
        cacheDisclosureButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        cacheDisclosureButton.contentTintColor = primaryText
        cacheDisclosureButton.isHidden = true
        cacheDisclosureButton.translatesAutoresizingMaskIntoConstraints = false
        let clearVectorCacheButton = cacheActionButton(
            title: AppText.localized("清除 AI 向量缓存", "Clear AI Vector Cache"),
            symbol: "trash",
            tint: NSColor(red: 1.00, green: 0.16, blue: 0.18, alpha: 1),
            target: self,
            action: #selector(clearVectorCache(_:)),
            isDark: isDark
        )
        clearVectorCacheButton.layer?.cornerRadius = 8
        clearVectorCacheButton.font = AppFont.semibold(ofSize: 14)
        clearVectorCacheButton.attributedTitle = NSAttributedString(
            string: AppText.localized("清除 AI 向量缓存", "Clear AI Vector Cache"),
            attributes: [
                .font: AppFont.semibold(ofSize: 14),
                .foregroundColor: primaryText
            ]
        )

        let currentIndexLabel = label(AppText.localized("当前书索引", "Current Book Index"), size: 15, weight: .semibold, color: primaryText)
        let currentIndexStatusLabel = label(currentVectorIndexStatus?() ?? AppText.noPDF, size: settingsFontSize, color: secondaryText)
        currentIndexStatusLabel.maximumNumberOfLines = 2
        currentIndexStatusLabel.lineBreakMode = .byWordWrapping
        let startIndexButton = cacheActionButton(title: AppText.localized("开始/继续生成", "Start / Resume"), symbol: "play.circle", tint: NSColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1), target: self, action: #selector(startCurrentVectorIndex(_:)), isDark: isDark)
        let pauseIndexButton = cacheActionButton(title: AppText.localized("暂停/继续", "Pause / Resume"), symbol: "pause.circle", tint: NSColor(red: 1.00, green: 0.58, blue: 0.00, alpha: 1), target: self, action: #selector(toggleCurrentVectorIndex(_:)), isDark: isDark)
        let cancelIndexButton = cacheActionButton(title: AppText.localized("取消生成", "Cancel"), symbol: "minus.circle", tint: NSColor(red: 1.00, green: 0.22, blue: 0.28, alpha: 1), target: self, action: #selector(cancelCurrentVectorIndex(_:)), isDark: isDark)
        let clearCurrentIndexButton = cacheActionButton(title: AppText.localized("清除当前书索引", "Clear Current Book"), symbol: "paintbrush", tint: NSColor(red: 0.60, green: 0.27, blue: 1.00, alpha: 1), target: self, action: #selector(clearCurrentVectorIndex(_:)), isDark: isDark)
        let clearCurrentWordsButton = cacheActionButton(title: AppText.localized("清除当前书单词记录", "Clear Current Book Words"), symbol: "trash", tint: NSColor(red: 0.00, green: 0.72, blue: 0.74, alpha: 1), target: self, action: #selector(clearCurrentWordRecords(_:)), isDark: isDark)
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
        for view in [cacheLabel, cacheStatusLabel, cacheDisclosureButton, clearVectorCacheButton] {
            vectorCacheCard.addSubview(view)
        }
        for view in [languageLabel, languagePopup, languageHelpLabel, themeLabel, themePopup, themeHelpLabel, speakSelectedWordLabel, speakSelectedWordCheckbox, saveAIConversationLabel, saveAIConversationCheckbox] {
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

            speakSelectedWordLabel.topAnchor.constraint(equalTo: themePopup.bottomAnchor, constant: 18),
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
        self.saveAIConversationCheckbox = saveAIConversationCheckbox
        self.autoEmbeddingIndexCheckbox = autoEmbeddingIndexCheckbox
        self.cacheStatusLabel = cacheStatusLabel
        self.currentIndexStatusLabel = currentIndexStatusLabel
        updateCustomModelFields(for: selectedModel.id)
        updateEmbeddingEndpointFields(for: selectedEmbeddingEndpoint.id, fillDefaults: false)
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
