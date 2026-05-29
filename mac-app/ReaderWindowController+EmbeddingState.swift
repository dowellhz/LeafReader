import Foundation

extension ReaderWindowController {
    var pdfAgentIndex: PDFDocumentAgentIndex? {
        get { embeddingState.pdfAgentIndex }
        set { embeddingState.pdfAgentIndex = newValue }
    }

    var isBuildingDocumentAgentIndex: Bool {
        get { embeddingState.isBuildingDocumentAgentIndex }
        set { embeddingState.isBuildingDocumentAgentIndex = newValue }
    }

    var documentAgentIndexGeneration: Int {
        get { embeddingState.documentAgentIndexGeneration }
        set { embeddingState.documentAgentIndexGeneration = newValue }
    }

    var pendingDocumentAgentIndexCallbacks: [() -> Void] {
        get { embeddingState.pendingDocumentAgentIndexCallbacks }
        set { embeddingState.pendingDocumentAgentIndexCallbacks = newValue }
    }

    var pdfEmbeddingStore: PDFEmbeddingStore? {
        get { embeddingState.pdfEmbeddingStore }
        set { embeddingState.pdfEmbeddingStore = newValue }
    }

    var embeddingStoreQueue: DispatchQueue {
        embeddingState.embeddingStoreQueue
    }

    var embeddingClient: EmbeddingClient {
        embeddingState.embeddingClient
    }

    var isPreparingPDFEmbeddings: Bool {
        get { embeddingState.isPreparingPDFEmbeddings }
        set { embeddingState.isPreparingPDFEmbeddings = newValue }
    }

    var isEmbeddingBackfillPaused: Bool {
        get { embeddingState.isEmbeddingBackfillPaused }
        set { embeddingState.isEmbeddingBackfillPaused = newValue }
    }

    var embeddingBackfillNeedsRetry: Bool {
        get { embeddingState.embeddingBackfillNeedsRetry }
        set { embeddingState.embeddingBackfillNeedsRetry = newValue }
    }

    var queuedEmbeddingPriorityPageIndex: Int? {
        get { embeddingState.queuedEmbeddingPriorityPageIndex }
        set { embeddingState.queuedEmbeddingPriorityPageIndex = newValue }
    }

    var pendingEmbeddingReadyCallbacks: [() -> Void] {
        get { embeddingState.pendingEmbeddingReadyCallbacks }
        set { embeddingState.pendingEmbeddingReadyCallbacks = newValue }
    }

    var embeddingBackfillGeneration: Int {
        get { embeddingState.embeddingBackfillGeneration }
        set { embeddingState.embeddingBackfillGeneration = newValue }
    }

    var scheduledEmbeddingCacheRestoreWorkItem: DispatchWorkItem? {
        get { embeddingState.scheduledEmbeddingCacheRestoreWorkItem }
        set { embeddingState.scheduledEmbeddingCacheRestoreWorkItem = newValue }
    }

    var scheduledEmbeddingWarmupWorkItem: DispatchWorkItem? {
        get { embeddingState.scheduledEmbeddingWarmupWorkItem }
        set { embeddingState.scheduledEmbeddingWarmupWorkItem = newValue }
    }

    var lastReaderInteractionAt: Date {
        get { embeddingState.lastReaderInteractionAt }
        set { embeddingState.lastReaderInteractionAt = newValue }
    }
}
