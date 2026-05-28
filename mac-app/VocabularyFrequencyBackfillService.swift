import Foundation

struct VocabularyFrequencyBackfillProgress {
    let word: String
    let current: Int
    let total: Int
}

struct VocabularyFrequencyBackfillResult {
    let frequenciesByID: [String: Int]
}

final class VocabularyFrequencyBackfillService {
    private let preferences: VocabularyReviewPreferences
    private let metadataService: VocabularyDictionaryMetadataService.Type

    init(
        preferences: VocabularyReviewPreferences,
        metadataService: VocabularyDictionaryMetadataService.Type = VocabularyDictionaryMetadataService.self
    ) {
        self.preferences = preferences
        self.metadataService = metadataService
    }

    func backfillIfNeeded(
        items: [VocabularyDictionaryBackfillItem],
        progress: @escaping (VocabularyFrequencyBackfillProgress) -> Void,
        completion: @escaping (VocabularyFrequencyBackfillResult) -> Void
    ) {
        if preferences.isFrequencyBackfilled || items.isEmpty {
            preferences.markFrequencyBackfilled()
            completion(VocabularyFrequencyBackfillResult(frequenciesByID: [:]))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [preferences, metadataService] in
            var frequenciesByID: [String: Int] = [:]
            for (offset, item) in items.enumerated() {
                DispatchQueue.main.async {
                    progress(VocabularyFrequencyBackfillProgress(word: item.word, current: offset + 1, total: items.count))
                }
                guard let frequency = metadataService.metadata(for: item.word).frequency else {
                    continue
                }
                frequenciesByID[item.id] = frequency
            }
            DispatchQueue.main.async {
                preferences.markFrequencyBackfilled()
                completion(VocabularyFrequencyBackfillResult(frequenciesByID: frequenciesByID))
            }
        }
    }
}
