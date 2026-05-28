import Foundation

struct VocabularyReviewPreferences {
    private let fileID: String
    private let defaults: UserDefaults

    init(fileID: String, defaults: UserDefaults = .standard) {
        self.fileID = fileID
        self.defaults = defaults
    }

    var reviewPriority: VocabularyReviewPriority {
        get {
            guard let rawValue = defaults.string(forKey: reviewPriorityKey),
                  let priority = VocabularyReviewPriority(rawValue: rawValue) else {
                return .frequencyFirst
            }
            return priority
        }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: reviewPriorityKey)
        }
    }

    var isFrequencyBackfilled: Bool {
        defaults.bool(forKey: frequencyBackfilledKey)
    }

    func markFrequencyBackfilled() {
        defaults.set(true, forKey: frequencyBackfilledKey)
    }

    private var reviewPriorityKey: String {
        "bookSession.\(fileID).vocabularyReviewPriority"
    }

    private var frequencyBackfilledKey: String {
        "bookSession.\(fileID).vocabularyFrequencyBackfilled"
    }
}
