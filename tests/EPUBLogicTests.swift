import Foundation

enum EPUBLogicTests {
    static func testReaderEntityDecoding() throws {
        try expectEqual(
            EPUBHTMLSanitizer.decodeEntities("Tom &amp; Jerry &lt;3 &quot;ok&quot;"),
            "Tom & Jerry <3 \"ok\"",
            "reader entity decoding should preserve basic XML entities"
        )
        try expectEqual(
            EPUBHTMLSanitizer.decodeEntities("A&nbsp;B&ensp;C&emsp;D"),
            "A\u{00A0}B\u{2002}C\u{2003}D",
            "reader entity decoding should handle common spacing entities"
        )
        try expectEqual(
            EPUBHTMLSanitizer.decodeEntities("&#20013;&#x6587; &ldquo;quote&rdquo;&hellip;"),
            "\u{4E2D}\u{6587} \u{201C}quote\u{201D}\u{2026}",
            "reader entity decoding should handle decimal, hex, and punctuation entities"
        )
        try expectEqual(
            EPUBHTMLSanitizer.decodeEntities("&amp;lt;tag&amp;gt;"),
            "&lt;tag&gt;",
            "reader entity decoding should avoid recursive over-decoding"
        )
    }

    static func testEPUBTextDecoding() throws {
        let bomData = Data([0xEF, 0xBB, 0xBF]) + Data("hello".utf8)
        try expectEqual(
            EPUBTextDecoder.text(from: bomData),
            "hello",
            "EPUB text decoder should strip UTF-8 BOM"
        )

        let latin1Bytes = Array(#"<html><meta charset="iso-8859-1"><body>caf"#.utf8)
            + [0xE9]
            + Array("</body></html>".utf8)
        let latin1Text = EPUBTextDecoder.text(from: Data(latin1Bytes)) ?? ""
        try expect(
            latin1Text.contains("café"),
            "EPUB text decoder should respect declared Latin-1 charset"
        )
    }

    static func testEPUBSpineLinearParsing() throws {
        let xml = """
        <spine>
          <itemref idref="cover" linear="no"/>
          <itemref linear="YES" idref="chapter1"/>
          <itemref idref="chapter2"/>
          <itemref idref="notes" linear="No"/>
        </spine>
        """
        let items = EPUBPackageParser.spineItemsByRegex(from: xml)
        try expectEqual(items, [
            EPUBSpineItem(id: "cover", isLinear: false),
            EPUBSpineItem(id: "chapter1", isLinear: true),
            EPUBSpineItem(id: "chapter2", isLinear: true),
            EPUBSpineItem(id: "notes", isLinear: false)
        ], "EPUB spine parsing should preserve order and respect linear=no")
        try expectEqual(
            items.filter(\.isLinear).map(\.id),
            ["chapter1", "chapter2"],
            "EPUB reader flow should skip non-linear spine items"
        )
    }

    static func testEPUBOPFXMLParsing() throws {
        let xml = """
        <opf:package xmlns:opf="http://www.idpf.org/2007/opf">
          <opf:manifest>
            <opf:item properties="nav cover-image" media-type="application/xhtml+xml" href="nav/toc.xhtml" id="nav"></opf:item>
            <opf:item href="Text/Chapter 1.xhtml" id="chapter1" media-type="application/xhtml+xml"/>
          </opf:manifest>
          <opf:spine>
            <opf:itemref linear="no" idref="nav"></opf:itemref>
            <opf:itemref idref="chapter1"/>
          </opf:spine>
        </opf:package>
        """
        let parsed = EPUBPackageParser.package(from: xml)
        try expectEqual(parsed.manifestItems, [
            EPUBManifestItem(id: "nav", href: "nav/toc.xhtml", mediaType: "application/xhtml+xml", properties: ["nav", "cover-image"]),
            EPUBManifestItem(id: "chapter1", href: "Text/Chapter 1.xhtml", mediaType: "application/xhtml+xml", properties: [])
        ], "EPUB OPF XML parser should read manifest items with namespaces and non-self-closing tags")
        try expectEqual(parsed.spineItems, [
            EPUBSpineItem(id: "nav", isLinear: false),
            EPUBSpineItem(id: "chapter1", isLinear: true)
        ], "EPUB OPF XML parser should read spine items with namespaces and linear defaults")
    }

    static func testEPUBLazyImagesAndSafePaths() throws {
        try expectEqual(
            EPUBHTMLSanitizer.addLazyLoadingToImages(in: #"<p><img src="a.jpg"><img src="b.jpg" loading="eager"><img src="c.jpg"/></p>"#),
            #"<p><img src="a.jpg" loading="lazy"><img src="b.jpg" loading="eager"><img src="c.jpg" loading="lazy"/></p>"#,
            "EPUB image rewriting should add lazy loading without overriding explicit loading"
        )
        try expect(EPUBPathResolver.safeArchivePath("OPS/../OPS/chapter.xhtml") == nil, "safe EPUB archive path should reject parent traversal components")
        try expect(EPUBPathResolver.safeArchivePath("../secret.txt") == nil, "safe EPUB archive path should reject parent traversal")
        try expect(EPUBPathResolver.safeArchivePath("/absolute/file") == nil, "safe EPUB archive path should reject absolute paths")
    }

    static func testEPUBTOCHrefNormalization() throws {
        try expectEqual(
            EPUBPathResolver.normalizedTOCHref("../Text/Chapter%201.xhtml#sec%202", relativeTo: "OPS/nav/toc.xhtml"),
            "OPS/Text/Chapter 1.xhtml#sec 2",
            "EPUB TOC href normalization should resolve relative paths and percent escapes"
        )
        try expectEqual(
            EPUBPathResolver.normalizedTOCHref("chapter.xhtml?utm=1#p1", relativeTo: "OPS/nav.xhtml"),
            "OPS/chapter.xhtml#p1",
            "EPUB TOC href normalization should drop query strings"
        )
        try expectEqual(
            EPUBPathResolver.normalizedTOCHref("#local", relativeTo: "OPS/nav.xhtml"),
            "#local",
            "EPUB TOC href normalization should preserve same-document fragments"
        )
        try expectEqual(
            EPUBPathResolver.normalizedTOCHref("chapter&amp;notes.xhtml", relativeTo: "OPS/nav.xhtml"),
            "OPS/chapter&notes.xhtml",
            "EPUB TOC href normalization should decode HTML entities"
        )
    }

    static func testEPUBInternalLinkTargetsAndSanitizing() throws {
        let root = URL(fileURLWithPath: "/tmp/book", isDirectory: true)
        let documentBase = root.appendingPathComponent("OPS", isDirectory: true)
        let chapterBase = documentBase.appendingPathComponent("Text", isDirectory: true)

        try expectEqual(
            EPUBPathResolver.internalLinkTarget("../Notes/end.xhtml#note%201", resourceBaseURL: chapterBase, documentBaseURL: documentBase, epubRootURL: root),
            "Notes/end.xhtml#note 1",
            "EPUB internal link target should resolve cross-chapter links relative to the package"
        )
        try expectEqual(
            EPUBPathResolver.internalLinkTarget("#local-note", resourceBaseURL: chapterBase, documentBaseURL: documentBase, epubRootURL: root),
            "#local-note",
            "EPUB internal link target should keep same-chapter fragments"
        )
        try expect(
            EPUBPathResolver.internalLinkTarget("../../../outside.xhtml", resourceBaseURL: chapterBase, documentBaseURL: documentBase, epubRootURL: root) == nil,
            "EPUB internal link target should reject links outside the EPUB root"
        )

        let sanitized = EPUBHTMLSanitizer.sanitizeContent(#"<p onclick="x()"><script>bad()</script><iframe src="bad"></iframe><a href="javascript:bad()">x</a><img src="cover.jpg"></p>"#)
        try expect(!sanitized.localizedCaseInsensitiveContains("<script"), "EPUB sanitizer should remove scripts")
        try expect(!sanitized.localizedCaseInsensitiveContains("<iframe"), "EPUB sanitizer should remove iframes")
        try expect(!sanitized.localizedCaseInsensitiveContains("onclick"), "EPUB sanitizer should remove event handlers")
        try expect(!sanitized.localizedCaseInsensitiveContains("javascript:"), "EPUB sanitizer should neutralize javascript links")
        try expect(sanitized.contains(#"loading="lazy""#), "EPUB sanitizer should add lazy loading to images")
    }
}
