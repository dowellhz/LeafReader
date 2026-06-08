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

    static func testReadingNoteMarkdownRenderRangePolicy() throws {
        let text = "**加粗**\n下一行"
        try expectEqual(
            ReadingNoteMarkdownRenderRangePolicy.completedLineRangeBeforeCursor(
                text: text,
                selection: NSRange(location: 7, length: 0)
            ),
            NSRange(location: 0, length: 7),
            "completed markdown line policy should target the line before a newline cursor"
        )

        let pastedText = "第一段\n\n- pasted\nline\n\n尾段"
        try expectEqual(
            ReadingNoteMarkdownRenderRangePolicy.pastedParagraphRange(
                text: pastedText,
                insertedRange: NSRange(location: 5, length: 13)
            ),
            NSRange(location: 5, length: 14),
            "pasted markdown policy should expand to the pasted paragraph"
        )
    }

    static func testMarkdownBlockParserParsesBlocks() throws {
        let blocks = MarkdownBlockParser.parse(
            "# 标题\n\n- item\n- [x] done\n\n**翻译**\n\n译文",
            baseFontSize: 17
        )
        try expectEqual(blocks.map(\.type), [.heading1, .paragraph, .bullet, .checklist, .heading3, .paragraph], "block parser should classify headings, lists, and compact section headings")
        try expectEqual(blocks[0].display, "标题", "block parser should remove heading markers")
        try expectEqual(blocks[2].display, "• item", "block parser should normalize bullet markers")
        try expectEqual(blocks[3].display, "☑ done", "block parser should normalize checklist markers")
    }

    static func testMarkdownInlineParserAppliesStyles() throws {
        let rendered = NSMutableAttributedString(string: "**bold** *italic* `code`")
        MarkdownInlineParser.applyInlineMarkdown(to: rendered, baseFontSize: 17)
        try expectEqual(rendered.string, "bold italic code", "inline parser should remove markdown delimiters")
        try expect(fontTraits(in: rendered, text: "bold").contains(.bold), "inline parser should apply bold font")
        try expect(fontTraits(in: rendered, text: "italic").contains(.italic), "inline parser should apply italic font")
        try expect(fontTraits(in: rendered, text: "code").contains(.monoSpace), "inline parser should apply monospace font")
    }

    static func testReadingNoteEditingShortcutsAcceptControlCopyPaste() throws {
        try expectEqual(
            ReadingNoteEditingShortcut.shortcut(for: keyEvent(key: "c", modifiers: [.control])),
            .copy,
            "Control-C should copy in reading note editor"
        )
        try expectEqual(
            ReadingNoteEditingShortcut.shortcut(for: keyEvent(key: "v", modifiers: [.control])),
            .paste,
            "Control-V should paste in reading note editor"
        )
        try expectEqual(
            ReadingNoteEditingShortcut.shortcut(for: keyEvent(key: "c", modifiers: [.command])),
            .copy,
            "Command-C should still copy in reading note editor"
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

    static func testReadingNoteLinePrefixPolicy() throws {
        let replacement = ReadingNoteLinePrefixPolicy.replacement(
            text: "alpha\nbeta\n",
            selection: NSRange(location: 0, length: 10),
            displayPrefix: "• "
        )
        try expectEqual(replacement?.range, NSRange(location: 0, length: 11), "line prefix replacement should cover selected paragraphs")
        try expectEqual(replacement?.text, "• alpha\n• beta\n", "line prefix replacement should prefix non-empty selected lines")
        try expectEqual(replacement?.selection, NSRange(location: 0, length: 14), "line prefix replacement should expand selection")

        let inserted = ReadingNoteLinePrefixPolicy.replacement(
            text: "alpha",
            selection: NSRange(location: 5, length: 0),
            displayPrefix: "☐ "
        )
        try expectEqual(inserted?.range, NSRange(location: 5, length: 0), "empty selection should insert at cursor")
        try expectEqual(inserted?.text, "\n☐ ", "empty selection should start a new prefixed line when needed")
    }

    static func testReadingNoteInlineStylePolicyTogglesTrait() throws {
        let baseFont = NSFont.systemFont(ofSize: 17)
        let attributed = NSAttributedString(string: "Dune", attributes: [.font: baseFont])
        let bold = ReadingNoteInlineStylePolicy.toggled(
            attributed: attributed,
            trait: .boldFontMask,
            defaultFont: baseFont
        )
        try expect(
            ReadingNoteInlineStylePolicy.containsTrait(bold, trait: .boldFontMask),
            "inline style policy should add a missing trait"
        )

        let plain = ReadingNoteInlineStylePolicy.toggled(
            attributed: bold,
            trait: .boldFontMask,
            defaultFont: baseFont
        )
        try expect(
            !ReadingNoteInlineStylePolicy.containsTrait(plain, trait: .boldFontMask),
            "inline style policy should remove an existing trait"
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

    static func testReadingNoteMarkdownRoundTripPreservesInlineStylesInLists() throws {
        let markdown = """
        - **Fremen**: 沙漠原住民
        - *Landstraad*: 各大家族议会
        1. **CHOAM**: 星际贸易组织
        - [ ] **Atreides**: 主角家族
        """
        let rendered = MarkdownRenderer.render(markdown, textColor: .black)
        let serialized = ReadingNoteMarkdownSerializer.markdown(from: rendered)
        try expect(serialized.contains("- **Fremen**: 沙漠原住民"), "bullet line should preserve inline bold")
        try expect(serialized.contains("- *Landstraad*: 各大家族议会"), "bullet line should preserve inline italic")
        try expect(serialized.contains("1. **CHOAM**: 星际贸易组织"), "numbered line should preserve inline bold")
        try expect(serialized.contains("- [ ] **Atreides**: 主角家族"), "checklist line should preserve inline bold")
    }

    static func testReadingNoteDocumentCodecRoundTrip() throws {
        let document = ReadingNoteDocument(markdown: """
        ## 解析

        - **Dune**: 沙丘
        """)
        let projection = ReadingNoteDocumentCodec.editorProjection(
            from: document,
            fontSize: 17,
            textColor: .black
        )
        let decoded = ReadingNoteDocumentCodec.document(fromEditorProjection: projection)
        try expect(decoded.markdown.contains("## 解析"), "document codec should preserve heading semantics")
        try expect(decoded.markdown.contains("- **Dune**: 沙丘"), "document codec should preserve list inline styles")
    }

    static func testReadingNoteDocumentAppendsAISection() throws {
        let document = ReadingNoteDocument(markdown: "已有内容\n")
        let appended = document.appendingAISection(title: "翻译", body: "译文")
        try expectEqual(
            appended.markdown,
            "已有内容\n\n### 翻译\n\n译文\n",
            "document operation should append an AI section with stable spacing"
        )
        let headerOnly = document.appendingAISectionHeader(title: "总结")
        try expectEqual(
            headerOnly.markdown,
            "已有内容\n\n### 总结\n\n",
            "document operation should append an AI section header for placeholders"
        )
    }

    static func testReadingNoteDocumentImageMarkdown() throws {
        let url = URL(fileURLWithPath: "/tmp/ChatGPT Image 2026 05 30.png")
        try expectEqual(
            ReadingNoteDocument.imageMarkdown(url: url, title: "ChatGPT [Image]"),
            "![ChatGPT Image](file:///tmp/ChatGPT%20Image%202026%2005%2030.png)",
            "document operation should create stable image markdown with a file URL"
        )
    }

    static func testReadingNoteImageMarkdownRoundTripWithSpacedFilePath() throws {
        let imageURL = try makeTemporaryReadingNoteImageURL(fileName: "ChatGPT Image 2026 05 30.png")
        defer { try? FileManager.default.removeItem(at: imageURL.deletingLastPathComponent()) }

        let legacyRawPathMarkdown = "![ChatGPT Image](\(imageURL.path))"
        let renderedLegacy = MarkdownRenderer.render(legacyRawPathMarkdown, textColor: .black)
        try expect(
            renderedLegacy.containsAttachments,
            "legacy image markdown with a raw absolute path should render as an attachment"
        )

        let serialized = ReadingNoteMarkdownSerializer.markdown(from: renderedLegacy)
        try expect(
            serialized.contains(imageURL.absoluteString),
            "serialized image markdown should persist a file URL so spaced paths reopen reliably"
        )

        let renderedSerialized = MarkdownRenderer.render(serialized, textColor: .black)
        try expect(
            renderedSerialized.containsAttachments,
            "serialized image markdown should reopen as an attachment"
        )
    }

    static func testReadingNoteAssetStoreImportsImageToManagedDirectory() throws {
        let sourceURL = try makeTemporaryReadingNoteImageURL(fileName: "Original Image.png")
        let assetDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeafReaderTests.ReadingNoteAssets.\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: assetDirectory)
        }

        let importedURL = try ReadingNoteAssetStore.importImage(from: sourceURL, directoryURL: assetDirectory)
        try expect(importedURL.deletingLastPathComponent() == assetDirectory, "imported image should live in the managed asset directory")
        try expect(importedURL != sourceURL, "imported image should not reference the original file")
        try expectEqual(importedURL.pathExtension, "png", "imported image should preserve the source extension")
        try expect(FileManager.default.fileExists(atPath: importedURL.path), "imported image file should exist")
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
        try expect(
            !ReadingNoteAIInsertionMode.replaceRange(NSRange(location: 0, length: 0), renderMarkdown: true).usesPlaceholder,
            "range insertion should not mark placeholder usage"
        )
    }

    private static func makeTemporaryReadingNoteImageURL(fileName: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeafReaderTests.ReadingNoteImage.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName)
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "LeafReaderTests", code: 1)
        }
        try png.write(to: url)
        return url
    }

    private static func fontTraits(in attributed: NSAttributedString, text: String) -> NSFontDescriptor.SymbolicTraits {
        let range = (attributed.string as NSString).range(of: text)
        guard range.location != NSNotFound,
              let font = attributed.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont else {
            return []
        }
        return font.fontDescriptor.symbolicTraits
    }

    private static func keyEvent(key: String, modifiers: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: key,
            charactersIgnoringModifiers: key,
            isARepeat: false,
            keyCode: 0
        )!
    }
}

private extension NSAttributedString {
    var containsAttachments: Bool {
        var found = false
        enumerateAttribute(.attachment, in: NSRange(location: 0, length: length)) { value, _, stop in
            if value is NSTextAttachment {
                found = true
                stop.pointee = true
            }
        }
        return found
    }
}
