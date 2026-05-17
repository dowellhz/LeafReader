import Foundation

extension ReaderWindowController {
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

        #if DEBUG
        let beforeText = before.map { String($0 + 1) } ?? "-"
        let afterText = after.map { String($0 + 1) } ?? "-"
        let suffix = detail.isEmpty ? "" : " \(detail)"
        print("[PageJump] \(source) \(beforeText)->\(afterText)\(suffix)")
        #endif
    }

    func recentPageJumpDiagnosticsText() -> String {
        pageJumpDiagnostics.map { entry in
            let before = entry.beforePageIndex.map { String($0 + 1) } ?? "-"
            let after = entry.afterPageIndex.map { String($0 + 1) } ?? "-"
            let detail = entry.detail.isEmpty ? "" : " \(entry.detail)"
            return "\(entry.date) \(entry.source) \(before)->\(after)\(detail)"
        }.joined(separator: "\n")
    }
}
