import Cocoa
import Foundation

enum ReadingNoteLogicTests {
    static func testReadingNoteStoreUnavailableDatabase() throws {
        let store = ReadingNoteStore(databaseURL: nil)
        let note = ReadingNote(
            id: "note-1",
            documentID: "doc-1",
            documentTitle: "Book",
            documentKind: "pdf",
            quote: "A useful passage",
            markdown: "",
            locator: ReadingNote.Locator(pdfFragments: nil, webAnchor: nil),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        try expectEqual(store.load(documentID: "doc-1").count, 0, "unavailable note store should load no notes")
        try expect(!store.upsert(note), "unavailable note store should reject saves")
        try expect(!store.delete(id: "note-1"), "unavailable note store should reject deletes")
    }

    static func testReadingNoteStoreRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeafReaderTests.ReadingNoteStore.\(UUID().uuidString)", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("notes.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ReadingNoteStore(databaseURL: databaseURL)
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        var note = ReadingNote(
            id: "note-1",
            documentID: "doc-1",
            documentTitle: "Book",
            documentKind: "pdf",
            quote: "A useful passage",
            markdown: "> A useful passage\n\n## Notes\n\nFirst thought\n",
            locator: ReadingNote.Locator(
                pdfFragments: [
                    ReadingNote.PDFFragment(
                        pageIndex: 3,
                        bounds: StoredPDFWordRect(CGRect(x: 10, y: 20, width: 30, height: 40))
                    )
                ],
                webAnchor: nil
            ),
            createdAt: createdAt,
            updatedAt: createdAt
        )

        try expect(store.upsert(note), "reading note should save")
        var loaded = store.load(documentID: "doc-1")
        try expectEqual(loaded.count, 1, "reading note should load by document")
        try expectEqual(loaded[0].id, "note-1", "loaded note should preserve id")
        try expectEqual(loaded[0].locator.pdfFragments?.first?.pageIndex, 3, "loaded note should preserve PDF locator")
        try expect(!loaded[0].isFavorite, "new reading note should default to not favorited")
        try expectEqual(
            loaded[0].locator.pdfFragments?.first?.bounds,
            StoredPDFWordRect(CGRect(x: 10, y: 20, width: 30, height: 40)),
            "loaded note should preserve PDF bounds"
        )

        note.markdown = "Updated\n"
        note.updatedAt = createdAt.addingTimeInterval(60)
        note.isFavorite = true
        try expect(store.upsert(note), "reading note should update")
        loaded = store.load(documentID: "doc-1")
        try expectEqual(loaded.count, 1, "upsert should replace the existing note")
        try expectEqual(loaded[0].markdown, "Updated\n", "updated note should preserve markdown")
        try expect(loaded[0].isFavorite, "updated note should preserve favorite state")
        try expect(store.containsNotes(documentID: "doc-1"), "note presence lookup should find durable records")

        let invalidReplacement = ReadingNote(
            id: note.id,
            documentID: note.documentID,
            documentTitle: note.documentTitle,
            documentKind: "epub",
            quote: note.quote,
            markdown: "Must not replace",
            locator: ReadingNote.Locator(
                pdfFragments: nil,
                webAnchor: ReadingNote.WebAnchor(
                    selectedText: "selection",
                    context: "context",
                    occurrenceIndex: 0,
                    scrollProgress: .nan
                )
            ),
            createdAt: note.createdAt,
            updatedAt: note.updatedAt
        )
        try expect(!store.upsert(invalidReplacement), "invalid required locator JSON should reject the replacement")
        loaded = store.load(documentID: "doc-1")
        try expectEqual(loaded.first?.markdown, "Updated\n", "failed locator encoding must preserve the existing note")

        try expect(store.delete(id: "note-1"), "reading note should delete")
        try expectEqual(store.load(documentID: "doc-1").count, 0, "deleted note should no longer load")
    }

    static func testReadingNoteExporterFallbackQuote() throws {
        let note = ReadingNote(
            id: "note-1",
            documentID: "doc-1",
            documentTitle: "Book",
            documentKind: "epub",
            quote: "Line one\nLine two",
            markdown: " \n",
            locator: ReadingNote.Locator(
                pdfFragments: nil,
                webAnchor: ReadingNote.WebAnchor(
                    selectedText: "Line one\nLine two",
                    context: "Before Line one Line two After",
                    occurrenceIndex: 0,
                    scrollProgress: 0.42
                )
            ),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let markdown = ReadingNoteExporter.markdown(
            documentTitle: "Book",
            notes: [note],
            exportedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        try expect(markdown.contains("# Book - "), "export should include document title")
        try expect(markdown.contains("：1"), "export should include note count")
        try expect(markdown.contains("> Line one\n> Line two"), "empty note body should fall back to quoted selection")
    }

    static func testReadingNoteExporterHTMLAndScope() throws {
        var favorite = ReadingNote(
            id: "note-favorite",
            documentID: "doc-1",
            documentTitle: "Book",
            documentKind: "pdf",
            quote: "Quoted",
            markdown: "## 解析\n\n> Quote & context\n\n- point\n\n![Image](file:///tmp/Reading%20Note.png)",
            locator: ReadingNote.Locator(
                pdfFragments: [ReadingNote.PDFFragment(pageIndex: 2, bounds: StoredPDFWordRect(.zero))],
                webAnchor: nil
            ),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        favorite.isFavorite = true
        let regular = ReadingNote(
            id: "note-regular",
            documentID: "doc-1",
            documentTitle: "Book",
            documentKind: "pdf",
            quote: "Regular",
            markdown: "Regular body",
            locator: ReadingNote.Locator(pdfFragments: nil, webAnchor: nil),
            createdAt: Date(timeIntervalSince1970: 1_700_000_010),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_010)
        )

        try expectEqual(
            ReadingNoteExporter.Scope.favorites.filter([favorite, regular]).map(\.id),
            ["note-favorite"],
            "favorite export scope should include only favorite notes"
        )

        let html = ReadingNoteExporter.html(
            documentTitle: "Book & Notes",
            notes: [favorite],
            exportedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        try expect(html.contains("<title>Book &amp; Notes</title>"), "HTML export should escape document title")
        try expect(html.contains("<h2>解析</h2>"), "HTML export should render markdown headings")
        try expect(html.contains("<blockquote>Quote &amp; context</blockquote>"), "HTML export should render and escape blockquotes")
        try expect(html.contains("<li>point</li>"), "HTML export should render list items")
        try expect(html.contains("<img src=\"file:///tmp/Reading%20Note.png\""), "HTML export should preserve image URLs")
    }

    static func testReadingNoteDisplayTitleUsesFirstMarkdownLine() throws {
        let note = ReadingNote(
            id: "note-1",
            documentID: "doc-1",
            documentTitle: "Book",
            documentKind: "pdf",
            quote: "Fallback quote",
            markdown: "\n> First note line\n\n## Notes\n\nBody",
            locator: ReadingNote.Locator(pdfFragments: nil, webAnchor: nil),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try expectEqual(note.displayTitle, "First note line", "reading note title should use first markdown line")

        var fallback = note
        fallback.markdown = " \n"
        try expectEqual(fallback.displayTitle, "Fallback quote", "empty markdown title should fall back to quote")
    }

    static func testReadingNoteListPresenterRows() throws {
        let newer = ReadingNote(
            id: "note-new",
            documentID: "doc-1",
            documentTitle: "Book",
            documentKind: "web",
            quote: "Fallback",
            markdown: "# Web note title",
            locator: ReadingNote.Locator(
                pdfFragments: nil,
                webAnchor: ReadingNote.WebAnchor(
                    selectedText: "Fallback",
                    context: "Before Fallback After",
                    occurrenceIndex: 0,
                    scrollProgress: 0.5
                )
            ),
            createdAt: Date(timeIntervalSince1970: 200),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let older = ReadingNote(
            id: "note-old",
            documentID: "doc-1",
            documentTitle: "Book",
            documentKind: "pdf",
            quote: "PDF fallback",
            markdown: "> PDF note title",
            locator: ReadingNote.Locator(
                pdfFragments: [
                    ReadingNote.PDFFragment(
                        pageIndex: 6,
                        bounds: StoredPDFWordRect(CGRect(x: 0, y: 0, width: 10, height: 10))
                    )
                ],
                webAnchor: nil
            ),
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        let rows = ReadingNoteListPresenter.rows(for: [newer, older])
        try expectEqual(rows.map(\.id), ["note-old", "note-new"], "reading note rows should sort by creation time")
        try expect(!rows[0].isFavorite, "row should expose favorite state")
        try expectEqual(rows[0].locationText, AppText.localized("第 7 页", "p. 7"), "PDF row should show page location")
        try expectEqual(rows[0].titleText, "PDF note title", "PDF row should use display title")
        try expectEqual(rows[1].locationText, AppText.localized("网页位置", "Web location"), "web row should show web location")
        try expectEqual(rows[1].titleText, "Web note title", "web row should use display title")

        var favoritedNewer = newer
        favoritedNewer.isFavorite = true
        let favoritedRows = ReadingNoteListPresenter.rows(for: [favoritedNewer, older])
        try expectEqual(favoritedRows.map(\.id), ["note-new", "note-old"], "favorite notes should be pinned before older notes")
        try expect(favoritedRows[0].isFavorite, "favorite row should expose favorite state")

        let titleMatches = ReadingNoteListPresenter.rows(for: [favoritedNewer, older], query: "web note")
        try expectEqual(titleMatches.map(\.id), ["note-new"], "reading note search should match title text")
        let quoteMatches = ReadingNoteListPresenter.rows(for: [newer, older], query: "pdf fallback")
        try expectEqual(quoteMatches.map(\.id), ["note-old"], "reading note search should match quote text")
        let locationMatches = ReadingNoteListPresenter.rows(for: [newer, older], query: "第 7")
        try expectEqual(locationMatches.map(\.id), ["note-old"], "reading note search should match location text")
    }

    static func testReadingNoteQuoteSoftLineBreaks() throws {
        let input = """
        A beginning is the time for taking
        the most delicate care that the balances
        are correct.

        - first item
        - second item

        hyphen-
        ated word
        """

        let normalized = ReadingNoteTextPolicy.normalizeQuote(input)
        try expectEqual(
            normalized,
            """
            A beginning is the time for taking the most delicate care that the balances are correct.

            - first item
            - second item

            hyphenated word
            """,
            "reading note quote should merge layout line breaks while preserving paragraph and list breaks"
        )
    }

    static func testReadingNotePDFLineGapsPreserveParagraphBreaks() throws {
        let lines = [
            ReadingNoteTextPolicy.PDFLine(text: "First visual line", pageIndex: 0, bounds: CGRect(x: 10, y: 300, width: 300, height: 20)),
            ReadingNoteTextPolicy.PDFLine(text: "second visual line", pageIndex: 0, bounds: CGRect(x: 10, y: 276, width: 300, height: 20)),
            ReadingNoteTextPolicy.PDFLine(text: "New paragraph line", pageIndex: 0, bounds: CGRect(x: 10, y: 220, width: 300, height: 20))
        ]
        try expectEqual(
            ReadingNoteTextPolicy.normalizePDFLines(lines),
            "First visual line second visual line\n\nNew paragraph line",
            "large PDF line gaps should preserve paragraph breaks"
        )
    }

    static func testReadingNoteSlashCommandGroups() throws {
        try expectEqual(
            ReadingNoteSlashCommand.blockCommands,
            [.text, .heading1, .heading2, .heading3, .heading4, .bulletedList, .numberedList, .template],
            "slash command menu should expose basic blocks in a stable order"
        )
        try expectEqual(
            ReadingNoteSlashCommand.aiCommands,
            [.aiContinue],
            "slash command menu should expose AI commands in a stable order"
        )
        try expectEqual(
            ReadingNoteSlashCommand.menuCommandGroups(isLineCommand: true).first,
            ReadingNoteSlashCommand.aiCommands,
            "slash command menu should put AI completion commands first"
        )
        try expectEqual(ReadingNoteSlashCommand.heading2.marker, "## ", "heading command should map to markdown marker")
        try expectEqual(ReadingNoteSlashCommand.template.marker, "模板", "template command should show a readable marker")
        try expect(ReadingNoteSlashCommand.aiContinue.isAICommand, "AI completion command should be marked as AI")
        try expect(!ReadingNoteSlashCommand.bulletedList.isAICommand, "block command should not be marked as AI")
    }

    static func testReadingNoteTemplates() throws {
        let quote = "The door stood ajar."
        let markdown = ReadingNoteTemplate.reading.markdown(quote: quote)
        try expect(
            markdown.contains("## \(AppText.localized("原文", "Original"))"),
            "reading template should include original text section"
        )
        try expect(markdown.contains("> The door stood ajar."), "reading template should preserve the selected quote")
        try expect(
            markdown.contains("## \(AppText.localized("核心思想", "Core Idea"))"),
            "reading template should include core idea section"
        )

        let defaultMarkdown = ReadingNoteMarkdown.defaultBody(quote: quote)
        try expect(
            ReadingNoteTemplateInsertionPolicy.shouldReplaceExistingMarkdown(
                currentMarkdown: defaultMarkdown,
                defaultMarkdown: defaultMarkdown
            ),
            "template should replace the untouched default reading note body"
        )
        try expect(
            !ReadingNoteTemplateInsertionPolicy.shouldReplaceExistingMarkdown(
                currentMarkdown: "\(defaultMarkdown)\n用户补充",
                defaultMarkdown: defaultMarkdown
            ),
            "template should not replace existing user content"
        )
        try expectEqual(
            ReadingNoteTemplateInsertionPolicy.spacerBeforeInsertion(existingText: "已有内容"),
            "\n\n",
            "template insertion should separate existing text with a paragraph gap"
        )
        try expectEqual(
            ReadingNoteTemplateInsertionPolicy.spacerBeforeInsertion(existingText: "已有内容\n"),
            "\n",
            "template insertion should keep exactly one blank line after a single newline"
        )
    }

    static func testReadingNoteSlashRangePolicy() throws {
        let lineTrigger = ReadingNoteSlashRangePolicy.trigger(
            text: "first\n/\nthird",
            selection: NSRange(location: 7, length: 0)
        )
        try expectEqual(lineTrigger?.triggerRange, NSRange(location: 6, length: 1), "slash trigger range should point at slash")
        try expectEqual(lineTrigger?.lineRange, NSRange(location: 6, length: 2), "slash line range should include the newline")
        try expect(lineTrigger?.isLineCommand == true, "single slash line should be treated as a line command")

        let inlineTrigger = ReadingNoteSlashRangePolicy.trigger(
            text: "ask /",
            selection: NSRange(location: 5, length: 0)
        )
        try expect(inlineTrigger?.isLineCommand == false, "inline slash should not be treated as a line command")
        try expect(
            ReadingNoteSlashRangePolicy.trigger(text: "plain", selection: NSRange(location: 5, length: 0)) == nil,
            "non-slash cursor should not trigger slash command"
        )
    }

    static func testReadingNoteAIMarkdownBodyStripsFence() throws {
        try expectEqual(
            ReadingNoteAITextPolicy.markdownBody(from: "```markdown\n# Title\n\nBody\n```"),
            "# Title\n\nBody",
            "AI markdown replacement should strip a wrapping fenced block"
        )
        try expectEqual(
            ReadingNoteAITextPolicy.markdownBody(from: "\nPlain text\n"),
            "Plain text",
            "AI markdown replacement should trim plain text"
        )
    }

    static func testReadingNoteAIErrorTextUsesSharedClassifier() throws {
        let rateLimit = NSError(domain: "openai", code: 429, userInfo: [
            NSLocalizedDescriptionKey: "OpenAI HTTP 429: rate_limit_exceeded"
        ])
        try expect(
            ReadingNoteAITextPolicy.userFacingError(rateLimit).contains("请求太频繁"),
            "reading-note AI errors should use the shared request failure classifier"
        )

        try expect(
            ReadingNoteAITextPolicy.emptyOutputMessage().contains("没有返回内容"),
            "empty AI responses should have a specific recovery message"
        )
    }

    static func testReadingNoteAIMarkdownImageProtector() throws {
        let markdown = """
        第一段
        ![Chart](file:///tmp/chart.png)
        第二段
        ![Photo](file:///tmp/photo.png)
        """
        let protected = ReadingNoteAIMarkdownImageProtector.protect(markdown)
        try expectEqual(
            protected.markdown,
            "第一段\n[[LEAF_IMAGE_1]]\n第二段\n[[LEAF_IMAGE_2]]",
            "image protector should replace image markdown lines with stable placeholders"
        )
        try expectEqual(protected.placeholders.count, 2, "image protector should track every protected image")

        let restored = ReadingNoteAIMarkdownImageProtector.restore(
            "整理后\n[[LEAF_IMAGE_2]]\n[[LEAF_IMAGE_1]]",
            protected: protected
        )
        try expect(restored.contains("![Chart](file:///tmp/chart.png)"), "image protector should restore the first image")
        try expect(restored.contains("![Photo](file:///tmp/photo.png)"), "image protector should restore the second image")

        let missingRestored = ReadingNoteAIMarkdownImageProtector.restore("AI 删除了占位符", protected: protected)
        try expect(missingRestored.contains("![Chart](file:///tmp/chart.png)"), "image protector should append missing images instead of dropping them")
        try expect(missingRestored.contains("![Photo](file:///tmp/photo.png)"), "image protector should append all missing images")
    }

}
