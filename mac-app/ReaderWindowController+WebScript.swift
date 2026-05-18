import Foundation

extension ReaderWindowController {
    static func webDocumentUserScriptSource() -> String {
        guard let url = Bundle.main.url(forResource: "reader-web", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("Missing bundled reader-web.js")
            return ""
        }
        return source
    }
}
