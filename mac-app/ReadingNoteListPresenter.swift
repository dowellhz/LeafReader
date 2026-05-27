import Foundation

struct ReadingNoteListRowViewModel: Equatable {
    let id: String
    let locationText: String
    let titleText: String
}

enum ReadingNoteListPresenter {
    static func sortedNotes(_ notes: [ReadingNote]) -> [ReadingNote] {
        notes.sortedByCreatedAt()
    }

    static func rows(for notes: [ReadingNote]) -> [ReadingNoteListRowViewModel] {
        sortedNotes(notes).map(row)
    }

    static func summaryText(noteCount: Int) -> String {
        AppText.localized("共 \(noteCount) 条笔记", "\(noteCount) note(s)")
    }

    static func row(for note: ReadingNote) -> ReadingNoteListRowViewModel {
        ReadingNoteListRowViewModel(
            id: note.id,
            locationText: locationText(for: note),
            titleText: ReadingNoteTextPolicy.compactInlineText(note.displayTitle, maxLength: 96)
        )
    }

    private static func locationText(for note: ReadingNote) -> String {
        if let first = note.locator.pdfFragments?.first {
            return AppText.localized("第 \(first.pageIndex + 1) 页", "p. \(first.pageIndex + 1)")
        }
        return AppText.localized("网页位置", "Web location")
    }
}
