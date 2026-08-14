import Foundation
import NaturalLanguage

struct VocabularyWordIdentity: Equatable {
    let surface: String
    let lemma: String
    let lexicalClass: String?
    let groupingKey: String
}

struct VocabularyWordSample {
    let id: String
    let word: String
    let context: String?
    let createdAt: Date
}

enum VocabularyRelatedFormPolicy {
    static func primarySampleIDs(_ samples: [VocabularyWordSample]) -> Set<String> {
        var primaryByGroup: [String: VocabularyWordSample] = [:]
        for sample in samples {
            let key = VocabularyLemmaResolver.identity(
                for: sample.word,
                context: sample.context
            ).groupingKey
            guard let existing = primaryByGroup[key] else {
                primaryByGroup[key] = sample
                continue
            }
            if sample.createdAt < existing.createdAt
                || (sample.createdAt == existing.createdAt && sample.id < existing.id) {
                primaryByGroup[key] = sample
            }
        }
        return Set(samples.compactMap { sample in
            let identity = VocabularyLemmaResolver.identity(for: sample.word, context: sample.context)
            guard let primary = primaryByGroup[identity.groupingKey] else { return nil }
            let primarySurface = VocabularyLemmaResolver.identity(
                for: primary.word,
                context: primary.context
            ).surface.lowercased()
            return identity.surface.lowercased() == primarySurface ? sample.id : nil
        })
    }
}

enum VocabularyLemmaResolver {
    private struct TaggedWord {
        let lemma: String
        let lexicalClass: String?
    }

    private static let irregularVerbs: [String: String] = [
        "am": "be", "are": "be", "been": "be", "being": "be", "is": "be", "was": "be", "were": "be",
        "came": "come", "did": "do", "done": "do", "gave": "give", "given": "give", "gone": "go",
        "got": "get", "gotten": "get", "had": "have", "has": "have", "knew": "know", "known": "know",
        "made": "make", "ran": "run", "said": "say", "saw": "see", "seen": "see", "spoke": "speak",
        "spoken": "speak", "took": "take", "taken": "take", "thought": "think", "went": "go",
        "wrote": "write", "written": "write"
    ]

    private static let irregularNouns: [String: String] = [
        "children": "child", "feet": "foot", "geese": "goose", "men": "man", "mice": "mouse",
        "people": "person", "teeth": "tooth", "women": "woman"
    ]

    private static let regularVerbCacheLock = NSLock()
    private static var regularVerbCache: [String: String] = [:]

    static func identity(for rawSurface: String, context: String? = nil) -> VocabularyWordIdentity {
        let surface = VocabularyTextPolicy.normalizedVocabularyText(rawSurface)
        let surfaceKey = canonicalKey(surface)
        guard !surfaceKey.isEmpty else {
            return exactIdentity(surface: surface, key: surfaceKey)
        }
        guard VocabularyTextPolicy.isSingleEnglishWord(surface), !isAcronym(surface) else {
            return exactIdentity(surface: surface, key: surfaceKey)
        }

        let tagged = context.flatMap { taggedWord(surface: surface, in: $0) }
            ?? taggedWord(surface: surface, in: surface)
        guard let tagged,
              let lexicalClass = normalizedLexicalClass(tagged.lexicalClass) else {
            return exactIdentity(surface: surface, key: surfaceKey)
        }
        return identity(
            forTaggedSurface: surface,
            lemma: tagged.lemma,
            lexicalClass: lexicalClass
        )
    }

    static func identity(
        forTaggedSurface rawSurface: String,
        lemma rawLemma: String,
        lexicalClass rawLexicalClass: String
    ) -> VocabularyWordIdentity {
        let surface = VocabularyTextPolicy.normalizedVocabularyText(rawSurface)
        let surfaceKey = canonicalKey(surface)
        guard VocabularyTextPolicy.isSingleEnglishWord(surface),
              let lexicalClass = normalizedLexicalClass(rawLexicalClass) else {
            return exactIdentity(surface: surface, key: surfaceKey)
        }
        let taggedLemma = canonicalKey(rawLemma)
        let lemmaKey = correctedLemma(
            surfaceKey: surfaceKey,
            taggedLemma: taggedLemma,
            lexicalClass: lexicalClass
        )
        guard VocabularyTextPolicy.isSingleEnglishWord(lemmaKey) else {
            return exactIdentity(surface: surface, key: surfaceKey)
        }
        return VocabularyWordIdentity(
            surface: surface,
            lemma: lemmaKey,
            lexicalClass: lexicalClass,
            groupingKey: "lemma:\(lexicalClass):\(lemmaKey)"
        )
    }

    static func areRelated(
        _ lhs: String,
        context lhsContext: String? = nil,
        _ rhs: String,
        context rhsContext: String? = nil
    ) -> Bool {
        let left = identity(for: lhs, context: lhsContext)
        let right = identity(for: rhs, context: rhsContext)
        return left.groupingKey == right.groupingKey
    }

    private static func exactIdentity(surface: String, key: String) -> VocabularyWordIdentity {
        VocabularyWordIdentity(
            surface: surface,
            lemma: key,
            lexicalClass: nil,
            groupingKey: "exact:\(key)"
        )
    }

    private static func taggedWord(surface: String, in rawText: String) -> TaggedWord? {
        let text = VocabularyTextPolicy.normalizedVocabularyText(rawText)
        guard !text.isEmpty else { return nil }
        let target = canonicalKey(surface)
        let tagger = NLTagger(tagSchemes: [.tokenType, .lemma, .lexicalClass])
        tagger.string = text
        let range = text.startIndex..<text.endIndex
        tagger.setLanguage(.english, range: range)

        var result: TaggedWord?
        tagger.enumerateTags(
            in: range,
            unit: .word,
            scheme: .tokenType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { _, tokenRange in
            guard canonicalKey(String(text[tokenRange])) == target else { return true }
            let lemma = tagger.tag(at: tokenRange.lowerBound, unit: .word, scheme: .lemma).0?.rawValue
                ?? String(text[tokenRange])
            let lexicalClass = tagger.tag(
                at: tokenRange.lowerBound,
                unit: .word,
                scheme: .lexicalClass
            ).0?.rawValue
            result = TaggedWord(lemma: lemma, lexicalClass: lexicalClass)
            return false
        }
        return result
    }

    private static func correctedLemma(surfaceKey: String, taggedLemma: String, lexicalClass: String) -> String {
        switch lexicalClass {
        case "verb":
            if let irregularLemma = irregularVerbs[surfaceKey] {
                return irregularLemma
            }
            guard taggedLemma == surfaceKey else { return taggedLemma }
            return regularVerbLemma(for: surfaceKey)
        case "noun":
            return irregularNouns[surfaceKey] ?? taggedLemma
        default:
            return taggedLemma
        }
    }

    private static func regularVerbLemma(for surface: String) -> String {
        regularVerbCacheLock.lock()
        if let cached = regularVerbCache[surface] {
            regularVerbCacheLock.unlock()
            return cached
        }
        regularVerbCacheLock.unlock()

        let candidates = regularVerbCandidates(for: surface)
        let result = candidates.first(where: isRecognizedBaseVerb) ?? surface
        regularVerbCacheLock.lock()
        regularVerbCache[surface] = result
        regularVerbCacheLock.unlock()
        return result
    }

    private static func regularVerbCandidates(for surface: String) -> [String] {
        var candidates: [String] = []
        if surface.hasSuffix("ies"), surface.count > 4 {
            candidates.append(String(surface.dropLast(3)) + "y")
        }
        if surface.hasSuffix("ing"), surface.count > 5 {
            let stem = String(surface.dropLast(3))
            candidates.append(stem)
            candidates.append(removingDoubledFinalConsonant(from: stem))
            candidates.append(stem + "e")
            if stem.hasSuffix("y") {
                candidates.append(String(stem.dropLast()) + "ie")
            }
        }
        if surface.hasSuffix("ed"), surface.count > 4 {
            let stem = String(surface.dropLast(2))
            candidates.append(stem)
            candidates.append(removingDoubledFinalConsonant(from: stem))
            candidates.append(stem + "e")
        }
        if surface.hasSuffix("es"), surface.count > 4 {
            let stem = String(surface.dropLast(2))
            if ["s", "x", "z", "ch", "sh", "o"].contains(where: stem.hasSuffix) {
                candidates.append(stem)
            }
        }
        if surface.hasSuffix("s"), !surface.hasSuffix("ss"), surface.count > 3 {
            candidates.append(String(surface.dropLast()))
        }
        return candidates.filter { !$0.isEmpty && $0 != surface }
    }

    private static func removingDoubledFinalConsonant(from value: String) -> String {
        guard value.count >= 2 else { return value }
        let final = value.last
        let preceding = value.dropLast().last
        guard final == preceding, let final, !"aeiou".contains(final) else { return value }
        return String(value.dropLast())
    }

    private static func isRecognizedBaseVerb(_ candidate: String) -> Bool {
        let text = "to \(candidate)"
        let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
        tagger.string = text
        let range = text.startIndex..<text.endIndex
        tagger.setLanguage(.english, range: range)
        var isRecognized = false
        tagger.enumerateTags(
            in: range,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, tokenRange in
            guard canonicalKey(String(text[tokenRange])) == candidate else { return true }
            let lemma = tagger.tag(at: tokenRange.lowerBound, unit: .word, scheme: .lemma).0?.rawValue
            isRecognized = normalizedLexicalClass(tag?.rawValue) == "verb"
                && canonicalKey(lemma ?? candidate) == candidate
            return false
        }
        return isRecognized
    }

    private static func normalizedLexicalClass(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              ["adjective", "adverb", "noun", "verb"].contains(value) else {
            return nil
        }
        return value
    }

    private static func canonicalKey(_ value: String) -> String {
        value
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func isAcronym(_ word: String) -> Bool {
        let letters = word.filter(\.isLetter)
        return letters.count > 1 && letters.allSatisfy(\.isUppercase)
    }
}
