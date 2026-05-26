import Cocoa

extension ReaderWindowController {
    func populateVocabularyStack(_ stack: NSStackView, records: [VocabularyExportRecord], filter: VocabularyFilter, isDark: Bool) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let page = vocabularyReviewSession.currentListPageRecords(records, matching: filter)
        if page.total == 0 {
            stack.addArrangedSubview(emptyVocabularyState(filter: filter, isDark: isDark))
            return
        }
        for record in page.records {
            stack.addArrangedSubview(vocabularyCard(record: record, isDark: isDark))
        }
        if page.pageCount > 1 {
            stack.addArrangedSubview(vocabularyPaginationView(currentPage: page.pageIndex, pageCount: page.pageCount, total: page.total, isDark: isDark))
        }
    }

    func vocabularyPaginationView(currentPage: Int, pageCount: Int, total: Int, isDark: Bool) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let previousButton = vocabularyActionButton(title: AppText.localized("上一页", "Previous"), target: self, action: #selector(previousVocabularyListPage(_:)), fontSize: 13)
        previousButton.isEnabled = currentPage > 0

        let nextButton = vocabularyActionButton(title: AppText.localized("下一页", "Next"), target: self, action: #selector(nextVocabularyListPage(_:)), fontSize: 13)
        nextButton.isEnabled = currentPage + 1 < pageCount

        let pageLabel = NSTextField(labelWithString: AppText.localized("第 \(currentPage + 1) / \(pageCount) 页 · 共 \(total) 个", "Page \(currentPage + 1) / \(pageCount) · \(total) total"))
        pageLabel.font = AppFont.semibold(ofSize: 13)
        pageLabel.textColor = isDark ? NSColor(red: 0.60, green: 0.67, blue: 0.76, alpha: 1) : NSColor(red: 0.48, green: 0.54, blue: 0.66, alpha: 1)
        pageLabel.alignment = .center
        pageLabel.translatesAutoresizingMaskIntoConstraints = false

        for view in [previousButton, pageLabel, nextButton] {
            container.addSubview(view)
        }

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 52),
            previousButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            previousButton.trailingAnchor.constraint(equalTo: pageLabel.leadingAnchor, constant: -14),
            previousButton.widthAnchor.constraint(equalToConstant: 86),
            previousButton.heightAnchor.constraint(equalToConstant: 32),
            pageLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            pageLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            pageLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
            nextButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            nextButton.leadingAnchor.constraint(equalTo: pageLabel.trailingAnchor, constant: 14),
            nextButton.widthAnchor.constraint(equalToConstant: 86),
            nextButton.heightAnchor.constraint(equalToConstant: 32)
        ])
        return container
    }

    @objc func previousVocabularyListPage(_ sender: NSButton) {
        guard vocabularyReviewSession.goToPreviousListPage() else { return }
        reloadVocabularyPanelContent()
    }

    @objc func nextVocabularyListPage(_ sender: NSButton) {
        vocabularyReviewSession.goToNextListPage()
        reloadVocabularyPanelContent()
    }

    func emptyVocabularyState(filter: VocabularyFilter, isDark: Bool) -> NSView {
        let label = NSTextField(labelWithString: {
            switch filter {
            case .due:
                return AppText.localized("今天还没有学习过的单词", "No words studied today")
            case .new:
                return AppText.localized("今天没有新加入的单词", "No new words added today")
            case .all:
                return AppText.localized("暂无单词", "No words yet")
            }
        }())
        label.font = AppFont.semibold(ofSize: 15)
        label.textColor = isDark ? NSColor(red: 0.60, green: 0.67, blue: 0.76, alpha: 1) : NSColor(red: 0.48, green: 0.54, blue: 0.66, alpha: 1)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(label)
        NSLayoutConstraint.activate([
            wrapper.heightAnchor.constraint(equalToConstant: 120),
            label.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor)
        ])
        return wrapper
    }
}
