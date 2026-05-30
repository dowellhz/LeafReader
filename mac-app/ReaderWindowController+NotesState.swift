import Foundation

extension ReaderWindowController {
    var storedReadingNotes: [ReadingNote] {
        get { notesState.storedReadingNotes }
        set { notesState.storedReadingNotes = newValue }
    }

    var readingNotePanelControllers: [String: ReadingNotePanelController] {
        get { notesState.panelControllers }
        set { notesState.panelControllers = newValue }
    }
}
