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
        try expectEqual(
            loaded[0].locator.pdfFragments?.first?.bounds,
            StoredPDFWordRect(CGRect(x: 10, y: 20, width: 30, height: 40)),
            "loaded note should preserve PDF bounds"
        )

        note.markdown = "Updated\n"
        note.updatedAt = createdAt.addingTimeInterval(60)
        try expect(store.upsert(note), "reading note should update")
        loaded = store.load(documentID: "doc-1")
        try expectEqual(loaded.count, 1, "upsert should replace the existing note")
        try expectEqual(loaded[0].markdown, "Updated\n", "updated note should preserve markdown")

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
        try expectEqual(rows[0].locationText, AppText.localized("第 7 页", "p. 7"), "PDF row should show page location")
        try expectEqual(rows[0].titleText, "PDF note title", "PDF row should use display title")
        try expectEqual(rows[1].locationText, AppText.localized("网页位置", "Web location"), "web row should show web location")
        try expectEqual(rows[1].titleText, "Web note title", "web row should use display title")
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
            [.text, .heading1, .heading2, .heading3, .heading4, .bulletedList, .numberedList],
            "slash command menu should expose basic blocks in a stable order"
        )
        try expectEqual(
            ReadingNoteSlashCommand.aiCommands,
            [.aiContinue],
            "slash command menu should expose AI commands in a stable order"
        )
        try expectEqual(ReadingNoteSlashCommand.heading2.marker, "## ", "heading command should map to markdown marker")
        try expect(ReadingNoteSlashCommand.aiContinue.isAICommand, "AI completion command should be marked as AI")
        try expect(!ReadingNoteSlashCommand.bulletedList.isAICommand, "block command should not be marked as AI")
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

    static func testReadingNoteAIDocumentContext() throws {
        let note = String(repeating: "a", count: ReadingNoteAITextPolicy.noteContextLimit + 10)
        let context = ReadingNoteAITextPolicy.documentContext(
            selectedText: "selected",
            noteMarkdown: note,
            isChinese: false
        )
        try expect(context.contains("[Selected reading-note text]\nselected"), "AI context should include selected note text")
        try expect(
            context.contains(String(repeating: "a", count: ReadingNoteAITextPolicy.noteContextLimit)),
            "AI context should include truncated note markdown"
        )
        try expect(!context.contains(String(repeating: "a", count: ReadingNoteAITextPolicy.noteContextLimit + 1)), "AI context should clamp note markdown")
    }

    static func testReadingNoteMarkdownInputPolicyRendersInlineStyles() throws {
        try expect(
            ReadingNoteMarkdownInputPolicy.shouldRenderCompletedLine("**加粗**文字"),
            "completed note line should render bold markdown"
        )
        try expect(
            ReadingNoteMarkdownInputPolicy.shouldRenderCompletedLine("这是 __加粗__ 文字"),
            "completed note line should render underscore bold markdown"
        )
        try expect(
            ReadingNoteMarkdownInputPolicy.shouldRenderCompletedLine("*斜体*文字"),
            "completed note line should render italic markdown"
        )
        try expect(
            ReadingNoteMarkdownInputPolicy.shouldRenderCompletedLine("使用 `code`"),
            "completed note line should render inline code markdown"
        )
        try expect(
            ReadingNoteMarkdownInputPolicy.shouldRenderCompletedLine("* 列表"),
            "completed note line should still render star bullet markdown"
        )
        try expect(
            !ReadingNoteMarkdownInputPolicy.shouldRenderCompletedLine("普通文字"),
            "plain note line should not be re-rendered"
        )
        try expect(
            !ReadingNoteMarkdownInputPolicy.shouldRenderCompletedLine("2 * 3 = 6"),
            "plain arithmetic star should not trigger markdown rendering"
        )
        try expect(
            ReadingNoteMarkdownInputPolicy.shouldRenderPastedText("第一行\n**加粗**"),
            "pasted multiline markdown should trigger rendering"
        )
        try expect(
            !ReadingNoteMarkdownInputPolicy.shouldRenderPastedText("第一行\n第二行"),
            "pasted plain text should not trigger rendering"
        )
    }

    static func testReadingNoteTextReplacementPolicyRestoresSelection() throws {
        try expectEqual(
            ReadingNoteTextReplacementPolicy.selectionRange(
                replacing: NSRange(location: 2, length: 4),
                replacementLength: 1,
                textLengthAfterReplacement: 8,
                selection: .caretAfterReplacement
            ),
            NSRange(location: 3, length: 0),
            "replacement should place caret after inserted text by default"
        )
        try expectEqual(
            ReadingNoteTextReplacementPolicy.selectionRange(
                replacing: NSRange(location: 0, length: 5),
                replacementLength: 3,
                textLengthAfterReplacement: 10,
                selection: .adjustedOriginal(NSRange(location: 6, length: 0))
            ),
            NSRange(location: 4, length: 0),
            "replacement should adjust an existing cursor by the replacement delta"
        )
        try expectEqual(
            ReadingNoteTextReplacementPolicy.boundedRange(location: 20, length: 5, textLength: 12),
            NSRange(location: 12, length: 0),
            "selection restoration should clamp out-of-range selections"
        )
    }

    static func testReadingNoteMarkdownRoundTrip() throws {
        let markdown = """
        # 标题

        - 项目
        - [ ] 任务
        - [x] 完成

        **加粗** 和 *斜体* 与 `code`
        """
        let rendered = MarkdownRenderer.render(markdown, textColor: .black)
        let serialized = ReadingNoteMarkdownSerializer.markdown(from: rendered)
        try expect(serialized.contains("# 标题"), "round-trip should preserve heading")
        try expect(serialized.contains("- 项目"), "round-trip should preserve bullet list")
        try expect(serialized.contains("- [ ] 任务"), "round-trip should preserve unchecked task")
        try expect(serialized.contains("- [x] 完成"), "round-trip should preserve checked task")
        try expect(serialized.contains("**加粗** 和 *斜体* 与 `code`"), "round-trip should preserve inline styles")
    }

    static func testReadingNoteEditorStateRejectsStaleAIResults() throws {
        let state = ReadingNoteEditorState()
        let first = state.beginAIRequest()
        let second = state.beginAIRequest()
        try expect(!state.canApplyAIResult(first), "starting a newer AI request should stale the older request")
        try expect(state.canApplyAIResult(second), "latest AI request should be applicable")
        state.finishAIRequest(second)
        try expect(!state.canApplyAIResult(second), "finished AI request should no longer be applicable")

        let closing = state.beginAIRequest()
        state.isClosing = true
        try expect(!state.canApplyAIResult(closing), "closing note panel should reject pending AI results")
    }

    static func testReadingNoteAIInsertionModePlaceholderFlag() throws {
        try expect(ReadingNoteAIInsertionMode.replacePlaceholder(title: "解析").usesPlaceholder, "placeholder insertion should mark placeholder usage")
        try expect(!ReadingNoteAIInsertionMode.replaceSlashTrigger.usesPlaceholder, "slash insertion should not mark placeholder usage")
        try expect(
            !ReadingNoteAIInsertionMode.replaceSelection(NSRange(location: 0, length: 1), renderMarkdown: true).usesPlaceholder,
            "selection insertion should not mark placeholder usage"
        )
    }
}
