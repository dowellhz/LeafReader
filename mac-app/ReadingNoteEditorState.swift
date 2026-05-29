import Foundation

final class ReadingNoteEditorState {
    var pendingAskSelectedText = ""
    var aiPlaceholderDisplayText: String?
    var askInputKeyMonitor: Any?
    var savesOnClose = true
    var autoSaveWorkItem: DispatchWorkItem?
    var activeAIRequestID: UUID?
    var isClosing = false

    func cancelAutoSave() {
        autoSaveWorkItem?.cancel()
        autoSaveWorkItem = nil
    }

    func beginAIRequest() -> UUID {
        let id = UUID()
        activeAIRequestID = id
        return id
    }

    func canApplyAIResult(_ id: UUID) -> Bool {
        !isClosing && activeAIRequestID == id
    }

    func finishAIRequest(_ id: UUID) {
        if activeAIRequestID == id {
            activeAIRequestID = nil
        }
    }

    func cancelAIRequests() {
        activeAIRequestID = nil
    }
}
