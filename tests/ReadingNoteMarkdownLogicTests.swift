import Cocoa
import Foundation

extension ReadingNoteLogicTests {
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
        guard let event = NSEvent.keyEvent(
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
        ) else {
            preconditionFailure("could not create synthetic key event")
        }
        return event
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
