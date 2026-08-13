import Foundation

extension ReaderWindowController {
    static func webDocumentUserScriptSource() -> String {
        guard let helper = bundledWebScript(named: "reader-web-text"),
              let overlay = bundledWebScript(named: "reader-web-overlay"),
              let search = bundledWebScript(named: "reader-web-search"),
              let marks = bundledWebScript(named: "reader-web-marks"),
              let tts = bundledWebScript(named: "reader-web-tts"),
              let selection = bundledWebScript(named: "reader-web-selection"),
              let main = bundledWebScript(named: "reader-web") else {
            return ""
        }
        return [helper, overlay, search, marks, tts, selection, main].joined(separator: "\n")
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
