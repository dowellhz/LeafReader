import Cocoa

struct ReaderNotesState {
    var storedReadingNotes: [ReadingNote] = []
    var panelControllers: [String: ReadingNotePanelController] = [:]
}
