import Foundation

struct VocabularyDeletionRecord {
    let id: String
    let word: String
}

enum VocabularyRecordDeletionPlanner {
    static func expandedIDs(
        requestedIDs: Set<String>,
        storedRecords: [VocabularyDeletionRecord],
        pendingRecords: [VocabularyDeletionRecord]
    ) -> Set<String> {
        guard !requestedIDs.isEmpty else { return [] }
        let allRecords = storedRecords + pendingRecords
        let matchingWords = Set(allRecords
            .filter { requestedIDs.contains($0.id) }
            .map { normalizedWord($0.word) })
        guard !matchingWords.isEmpty else { return requestedIDs }

        var expanded = requestedIDs
        expanded.formUnion(allRecords.compactMap { record in
            matchingWords.contains(normalizedWord(record.word)) ? record.id : nil
        })
        return expanded
    }

    private static func normalizedWord(_ word: String) -> String {
        word
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
