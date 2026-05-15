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
        let trimmedLocation = locationLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedLocation.isEmpty ? title : "\(title) - \(trimmedLocation)"
    }

    var readingText: String {
        let visible = visibleText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !visible.isEmpty { return visible }
        return nearbyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var contextText: String {
        var parts: [String] = []
        if !locationLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(AppText.localized("【当前位置】\n\(locationLabel)", "[Current location]\n\(locationLabel)"))
        }
        if !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(AppText.localized("【当前选中内容】\n\(selectedText)", "[Selected text]\n\(selectedText)"))
        }
        if !selectedContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(AppText.localized("【选中内容附近上下文】\n\(selectedContext)", "[Selection context]\n\(selectedContext)"))
        }
        if !nearbyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(AppText.localized("【当前位置附近内容】\n\(nearbyText)", "[Nearby reading text]\n\(nearbyText)"))
        }
        return String(parts.joined(separator: "\n\n").prefix(5000))
    }
}
