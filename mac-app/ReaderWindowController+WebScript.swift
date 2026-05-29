import Foundation

extension ReaderWindowController {
    static func webDocumentUserScriptSource() -> String {
        guard let helper = bundledWebScript(named: "reader-web-text"),
              let main = bundledWebScript(named: "reader-web") else {
            return ""
        }
        return helper + "\n" + main
    }

    private static func bundledWebScript(named name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("Missing bundled \(name).js")
            return nil
        }
        return source
    }
}
