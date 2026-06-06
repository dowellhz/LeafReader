import Foundation

enum PersonalVocabularyStatus: String {
    case observed
    case learning
    case likelyKnown = "likely_known"
    case known
}

struct PersonalVocabularyProfile: Equatable {
    let lemma: String
    var surfaceCount: Int
    var seenCount: Int
    var unqueriedSeenCount: Int
    var postQueryUnqueriedSeenCount: Int
    var queriedCount: Int
    var aiExplainCount: Int
    var reviewCorrectCount: Int
    var reviewWrongCount: Int
    var documentsSeen: Int
    var status: PersonalVocabularyStatus
    var confidence: Double
    var lastSeenAt: Date?
    var updatedAt: Date
}

struct PersonalVocabularyExposure {
    let documentID: String
    let lemmaCounts: [String: Int]
    let date: Date
}

enum PersonalVocabularyTokenizer {
    private static let tokenPattern = #"[A-Za-z](?:[A-Za-z]|['’](?=[A-Za-z]))*(?:-(?=[A-Za-z])[A-Za-z](?:[A-Za-z]|['’](?=[A-Za-z]))*)*"#
    private static let stopWords: Set<String> = [
        "a", "an", "the",
        "am", "are", "be", "been", "being", "is", "was", "were",
        "do", "does", "did", "doing",
        "have", "has", "had", "having",
        "i", "me", "my", "mine", "we", "us", "our", "ours",
        "you", "your", "yours",
        "he", "him", "his", "she", "her", "hers", "it", "its",
        "they", "them", "their", "theirs",
        "this", "that", "these", "those",
        "and", "but", "or", "nor", "so", "yet",
        "if", "then", "because", "as", "when", "while", "where", "which", "who", "whom", "whose",
        "to", "of", "in", "on", "at", "by", "for", "from", "with", "without", "into", "onto", "over", "under",
        "up", "down", "out", "off", "about", "through", "between", "among",
        "not", "no", "yes",
        "can", "could", "may", "might", "must", "shall", "should", "will", "would",
        "com", "ebook", "ebooks", "http", "https", "ing", "www"
    ]

    static func lemmaCounts(in text: String) -> [String: Int] {
        let normalized = cleanedReadingText(text)
        guard let regex = try? NSRegularExpression(pattern: tokenPattern) else { return [:] }
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        var counts: [String: Int] = [:]
        regex.enumerateMatches(in: normalized, range: range) { match, _, _ in
            guard let matchRange = match?.range,
                  let tokenRange = Range(matchRange, in: normalized) else {
                return
            }
            let lemma = lemma(for: String(normalized[tokenRange]))
            guard isTrackableLemma(lemma) else { return }
            counts[lemma, default: 0] += 1
        }
        return counts
    }

    static func lemma(for token: String) -> String {
        var value = token
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: CharacterSet(charactersIn: "'-"))
        if value.hasSuffix("'s") {
            value.removeLast(2)
        }
        return value
    }

    static func isStoredLemmaTrackable(_ rawLemma: String) -> Bool {
        isTrackableLemma(lemma(for: rawLemma))
    }

    static func cleanedReadingText(_ text: String) -> String {
        text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !shouldSkipLine($0) }
            .joined(separator: "\n")
            .replacingOccurrences(of: #"\b([A-Za-z]{1,3})[‐‑‒–—-]\s+([A-Za-z]{4,})\b"#, with: "$1$2", options: .regularExpression)
            .replacingOccurrences(of: #"[‐‑‒-]\s+"#, with: "-", options: .regularExpression)
            .replacingOccurrences(of: #"[–—]"#, with: " ", options: .regularExpression)
    }

    private static func shouldSkipLine(_ line: String) -> Bool {
        let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return true }
        if value.range(of: #"^\d+$"#, options: .regularExpression) != nil {
            return true
        }
        let lowercased = value.lowercased()
        return lowercased.contains("free ebooks at planet ebook")
            || lowercased.contains("planet ebook.com")
            || lowercased.contains("project gutenberg")
    }

    private static func isTrackableLemma(_ lemma: String) -> Bool {
        guard lemma.count >= 2, lemma.count <= 40 else { return false }
        guard !stopWords.contains(lemma) else { return false }
        return lemma.range(of: #"[a-z]"#, options: .regularExpression) != nil
            && lemma.range(of: #"^[a-z]+(?:['-][a-z]+)*$"#, options: .regularExpression) != nil
    }
}

enum PersonalVocabularyProfilePolicy {
    static func status(
        seenCount: Int,
        unqueriedSeenCount: Int,
        postQueryUnqueriedSeenCount: Int,
        queriedCount: Int,
        reviewCorrectCount: Int,
        reviewWrongCount: Int,
        documentsSeen: Int
    ) -> PersonalVocabularyStatus {
        if reviewCorrectCount >= 3, reviewWrongCount == 0 {
            return .known
        }
        if queriedCount > 0, reviewWrongCount == 0, postQueryUnqueriedSeenCount >= 4 {
            return .known
        }
        if queriedCount > 0 || reviewWrongCount > 0 {
            return .learning
        }
        if unqueriedSeenCount >= 4 {
            return .known
        }
        if documentsSeen >= 3, unqueriedSeenCount >= 3 {
            return .likelyKnown
        }
        return .observed
    }

    static func confidence(
        seenCount: Int,
        unqueriedSeenCount: Int,
        postQueryUnqueriedSeenCount: Int,
        queriedCount: Int,
        reviewCorrectCount: Int,
        reviewWrongCount: Int,
        documentsSeen: Int
    ) -> Double {
        let exposureScore = min(0.55, Double(unqueriedSeenCount) * 0.025)
        let recoveryScore = min(0.20, Double(postQueryUnqueriedSeenCount) * 0.05)
        let documentScore = min(0.20, Double(max(0, documentsSeen - 1)) * 0.07)
        let reviewScore = min(0.30, Double(reviewCorrectCount) * 0.10)
        let queryPenalty = min(0.40, Double(queriedCount) * 0.10 + Double(reviewWrongCount) * 0.15)
        return min(1, max(0, exposureScore + recoveryScore + documentScore + reviewScore - queryPenalty))
    }
}

enum PersonalVocabularyExposurePolicy {
    static let webProgressBucketCount = 200

    static func webProgressBucket(_ progress: Double) -> Int {
        let clamped = min(1, max(0, progress))
        return Int((clamped * Double(webProgressBucketCount)).rounded(.down))
    }
}
