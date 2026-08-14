import Foundation

enum VocabularyRecordProvider {
    static func records(
        documentKind: ReaderDocumentKind,
        pdfRecords: [StoredPDFWordRecord],
        webRecords: [StoredWebWordRecord],
        pdfContext: (StoredPDFWordRecord) -> String
    ) -> [VocabularyExportRecord] {
        let records: [VocabularyExportRecord]
        if documentKind == .pdf {
            records = pdfRecords
                .filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map {
                    VocabularyExportRecord(
                        ids: [$0.id],
                        word: $0.word,
                        answer: $0.answer,
                        dictionaryTags: $0.dictionaryTags,
                        dictionaryFrequency: $0.dictionaryFrequency,
                        location: AppText.localized("第 \($0.pageIndex + 1) 页", "p. \($0.pageIndex + 1)"),
                        context: pdfContext($0),
                        createdAt: $0.createdAt,
                        srs: $0.srs ?? VocabularySRSState.initial(createdAt: $0.createdAt)
                    )
                }
        } else {
            records = webRecords
                .filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map {
                    VocabularyExportRecord(
                        ids: [$0.id],
                        word: $0.word,
                        answer: $0.answer,
                        dictionaryTags: $0.dictionaryTags,
                        dictionaryFrequency: $0.dictionaryFrequency,
                        location: AppText.localized("进度 \(Int(($0.scrollProgress * 100).rounded()))%", "\(Int(($0.scrollProgress * 100).rounded()))%"),
                        context: $0.context,
                        createdAt: $0.createdAt,
                        srs: $0.srs ?? VocabularySRSState.initial(createdAt: $0.createdAt)
                    )
                }
        }
        return aggregate(records)
    }

    static func aggregate(_ records: [VocabularyExportRecord]) -> [VocabularyExportRecord] {
        var order: [String] = []
        var grouped: [String: [(record: VocabularyExportRecord, identity: VocabularyWordIdentity)]] = [:]
        for record in records.sorted(by: { $0.createdAt < $1.createdAt }) {
            let identity = VocabularyLemmaResolver.identity(for: record.word, context: record.context)
            let key = identity.groupingKey
            guard !identity.surface.isEmpty else { continue }
            if grouped[key] == nil {
                order.append(key)
                grouped[key] = []
            }
            grouped[key]?.append((record, identity))
        }

        return order.compactMap { key in
            guard let entries = grouped[key], let firstEntry = entries.first else { return nil }
            let group = entries.map(\.record)
            let first = firstEntry.record
            var seenLocations = Set<String>()
            let locations = group.map(\.location).filter { location in
                guard !seenLocations.contains(location) else { return false }
                seenLocations.insert(location)
                return true
            }
            let locationText: String
            if group.count > 1 {
                locationText = AppText.localized(
                    "出现 \(group.count) 次：\(locations.prefix(6).joined(separator: "、"))",
                    "\(group.count) occurrences: \(locations.prefix(6).joined(separator: ", "))"
                )
            } else {
                locationText = first.location
            }
            let context = group
                .map(\.context)
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
            let answer = group
                .map(\.answer)
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? first.answer
            let dictionaryTags = group
                .compactMap(\.dictionaryTags)
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let dictionaryFrequency = group
                .compactMap(\.dictionaryFrequency)
                .min()
            var seenForms = Set<String>()
            let surfaceForms = entries.compactMap { entry -> String? in
                let form = displayWord(entry.identity.surface)
                let formKey = form.lowercased()
                guard !form.isEmpty, seenForms.insert(formKey).inserted else { return nil }
                return form
            }
            return VocabularyExportRecord(
                ids: group.flatMap(\.ids),
                word: displayWord(first.word),
                lemma: firstEntry.identity.lemma,
                surfaceForms: surfaceForms,
                answer: answer,
                dictionaryTags: dictionaryTags,
                dictionaryFrequency: dictionaryFrequency,
                location: locationText,
                context: context,
                createdAt: first.createdAt,
                srs: group.map(\.srs).min { $0.dueDate < $1.dueDate } ?? first.srs
            )
        }
    }

    static func displayWord(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
