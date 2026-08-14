import Foundation

enum VocabularyReviewScoringService {
    // One exported vocabulary card may aggregate several saved word records. Keep the
    // exported card's SRS state pinned to the earliest due underlying record.
    static func snapshot(
        ids: [String],
        documentKind: ReaderDocumentKind,
        pdfRecords: [StoredPDFWordRecord],
        webRecords: [StoredWebWordRecord]
    ) -> [String: VocabularySRSState] {
        let idSet = Set(ids)
        switch documentKind {
        case .pdf:
            return Dictionary(
                uniqueKeysWithValues: pdfRecords
                    .filter { idSet.contains($0.id) }
                    .map { ($0.id, $0.srs ?? VocabularySRSState.initial(createdAt: $0.createdAt)) }
            )
        default:
            return Dictionary(
                uniqueKeysWithValues: webRecords
                    .filter { idSet.contains($0.id) }
                    .map { ($0.id, $0.srs ?? VocabularySRSState.initial(createdAt: $0.createdAt)) }
            )
        }
    }

    static func restore(
        snapshot: [String: VocabularySRSState],
        documentKind: ReaderDocumentKind,
        pdfRecords: inout [StoredPDFWordRecord],
        webRecords: inout [StoredWebWordRecord],
        exportRecords: inout [VocabularyExportRecord]
    ) {
        let idSet = Set(snapshot.keys)
        switch documentKind {
        case .pdf:
            for index in pdfRecords.indices where idSet.contains(pdfRecords[index].id) {
                pdfRecords[index].srs = snapshot[pdfRecords[index].id]
            }
        default:
            for index in webRecords.indices where idSet.contains(webRecords[index].id) {
                webRecords[index].srs = snapshot[webRecords[index].id]
            }
        }

        refreshExportRecords(&exportRecords, ids: idSet) { old in
            old.ids.compactMap { snapshot[$0] }.min { $0.dueDate < $1.dueDate } ?? old.srs
        }
    }

    static func update(
        ids: [String],
        grade: Int,
        documentKind: ReaderDocumentKind,
        pdfRecords: inout [StoredPDFWordRecord],
        webRecords: inout [StoredWebWordRecord],
        exportRecords: inout [VocabularyExportRecord]
    ) {
        let idSet = Set(ids)
        switch documentKind {
        case .pdf:
            for index in pdfRecords.indices where idSet.contains(pdfRecords[index].id) {
                let current = pdfRecords[index].srs ?? VocabularySRSState.initial(createdAt: pdfRecords[index].createdAt)
                pdfRecords[index].srs = current.reviewed(grade: grade)
            }
        default:
            for index in webRecords.indices where idSet.contains(webRecords[index].id) {
                let current = webRecords[index].srs ?? VocabularySRSState.initial(createdAt: webRecords[index].createdAt)
                webRecords[index].srs = current.reviewed(grade: grade)
            }
        }

        refreshExportRecords(&exportRecords, ids: idSet) { old in
            state(
                ids: old.ids,
                fallback: old.srs,
                documentKind: documentKind,
                pdfRecords: pdfRecords,
                webRecords: webRecords
            )
        }
    }

    static func state(
        ids: [String],
        fallback: VocabularySRSState,
        documentKind: ReaderDocumentKind,
        pdfRecords: [StoredPDFWordRecord],
        webRecords: [StoredWebWordRecord]
    ) -> VocabularySRSState {
        let idSet = Set(ids)
        let states: [VocabularySRSState]
        switch documentKind {
        case .pdf:
            states = pdfRecords
                .filter { idSet.contains($0.id) }
                .map { $0.srs ?? VocabularySRSState.initial(createdAt: $0.createdAt) }
        default:
            states = webRecords
                .filter { idSet.contains($0.id) }
                .map { $0.srs ?? VocabularySRSState.initial(createdAt: $0.createdAt) }
        }
        return states.min { $0.dueDate < $1.dueDate } ?? fallback
    }

    private static func refreshExportRecords(
        _ exportRecords: inout [VocabularyExportRecord],
        ids: Set<String>,
        stateForRecord: (VocabularyExportRecord) -> VocabularySRSState
    ) {
        for index in exportRecords.indices where !Set(exportRecords[index].ids).isDisjoint(with: ids) {
            let old = exportRecords[index]
            exportRecords[index] = VocabularyExportRecord(
                ids: old.ids,
                word: old.word,
                lemma: old.lemma,
                surfaceForms: old.surfaceForms,
                answer: old.answer,
                dictionaryTags: old.dictionaryTags,
                dictionaryFrequency: old.dictionaryFrequency,
                location: old.location,
                context: old.context,
                createdAt: old.createdAt,
                srs: stateForRecord(old)
            )
        }
    }
}
