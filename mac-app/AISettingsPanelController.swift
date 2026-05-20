import Cocoa

final class AISettingsPanelController {
    enum SettingsTab: Int {
        case general = 0
        case model = 1
        case vector = 2
        case cache = 3
    }

    enum Identifiers {
        static let saveButton = NSUserInterfaceItemIdentifier("saveAISettings")
        static let modelPopup = NSUserInterfaceItemIdentifier("modelPopup")
        static let languagePopup = NSUserInterfaceItemIdentifier("languagePopup")
        static let themePopup = NSUserInterfaceItemIdentifier("themePopup")
        static let keyField = NSUserInterfaceItemIdentifier("keyField")
        static let embeddingProviderPopup = NSUserInterfaceItemIdentifier("embeddingProviderPopup")
        static let embeddingEndpointField = NSUserInterfaceItemIdentifier("embeddingEndpointField")
        static let embeddingModelField = NSUserInterfaceItemIdentifier("embeddingModelField")
        static let embeddingKeyField = NSUserInterfaceItemIdentifier("embeddingKeyField")
    }

    var onSaved: (() -> Void)?
    var onAppearanceChanged: (() -> Void)?
    var currentVectorIndexStatus: (() -> String)?
    var onStartVectorIndex: (() -> Void)?
    var onToggleVectorIndexPaused: (() -> Void)?
    var onCancelVectorIndex: (() -> Void)?
    var onClearCurrentVectorIndex: (() -> Void)?
    var onClearCurrentWordRecords: (() -> Void)?

    let vectorCacheQueue = DispatchQueue(label: "com.linlu.leafreader.settings-vector-cache", qos: .utility)
    weak var parentWindow: NSWindow?
    var panel: SettingsPanel?
    weak var settingsTabControl: NSView?
    weak var settingsScrollView: NSScrollView?
    weak var basicPage: NSView?
    weak var modelPage: NSView?
    weak var embeddingPage: NSView?
    weak var cachePage: NSView?
    weak var modelPopup: NSPopUpButton?
    weak var languagePopup: NSPopUpButton?
    weak var themePopup: NSPopUpButton?
    weak var pdfDimmingLabel: NSTextField?
    weak var pdfDimmingSlider: ThemedSettingsSlider?
    var pdfDimmingLabelTopConstraint: NSLayoutConstraint?
    var speakSelectedWordTopToDimmingConstraint: NSLayoutConstraint?
    var speakSelectedWordTopToThemeConstraint: NSLayoutConstraint?
    var pdfDimmingCollapsedConstraints: [NSLayoutConstraint] = []
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
