import Foundation

final class ReadingNoteEditorState {
    var pendingAskSelectedText = ""
    var aiPlaceholderDisplayText: String?
    var askInputKeyMonitor: Any?
    var savesOnClose = true
    var autoSaveWorkItem: DispatchWorkItem?

    func cancelAutoSave() {
        autoSaveWorkItem?.cancel()
        autoSaveWorkItem = nil
    }
}
