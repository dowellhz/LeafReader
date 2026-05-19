import Foundation

struct ReadingContextSnapshot {
    let title: String
    let documentKind: ReaderDocumentKind
    let locationLabel: String
    let visibleText: String
    let nearbyText: String
    let selectedText: String
    let selectedContext: String

    var currentContentTitle: String {
        let trimmedLocation = trimmed(locationLabel)
        return trimmedLocation.isEmpty ? title : "\(title) - \(trimmedLocation)"
    }

    var readingText: String {
        let visible = trimmed(visibleText)
        if !visible.isEmpty { return visible }
        return trimmed(nearbyText)
    }

    var contextText: String {
        var parts: [String] = []
        if hasTrimmedText(locationLabel) {
            parts.append(AppText.localized("【当前位置】\n\(locationLabel)", "[Current location]\n\(locationLabel)"))
        }
        if hasTrimmedText(selectedText) {
            parts.append(AppText.localized("【当前选中内容】\n\(selectedText)", "[Selected text]\n\(selectedText)"))
        }
        if hasTrimmedText(selectedContext) {
            parts.append(AppText.localized("【选中内容附近上下文】\n\(selectedContext)", "[Selection context]\n\(selectedContext)"))
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
