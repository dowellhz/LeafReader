import Cocoa

extension ReaderWindowController {
    func aggregateVocabularyRecords(_ records: [VocabularyExportRecord]) -> [VocabularyExportRecord] {
        var order: [String] = []
        var grouped: [String: [VocabularyExportRecord]] = [:]
        for record in records.sorted(by: { $0.createdAt < $1.createdAt }) {
            let key = record.word
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !key.isEmpty else { continue }
            if grouped[key] == nil {
                order.append(key)
                grouped[key] = []
            }
            grouped[key]?.append(record)
        }

        return order.compactMap { key in
            guard let group = grouped[key], let first = group.first else { return nil }
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
            return VocabularyExportRecord(
                ids: group.flatMap(\.ids),
                word: vocabularyDisplayWord(first.word),
                answer: answer,
                location: locationText,
                context: context,
                createdAt: first.createdAt,
                srs: group.map(\.srs).min { $0.dueDate < $1.dueDate } ?? first.srs
            )
        }
    }

    func vocabularyDisplayWord(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    @objc func changeVocabularyTab(_ sender: NSSegmentedControl) {
        guard let panel = vocabularyPanel,
              let root = panel.contentView else { return }
        commitPendingVocabularyAnswerIfNeeded()
        if sender.selectedSegment == 0 {
            vocabularyListModeEnabled = false
            vocabularyReviewIndex = 0
            vocabularyReviewBatchKeys = []
            resetVocabularyReviewCardState(clearCardKey: true)
            showVocabularyReviewMode(in: root, autoPlay: true)
            return
        }
        let filter = vocabularyFilter(forSegment: sender.selectedSegment)
        vocabularyReviewFilter = filter
        vocabularyReviewIndex = 0
        vocabularyListPageIndex = 0
        resetVocabularyReviewCardState(clearCardKey: true)
        refreshVocabularyListContent(in: root, filter: filter)
        showVocabularyListMode(in: root)
    }

    func showVocabularyReviewMode(in root: NSView, autoPlay: Bool) {
        findView(identifier: "vocabularyReviewContainer", in: root)?.isHidden = false
        findView(identifier: "vocabularyScrollView", in: root)?.isHidden = true
        findView(identifier: "vocabularyExportMarkdownButton", in: root)?.isHidden = true
        findView(identifier: "vocabularyExportCSVButton", in: root)?.isHidden = true
        if let reviewContainer = findView(identifier: "vocabularyReviewContainer", in: root) {
            let isDark = ReaderTheme.selected == .dark
            populateVocabularyReviewContainer(reviewContainer, records: currentVocabularyExportRecords, filter: vocabularyReviewFilter, isDark: isDark, autoPlayNewCard: autoPlay)
        }
    }

    func showVocabularyListMode(in root: NSView) {
        vocabularyListModeEnabled = true
        findView(identifier: "vocabularyReviewContainer", in: root)?.isHidden = true
        findView(identifier: "vocabularyScrollView", in: root)?.isHidden = false
        findView(identifier: "vocabularyExportMarkdownButton", in: root)?.isHidden = false
        findView(identifier: "vocabularyExportCSVButton", in: root)?.isHidden = false
    }

    func refreshVocabularyListContent(in root: NSView, filter: VocabularyFilter) {
        let isDark = ReaderTheme.selected == .dark
        if let stack = findView(identifier: "vocabularyStack", in: root) as? NSStackView {
            populateVocabularyStack(stack, records: currentVocabularyExportRecords, filter: filter, isDark: isDark)
        }
        if let summary = findView(identifier: "vocabularySummaryLabel", in: root) as? NSTextField {
            summary.stringValue = vocabularySummaryText(records: currentVocabularyExportRecords, filter: filter)
        }
    }

    func vocabularyFilter(forSegment selectedSegment: Int) -> VocabularyFilter {
        switch selectedSegment {
        case 1:
            return .due
        case 2:
            return .new
        case 3:
            return .all
        default:
            return vocabularyReviewFilter
        }
    }

    func selectedVocabularyListFilter(in root: NSView?) -> VocabularyFilter {
        guard let root,
              let filterControl = root.subviews.compactMap({ $0 as? NSSegmentedControl }).first else {
            return vocabularyReviewFilter
        }
        return vocabularyFilter(forSegment: filterControl.selectedSegment)
    }

}
