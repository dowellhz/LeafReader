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

}

