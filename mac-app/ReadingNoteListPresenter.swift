import Foundation

struct ReadingNoteListRowViewModel: Equatable {
    let id: String
    let locationText: String
    let titleText: String
    let isFavorite: Bool
}

enum ReadingNoteListPresenter {
    static func sortedNotes(_ notes: [ReadingNote]) -> [ReadingNote] {
        notes.sortedForReadingNoteList()
    }

    static func rows(for notes: [ReadingNote]) -> [ReadingNoteListRowViewModel] {
        sortedNotes(notes).map(row)
    }

    static func filteredNotes(_ notes: [ReadingNote], query: String) -> [ReadingNote] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return sortedNotes(notes)
        }
        return sortedNotes(notes).filter { note in
            searchableText(for: note)
                .localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    static func rows(for notes: [ReadingNote], query: String) -> [ReadingNoteListRowViewModel] {
        filteredNotes(notes, query: query).map(row)
    }

    static func summaryText(noteCount: Int) -> String {
        AppText.localized("共 \(noteCount) 条笔记", "\(noteCount) note(s)")
    }

    static func row(for note: ReadingNote) -> ReadingNoteListRowViewModel {
        ReadingNoteListRowViewModel(
            id: note.id,
            locationText: locationText(for: note),
            titleText: ReadingNoteTextPolicy.compactInlineText(note.displayTitle, maxLength: 96),
            isFavorite: note.isFavorite
        )
    }

    private static func locationText(for note: ReadingNote) -> String {
        if let first = note.locator.pdfFragments?.first {
            return AppText.localized("第 \(first.pageIndex + 1) 页", "p. \(first.pageIndex + 1)")
        }
        return AppText.localized("网页位置", "Web location")
    }

    private static func searchableText(for note: ReadingNote) -> String {
        [
            note.displayTitle,
            locationText(for: note),
            note.quote,
            note.markdown,
            note.documentTitle
        ].joined(separator: "\n")
    }
}
