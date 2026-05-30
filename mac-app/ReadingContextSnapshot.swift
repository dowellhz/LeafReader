import Foundation

struct ReadingContextSnapshot {
    let title: String
    let documentKind: ReaderDocumentKind
    let locationLabel: String
    let visibleText: String
    let nearbyText: String
    let focusedSelection: ReaderFocusedSelection?

    init(
        title: String,
        documentKind: ReaderDocumentKind,
        locationLabel: String,
        visibleText: String,
        nearbyText: String,
        focusedSelection: ReaderFocusedSelection?
    ) {
        self.title = title
        self.documentKind = documentKind
        self.locationLabel = locationLabel
        self.visibleText = visibleText
        self.nearbyText = nearbyText
        self.focusedSelection = focusedSelection
    }

    init(
        title: String,
        documentKind: ReaderDocumentKind,
        locationLabel: String,
        visibleText: String,
        nearbyText: String,
        selectedText: String,
        selectedContext: String
    ) {
        self.init(
            title: title,
            documentKind: documentKind,
            locationLabel: locationLabel,
            visibleText: visibleText,
            nearbyText: nearbyText,
            focusedSelection: ReaderFocusedSelection.make(
                explicitSelection: selectedText,
                readAloudSelection: "",
                explicitContext: selectedContext,
                readAloudContext: ""
            )
        )
    }

    var selectedText: String {
        focusedSelection?.text ?? ""
    }

    var selectedContext: String {
        focusedSelection?.context ?? ""
    }

    var currentContentTitle: String {
        let trimmedLocation = trimmed(locationLabel)
        return trimmedLocation.isEmpty ? title : "\(title) - \(trimmedLocation)"
    }

    var readingText: String {
        let visible = trimmed(visibleText)
        if !visible.isEmpty { return visible }
        return trimmed(nearbyText)
    }

    var focusedReadingText: String {
        let selected = trimmed(selectedText)
        return selected.isEmpty ? readingText : selected
    }

    var contextText: String {
        var parts: [String] = []
        if hasTrimmedText(locationLabel) {
            parts.append(AppText.localized("【当前位置】\n\(locationLabel)", "[Current location]\n\(locationLabel)"))
        }
        if let focusedSelection, hasTrimmedText(focusedSelection.text) {
            let title = focusedSelection.origin == .readAloudSegment
                ? AppText.localized("【当前朗读内容】", "[Current read-aloud text]")
                : AppText.localized("【当前选中内容】", "[Selected text]")
            parts.append("\(title)\n\(focusedSelection.text)")
        }
        if let focusedSelection, hasTrimmedText(focusedSelection.context) {
            let title = focusedSelection.origin == .readAloudSegment
                ? AppText.localized("【朗读内容附近上下文】", "[Read-aloud context]")
                : AppText.localized("【选中内容附近上下文】", "[Selection context]")
            parts.append("\(title)\n\(focusedSelection.context)")
        }
        if hasTrimmedText(nearbyText) {
            parts.append(AppText.localized("【当前位置附近内容】\n\(nearbyText)", "[Nearby reading text]\n\(nearbyText)"))
        }
        return String(parts.joined(separator: "\n\n").prefix(5000))
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func hasTrimmedText(_ text: String) -> Bool {
        !trimmed(text).isEmpty
    }
}
