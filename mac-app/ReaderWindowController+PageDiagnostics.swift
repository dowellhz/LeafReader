import Foundation

extension ReaderWindowController {
    private static let pageJumpDiagnosticsDefaultsKey = "leafReader.pageJumpDiagnostics"
    private static let pageJumpDiagnosticsEnabledKey = "leafReader.enablePageJumpDiagnostics"

    func recordPageJump(source: String, before: Int? = nil, after: Int? = nil, detail: String = "") {
        let entry = PageJumpDiagnosticEntry(
            date: Date(),
            source: source,
            beforePageIndex: before,
            afterPageIndex: after,
            detail: detail
        )
        pageJumpDiagnostics.append(entry)
        if pageJumpDiagnostics.count > 50 {
            pageJumpDiagnostics.removeFirst(pageJumpDiagnostics.count - 50)
        }

        guard Self.isPageJumpDiagnosticsPersistenceEnabled else { return }
        persistPageJumpDiagnostic(entry)
        NSLog("[PageJump] \(entry.diagnosticText)")
    }

    func recentPageJumpDiagnosticsText() -> String {
        if !pageJumpDiagnostics.isEmpty {
            return pageJumpDiagnostics.map(\.diagnosticText).joined(separator: "\n")
        }
        return Self.persistedPageJumpDiagnosticsText()
    }

    static var isPageJumpDiagnosticsPersistenceEnabled: Bool {
        #if DEBUG
        return true
        #else
        return UserDefaults.standard.bool(forKey: pageJumpDiagnosticsEnabledKey)
        #endif
    }

    static func setPageJumpDiagnosticsPersistenceEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: pageJumpDiagnosticsEnabledKey)
    }

    static func persistedPageJumpDiagnosticsText() -> String {
        (UserDefaults.standard.stringArray(forKey: pageJumpDiagnosticsDefaultsKey) ?? [])
            .map(persistedDiagnosticLineText)
            .joined(separator: "\n")
    }

    private func persistPageJumpDiagnostic(_ entry: PageJumpDiagnosticEntry) {
        var persisted = UserDefaults.standard.stringArray(forKey: Self.pageJumpDiagnosticsDefaultsKey) ?? []
        let beforeText = entry.beforePageIndex.map { String($0 + 1) } ?? "-"
        let afterText = entry.afterPageIndex.map { String($0 + 1) } ?? "-"
        persisted.append("\(entry.date.timeIntervalSince1970)|\(entry.source)|\(beforeText)|\(afterText)|\(entry.detail)")
        if persisted.count > 50 {
            persisted.removeFirst(persisted.count - 50)
        }
        UserDefaults.standard.set(persisted, forKey: Self.pageJumpDiagnosticsDefaultsKey)
    }

    private static func persistedDiagnosticLineText(_ line: String) -> String {
        let parts = line.split(separator: "|", maxSplits: 4, omittingEmptySubsequences: false)
        guard parts.count >= 5,
              let timestamp = TimeInterval(parts[0]) else {
            return line
        }
        let date = Date(timeIntervalSince1970: timestamp)
        let detail = parts[4].isEmpty ? "" : " \(parts[4])"
        return "\(date) \(parts[1]) \(parts[2])->\(parts[3])\(detail)"
    }
}

private extension ReaderWindowController.PageJumpDiagnosticEntry {
    var diagnosticText: String {
        let before = beforePageIndex.map { String($0 + 1) } ?? "-"
        let after = afterPageIndex.map { String($0 + 1) } ?? "-"
        let detail = detail.isEmpty ? "" : " \(detail)"
        return "\(date) \(source) \(before)->\(after)\(detail)"
    }
}
