import Foundation

struct TextQuoteAnchor: Codable, Equatable {
    static let currentVersion = 1

    let unitOrdinal: Int
    let sourceStart: Int
    let sourceLength: Int
    let exactQuote: String
    let prefix: String
    let suffix: String
    let version: Int

    init?(
        unitOrdinal: Int,
        sourceRange: NSRange,
        sourceText: String,
        contextLength: Int = 32,
        version: Int = currentVersion
    ) {
        let source = sourceText as NSString
        guard unitOrdinal >= 0,
              sourceRange.location != NSNotFound,
              sourceRange.location >= 0,
              sourceRange.length > 0,
              NSMaxRange(sourceRange) <= source.length else {
            return nil
        }

        let radius = max(0, contextLength)
        let prefixStart = max(0, sourceRange.location - radius)
        let suffixEnd = min(source.length, NSMaxRange(sourceRange) + radius)
        self.unitOrdinal = unitOrdinal
        sourceStart = sourceRange.location
        sourceLength = sourceRange.length
        exactQuote = source.substring(with: sourceRange)
        prefix = source.substring(with: NSRange(
            location: prefixStart,
            length: sourceRange.location - prefixStart
        ))
        suffix = source.substring(with: NSRange(
            location: NSMaxRange(sourceRange),
            length: suffixEnd - NSMaxRange(sourceRange)
        ))
        self.version = version
    }

    func resolvedRange(in sourceText: String) -> NSRange? {
        let source = sourceText as NSString
        let expected = NSRange(location: sourceStart, length: sourceLength)
        if expected.location >= 0,
           expected.length > 0,
           NSMaxRange(expected) <= source.length,
           source.substring(with: expected) == exactQuote {
            return expected
        }
        guard !exactQuote.isEmpty else { return nil }

        var candidates: [NSRange] = []
        var searchRange = NSRange(location: 0, length: source.length)
        while searchRange.length > 0 {
            let found = source.range(of: exactQuote, options: [], range: searchRange)
            guard found.location != NSNotFound else { break }
            candidates.append(found)
            let nextLocation = NSMaxRange(found)
            guard nextLocation < source.length else { break }
            searchRange = NSRange(location: nextLocation, length: source.length - nextLocation)
        }
        guard !candidates.isEmpty else { return nil }

        return candidates.max { lhs, rhs in
            let lhsScore = contextScore(for: lhs, in: source)
            let rhsScore = contextScore(for: rhs, in: source)
            if lhsScore != rhsScore { return lhsScore < rhsScore }
            let lhsDistance = abs(lhs.location - sourceStart)
            let rhsDistance = abs(rhs.location - sourceStart)
            if lhsDistance != rhsDistance { return lhsDistance > rhsDistance }
            return lhs.location > rhs.location
        }
    }

    private func contextScore(for range: NSRange, in source: NSString) -> Int {
        let prefixLength = min(prefix.utf16.count, range.location)
        let candidatePrefix = source.substring(with: NSRange(
            location: range.location - prefixLength,
            length: prefixLength
        ))
        let suffixLength = min(suffix.utf16.count, source.length - NSMaxRange(range))
        let candidateSuffix = source.substring(with: NSRange(
            location: NSMaxRange(range),
            length: suffixLength
        ))
        return Self.commonSuffixLength(prefix, candidatePrefix)
            + Self.commonPrefixLength(suffix, candidateSuffix)
    }

    private static func commonPrefixLength(_ lhs: String, _ rhs: String) -> Int {
        zip(lhs.utf16, rhs.utf16).prefix { $0 == $1 }.count
    }

    private static func commonSuffixLength(_ lhs: String, _ rhs: String) -> Int {
        zip(lhs.utf16.reversed(), rhs.utf16.reversed()).prefix { $0 == $1 }.count
    }
}
