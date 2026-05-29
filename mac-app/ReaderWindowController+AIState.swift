import Cocoa

extension ReaderWindowController {
    var retrievalQueryClient: AIClient {
        aiState.retrievalQueryClient
    }

    var suppressSearchSelectionForAIUntil: Date {
        get { aiState.suppressSearchSelectionForAIUntil }
        set { aiState.suppressSearchSelectionForAIUntil = newValue }
    }

    var highlightedSelectionKeys: Set<String> {
        get { aiState.highlightedSelectionKeys }
        set { aiState.highlightedSelectionKeys = newValue }
    }

    var aiSourceUnderlineKeys: Set<String> {
        get { aiState.aiSourceUnderlineKeys }
        set { aiState.aiSourceUnderlineKeys = newValue }
    }

    var aiSourceLocationsByUnderlineKey: [String: AIConversationSourceLocation] {
        get { aiState.aiSourceLocationsByUnderlineKey }
        set { aiState.aiSourceLocationsByUnderlineKey = newValue }
    }

    var webAISourceLocationsByKey: [String: AIConversationSourceLocation] {
        get { aiState.webAISourceLocationsByKey }
        set { aiState.webAISourceLocationsByKey = newValue }
    }

    var activeAISourceUnderlines: [AIConversationSourceLocation] {
        get { aiState.activeAISourceUnderlines }
        set { aiState.activeAISourceUnderlines = newValue }
    }

    var aiConversationStore: AIConversationStore? {
        get { aiState.conversationStore }
        set { aiState.conversationStore = newValue }
    }

    var loadedAIConversation: SavedAIConversation? {
        get { aiState.loadedConversation }
        set { aiState.loadedConversation = newValue }
    }

    var pendingAIConversationToSave: SavedAIConversation? {
        get { aiState.pendingConversationToSave }
        set { aiState.pendingConversationToSave = newValue }
    }

    var documentPromptGeneration: Int {
        get { aiState.documentPromptGeneration }
        set { aiState.documentPromptGeneration = newValue }
    }

    var retrievalQueryTask: URLSessionDataTask? {
        get { aiState.retrievalQueryTask }
        set { aiState.retrievalQueryTask = newValue }
    }

    var aiConversationSaveTask: DebouncedTask {
        aiState.conversationSaveTask
    }

    var preferredAIWidthSaveTask: DebouncedTask {
        aiState.preferredWidthSaveTask
    }

    var windowResizeLayoutTask: DebouncedTask {
        aiState.windowResizeLayoutTask
    }

    var aiPanelResizeLayoutTask: DebouncedTask {
        aiState.panelResizeLayoutTask
    }

    var pendingAIPanelExpansionAction: (() -> Void)? {
        get { aiState.pendingPanelExpansionAction }
        set { aiState.pendingPanelExpansionAction = newValue }
    }

    var pendingAISourceClickWorkItem: DispatchWorkItem? {
        get { aiState.pendingSourceClickWorkItem }
        set { aiState.pendingSourceClickWorkItem = newValue }
    }

    var isAIPanelCollapsed: Bool {
        get { aiState.isPanelCollapsed }
        set { aiState.isPanelCollapsed = newValue }
    }

    var preferredAIWidth: CGFloat {
        get { aiState.preferredWidth }
        set { aiState.preferredWidth = newValue }
    }
}
