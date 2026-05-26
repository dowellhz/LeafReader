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
}
