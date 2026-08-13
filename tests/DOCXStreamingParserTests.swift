import Foundation

private func assert(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("DOCXStreamingParserTests failed: \(message)\n", stderr)
        exit(1)
    }
}

private func writeFixture(root: URL, title: String) throws -> URL {
    let wordDirectory = root.appendingPathComponent("word", isDirectory: true)
    let relationshipsDirectory = wordDirectory.appendingPathComponent("_rels", isDirectory: true)
    let mediaDirectory = wordDirectory.appendingPathComponent("media", isDirectory: true)
    try FileManager.default.createDirectory(at: relationshipsDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
    let documentXML = """
    <w:document
      xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
      xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
      xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
      <w:body>
        <w:p><w:pPr><w:pStyle w:val="Heading1"/><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/></w:rPr><w:t>\(title)</w:t></w:r></w:p>
        <w:tbl><w:tr><w:tc><w:p><w:r><w:t>Inside table</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
        <w:p><w:pPr><w:numPr/></w:pPr><w:r><w:t>- Item</w:t></w:r></w:p>
        <w:p><w:r><w:drawing><a:blip r:embed="image"/></w:drawing></w:r></w:p>
      </w:body>
    </w:document>
    """
    try Data(documentXML.utf8).write(to: wordDirectory.appendingPathComponent("document.xml"))
    let relationshipsXML = """
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="image" Target="media/image 1.png"/>
    </Relationships>
    """
    try Data(relationshipsXML.utf8).write(
        to: relationshipsDirectory.appendingPathComponent("document.xml.rels")
    )
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: mediaDirectory.appendingPathComponent("image 1.png"))
    return wordDirectory.appendingPathComponent("document.xml")
}

private func makeArchive(from root: URL, at archiveURL: URL) throws {
    try? FileManager.default.removeItem(at: archiveURL)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    process.currentDirectoryURL = root
    process.arguments = ["-q", "-r", archiveURL.path, "word"]
    try process.run()
    process.waitUntilExit()
    assert(process.terminationStatus == 0, "fixture archive creation should succeed")
}

@main
private struct DOCXStreamingParserTestRunner {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("leafreader-docx-tests-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        let archiveURL = root.appendingPathComponent("fixture.docx")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        defer {
            unsetenv("LEAFREADER_DOCX_CACHE_ROOT")
            try? FileManager.default.removeItem(at: root)
        }
        setenv("LEAFREADER_DOCX_CACHE_ROOT", cache.path, 1)

        let documentXMLURL = try writeFixture(root: source, title: "First title")
        let streaming = try WebDocumentLoader.docxStreamingContent(
            from: documentXMLURL,
            directory: source,
            relationships: ["image": "media/image 1.png"]
        )
        assert(streaming.plainText == ["First title", "Inside table", "- Item"], "streaming text should preserve document order")
        assert(streaming.html.contains("<h1 id=\"docx-heading-1\" class=\"docx-align-center\"><strong>First title</strong></h1>"), "streaming HTML should preserve heading formatting")
        assert(streaming.html.contains("<ul>\n<li>Item</li>\n</ul>"), "streaming HTML should preserve list structure")
        assert(streaming.tocItems.first?.title == "First title", "streaming parser should emit TOC items")

        try makeArchive(from: source, at: archiveURL)
        let first = try WebDocumentLoader.loadDOCX(url: archiveURL)
        guard let firstHTMLURL = first.htmlFileURL else {
            assert(false, "prepared DOCX should load from an HTML file")
            return
        }
        assert(first.ownedResource == nil, "prepared DOCX cache should not be owned as a temporary resource")
        assert(first.plainText.contains("First title"), "prepared DOCX should expose plain text")
        let firstHTML = try String(contentsOf: firstHTMLURL, encoding: .utf8)
        assert(firstHTML.contains("First title"), "prepared HTML should contain rendered content")

        let second = try WebDocumentLoader.loadDOCX(url: archiveURL)
        assert(second.htmlFileURL == firstHTMLURL, "unchanged DOCX content should reuse its prepared cache")

        try Data("tampered".utf8).write(to: firstHTMLURL)
        let repaired = try WebDocumentLoader.loadDOCX(url: archiveURL)
        guard let repairedHTMLURL = repaired.htmlFileURL else {
            assert(false, "rebuilt DOCX should retain its prepared HTML URL")
            return
        }
        let repairedHTML = try String(contentsOf: repairedHTMLURL, encoding: .utf8)
        assert(repairedHTML.contains("First title"), "invalid cached HTML should be rebuilt")

        _ = try writeFixture(root: source, title: "Other title")
        try makeArchive(from: source, at: archiveURL)
        let changed = try WebDocumentLoader.loadDOCX(url: archiveURL)
        assert(changed.htmlFileURL != firstHTMLURL, "content replacement should use a different cache identity")
        assert(changed.plainText.contains("Other title"), "changed DOCX content should be rendered")

        let token = DocumentLoadCancellationToken()
        token.cancel()
        do {
            _ = try WebDocumentLoader.loadDOCX(url: archiveURL, cancellationToken: token)
            assert(false, "a cancelled DOCX load should not return a document")
        } catch is CancellationError {
            // Expected.
        }

        print("DOCXStreamingParserTests passed")
    }
}
