import Foundation
import CryptoKit
import PDFKit

struct PDFDocumentAgentEvidence {
    let pageIndex: Int
    let chunkID: String
    let text: String
    let score: Double

    var pageNumber: Int {
        pageIndex + 1
    }
}

final class PDFDocumentAgentIndex {
    private struct Chunk {
        let id: String
        let pageIndex: Int
        let chunkIndex: Int
        let text: String
        let normalizedText: String
        let tokens: Set<String>
        var embedding: [Float]?
        var embeddingNorm: Float?
    }

    private var chunks: [Chunk]

    init(document: PDFDocument, title: String) {
        var builtChunks: [Chunk] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let pageText = ReaderAIContextBuilder.pdfPageTranslationText(document: document, page: page, title: title)
            builtChunks.append(contentsOf: Self.chunks(from: pageText, pageIndex: pageIndex))
        }
        chunks = builtChunks
    }

    init(text: String) {
        let sections = Self.sections(from: text)
        chunks = sections.enumerated().flatMap { sectionIndex, sectionText in
            Self.chunks(from: sectionText, pageIndex: sectionIndex)
        }
    }

    var locationCount: Int {
        Set(chunks.map(\.pageIndex)).count
    }

    var indexableChunks: [(id: String, pageIndex: Int, chunkIndex: Int, text: String)] {
        chunks.map { ($0.id, $0.pageIndex, $0.chunkIndex, $0.text) }
    }

    var embeddingCoverage: (embedded: Int, total: Int) {
        (chunks.filter { $0.embedding != nil }.count, chunks.count)
    }

    func search(question: String, currentPageIndex: Int?, limit: Int = 6) -> [PDFDocumentAgentEvidence] {
        search(question: question, currentPageIndex: currentPageIndex, queryEmbedding: nil, limit: limit)
    }

    func search(question: String, currentPageIndex: Int?, queryEmbedding: [Float]?, limit: Int = 6) -> [PDFDocumentAgentEvidence] {
        let normalizedQuestion = Self.normalized(question)
        let queryTokens = Self.tokens(from: question)
        guard !queryTokens.isEmpty || queryEmbedding != nil else { return [] }

        let queryEmbeddingNorm = queryEmbedding.flatMap(Self.vectorNorm)
        let scored = chunks.compactMap { chunk -> PDFDocumentAgentEvidence? in
            let overlap = queryTokens.intersection(chunk.tokens)
            let vectorScore: Float? = queryEmbedding.flatMap { queryEmbedding -> Float? in
                guard let queryEmbeddingNorm,
                      let embedding = chunk.embedding,
                      let embeddingNorm = chunk.embeddingNorm else {
                    return nil
                }
                return Self.cosineSimilarity(queryEmbedding, embedding, lhsNorm: queryEmbeddingNorm, rhsNorm: embeddingNorm)
            }
            guard !overlap.isEmpty || chunk.normalizedText.contains(normalizedQuestion) || vectorScore != nil else { return nil }

            var score = Double(overlap.count) * 3
            for token in overlap {
                if token.count >= 4, chunk.normalizedText.contains(token) {
                    score += 1
                }
            }
            if !normalizedQuestion.isEmpty, chunk.normalizedText.contains(normalizedQuestion) {
                score += 8
            }
            if let currentPageIndex {
                let distance = abs(chunk.pageIndex - currentPageIndex)
                score += max(0, 3 - Double(distance) * 0.75)
            }
            if let vectorScore {
                score += Double(vectorScore) * 12
            }
            return PDFDocumentAgentEvidence(pageIndex: chunk.pageIndex, chunkID: chunk.id, text: chunk.text, score: score)
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.pageIndex < rhs.pageIndex
                }
                return lhs.score > rhs.score
            }
            .prefix(limit)
            .map { $0 }
    }

    func missingEmbeddingChunks(limit: Int = 48, preferredPageIndex: Int? = nil, preferredRadius: Int = 2) -> [(id: String, pageIndex: Int, chunkIndex: Int, text: String)] {
        let missing = chunks.filter { $0.embedding == nil }
        let ordered: [Chunk]
        if let preferredPageIndex {
            ordered = missing.sorted { lhs, rhs in
                let lhsDistance = abs(lhs.pageIndex - preferredPageIndex)
                let rhsDistance = abs(rhs.pageIndex - preferredPageIndex)
                let lhsPriority = lhsDistance <= preferredRadius ? 0 : 1
                let rhsPriority = rhsDistance <= preferredRadius ? 0 : 1
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
                if lhs.pageIndex != rhs.pageIndex { return lhs.pageIndex < rhs.pageIndex }
                return lhs.chunkIndex < rhs.chunkIndex
            }
        } else {
            ordered = missing
        }
        return ordered
            .prefix(limit)
            .map { ($0.id, $0.pageIndex, $0.chunkIndex, $0.text) }
    }

    func applyEmbeddings(_ embeddingsByChunkID: [String: [Float]]) {
        guard !embeddingsByChunkID.isEmpty else { return }
        for index in chunks.indices {
            if let embedding = embeddingsByChunkID[chunks[index].id] {
                chunks[index].embedding = embedding
                chunks[index].embeddingNorm = Self.vectorNorm(embedding)
            }
        }
    }

    static func evidenceText(_ evidence: [PDFDocumentAgentEvidence], locationName: String = "Page", maxCharacters: Int = 7000) -> String {
        var remaining = maxCharacters
        var parts: [String] = []
        for item in evidence {
            guard remaining > 0 else { break }
            let text = String(item.text.prefix(max(0, min(remaining, 1400))))
            guard !text.isEmpty else { continue }
            let label: String
            if AppText.isChinese, locationName == "Page" {
                label = "第 \(item.pageNumber) 页"
            } else {
                label = "\(locationName) \(item.pageNumber)"
            }
            let part = "[\(label)]\n\(text)"
            parts.append(part)
            remaining -= part.count
        }
        return parts.joined(separator: "\n\n")
    }

    private static func sections(from text: String, targetLength: Int = 2600) -> [String] {
        let normalized = ReaderAIContextBuilder.normalizeReaderTextPreservingParagraphs(text)
        guard !normalized.isEmpty else { return [] }

        let paragraphs = normalized
            .components(separatedBy: "\n\n")
            .map { ReaderAIContextBuilder.normalizeWhitespace($0) }
            .filter { !$0.isEmpty }

        var sections: [String] = []
        var current = ""

        func flush() {
            let text = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                sections.append(text)
            }
            current = ""
        }

        for paragraph in paragraphs {
            if current.count + paragraph.count > targetLength {
                flush()
            }
            if paragraph.count > targetLength * 2 {
                var start = paragraph.startIndex
                while start < paragraph.endIndex {
                    let end = paragraph.index(start, offsetBy: targetLength, limitedBy: paragraph.endIndex) ?? paragraph.endIndex
                    sections.append(String(paragraph[start..<end]))
                    start = end
                }
                continue
            }
            current = current.isEmpty ? paragraph : "\(current)\n\(paragraph)"
        }
        flush()
        return sections
    }

    private static func chunks(from text: String, pageIndex: Int) -> [Chunk] {
        let normalized = ReaderAIContextBuilder.normalizeReaderTextPreservingParagraphs(text)
        guard !normalized.isEmpty else { return [] }

        let paragraphs = normalized
            .components(separatedBy: "\n\n")
            .map { ReaderAIContextBuilder.normalizeWhitespace($0) }
            .filter { !$0.isEmpty }

        var chunks: [Chunk] = []
        var current = ""

        func flush() {
            let text = current.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let chunkIndex = chunks.count
            chunks.append(Chunk(
                id: chunkID(pageIndex: pageIndex, chunkIndex: chunkIndex, text: text),
                pageIndex: pageIndex,
                chunkIndex: chunkIndex,
                text: String(text.prefix(1600)),
                normalizedText: Self.normalized(text),
                tokens: Self.tokens(from: text),
                embedding: nil,
                embeddingNorm: nil
            ))
            current = ""
        }

        for paragraph in paragraphs {
            if current.count + paragraph.count > 1200 {
                flush()
            }
            if paragraph.count > 1600 {
                chunks.append(contentsOf: splitLongParagraph(paragraph, pageIndex: pageIndex))
                continue
            }
            current = current.isEmpty ? paragraph : "\(current)\n\(paragraph)"
        }
        flush()
        return chunks
    }

    private static func splitLongParagraph(_ paragraph: String, pageIndex: Int) -> [Chunk] {
        var result: [Chunk] = []
        var start = paragraph.startIndex
        while start < paragraph.endIndex {
            let end = paragraph.index(start, offsetBy: 1200, limitedBy: paragraph.endIndex) ?? paragraph.endIndex
            let piece = String(paragraph[start..<end])
            let chunkIndex = result.count
            result.append(Chunk(
                id: chunkID(pageIndex: pageIndex, chunkIndex: chunkIndex, text: piece),
                pageIndex: pageIndex,
                chunkIndex: chunkIndex,
                text: piece,
                normalizedText: normalized(piece),
                tokens: tokens(from: piece),
                embedding: nil,
                embeddingNorm: nil
            ))
            start = end
        }
        return result
    }

    private static func chunkID(pageIndex: Int, chunkIndex: Int, text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        let hash = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return "\(pageIndex)-\(chunkIndex)-\(hash)"
    }

    private static func vectorNorm(_ values: [Float]) -> Float? {
        guard !values.isEmpty else { return nil }
        var norm: Float = 0
        for value in values {
            norm += value * value
        }
        guard norm > 0 else { return nil }
        return sqrt(norm)
    }

    private static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float], lhsNorm: Float, rhsNorm: Float) -> Float? {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return nil }
        var dot: Float = 0
        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
        }
        return dot / (lhsNorm * rhsNorm)
    }

    private static func normalized(_ text: String) -> String {
        ReaderAIContextBuilder.normalizeWhitespace(text).lowercased()
    }

    private static func tokens(from text: String) -> Set<String> {
        let normalized = normalized(text)
        let pattern = #"[a-z0-9][a-z0-9_-]{1,}|\p{Han}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        return Set(regex.matches(in: normalized, range: range).compactMap { match in
            guard let range = Range(match.range, in: normalized) else { return nil }
            let token = String(normalized[range])
            return stopWords.contains(token) ? nil : token
        })
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "that", "this", "with", "from", "are", "was", "were",
        "you", "your", "what", "when", "where", "which", "how", "why", "does",
        "have", "has", "had", "not", "can", "could", "would", "should", "about",
        "into", "than", "then", "there", "their", "them", "they", "its", "it"
    ]
}
