import Foundation

struct PDFReadAloudPageText {
    let pageIndex: Int
    let speechSourceText: String
    let fullPageText: String
}

struct PDFReadAloudMatchedSegment {
    let speechText: String
    let sourceText: String
    let pageIndex: Int
    let range: NSRange?
}

enum PDFReadAloudSegmentMatcher {
    static func segments(from pages: [PDFReadAloudPageText]) -> [PDFReadAloudMatchedSegment] {
        var matchedSegments: [PDFReadAloudMatchedSegment] = []
        for page in pages {
            matchedSegments.append(contentsOf: segments(from: page))
        }
        return matchedSegments
    }

    private static func segments(from page: PDFReadAloudPageText) -> [PDFReadAloudMatchedSegment] {
        let text = page.speechSourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        var searchLocation = 0
        return SpeechTextPolicy.segments(for: text).compactMap { sourceSegment in
            let speechText = SpeechTextPolicy.normalizedReadAloudInput(sourceSegment)
            guard !speechText.isEmpty else { return nil }
            let matchRange = matchRange(
                for: sourceSegment,
                in: page.fullPageText,
                searchLocation: &searchLocation
            )
            return PDFReadAloudMatchedSegment(
                speechText: speechText,
                sourceText: sourceSegment,
                pageIndex: page.pageIndex,
                range: matchRange
            )
        }
    }

    private static func matchRange(
        for sourceSegment: String,
        in pageText: String,
        searchLocation: inout Int
    ) -> NSRange? {
        guard !pageText.isEmpty else { return nil }
        let nsText = pageText as NSString
        let safeLocation = min(max(0, searchLocation), nsText.length)
        let searchRange = NSRange(location: safeLocation, length: nsText.length - safeLocation)
        let range = ReadAloudTextMatcher.range(
            of: sourceSegment,
            in: pageText,
            searchRange: searchRange,
            allowsPartialFallback: false
        ) ?? ReadAloudTextMatcher.range(
            of: sourceSegment,
            in: pageText,
            searchRange: searchRange
        )
        if let range {
            searchLocation = NSMaxRange(range)
        }
        return range
    }
}
