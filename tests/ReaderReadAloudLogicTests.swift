import Foundation
import CoreGraphics

func testPDFReadAloudChromeFilterLearnsRepeatedEdgeLines() throws {
    let pageBounds = CGRect(x: 0, y: 0, width: 600, height: 800)
    let shortPageBounds = CGRect(x: 0, y: 0, width: 372, height: 484)
    let firstPageLines = [
        PDFReadAloudChromeFilter.Line(text: "Book Title", bounds: CGRect(x: 50, y: 760, width: 200, height: 12), pageBounds: pageBounds),
        PDFReadAloudChromeFilter.Line(text: "Real first page sentence.", bounds: CGRect(x: 50, y: 500, width: 300, height: 12), pageBounds: pageBounds),
        PDFReadAloudChromeFilter.Line(text: "1", bounds: CGRect(x: 300, y: 20, width: 20, height: 12), pageBounds: pageBounds)
    ]
    let secondPageLines = [
        PDFReadAloudChromeFilter.Line(text: "Book Title", bounds: CGRect(x: 50, y: 760, width: 200, height: 12), pageBounds: pageBounds),
        PDFReadAloudChromeFilter.Line(text: "Real second page sentence.", bounds: CGRect(x: 50, y: 500, width: 300, height: 12), pageBounds: pageBounds),
        PDFReadAloudChromeFilter.Line(text: "Book Title", bounds: CGRect(x: 50, y: 400, width: 200, height: 12), pageBounds: pageBounds),
        PDFReadAloudChromeFilter.Line(text: "2", bounds: CGRect(x: 300, y: 20, width: 20, height: 12), pageBounds: pageBounds),
        PDFReadAloudChromeFilter.Line(text: "Chapter footer", bounds: CGRect(x: 330, y: 20, width: 120, height: 12), pageBounds: pageBounds)
    ]
    let state = PDFReadAloudChromeFilter.State()

    let first = PDFReadAloudChromeFilter.filteredText(lines: firstPageLines, state: state)
    try expect(first.contains("Book Title"), "first repeated-looking edge line should be kept until the filter learns it")
    try expect(!first.contains("\n1"), "page number edge lines should be filtered immediately")

    let second = PDFReadAloudChromeFilter.filteredText(lines: secondPageLines, state: state)
    try expect(!second.hasPrefix("Book Title"), "second repeated edge line should be filtered after learning")
    try expect(second.contains("Real second page sentence."), "body text should remain readable")
    try expect(second.contains("\nBook Title"), "same text in the page body should not be removed")
    try expect(!second.contains("\n2"), "later footer rows should be filtered immediately")
    try expect(!second.contains("Chapter footer"), "the whole detected footer row should be filtered")

    let shortPageState = PDFReadAloudChromeFilter.State()
    _ = PDFReadAloudChromeFilter.filteredText(
        lines: [
            PDFReadAloudChromeFilter.Line(text: "Free eBooks at Planet eBook.com", bounds: CGRect(x: 31, y: 62, width: 200, height: 12), pageBounds: shortPageBounds),
            PDFReadAloudChromeFilter.Line(text: "51", bounds: CGRect(x: 264, y: 62, width: 20, height: 12), pageBounds: shortPageBounds)
        ],
        state: shortPageState
    )
    let gatsbyLikePage = PDFReadAloudChromeFilter.filteredText(
        lines: [
            PDFReadAloudChromeFilter.Line(text: "Real Gatsby paragraph.", bounds: CGRect(x: 31, y: 250, width: 260, height: 12), pageBounds: shortPageBounds),
            PDFReadAloudChromeFilter.Line(text: "Free eBooks at Planet eBook.com", bounds: CGRect(x: 31, y: 62, width: 200, height: 12), pageBounds: shortPageBounds),
            PDFReadAloudChromeFilter.Line(text: "52", bounds: CGRect(x: 264, y: 62, width: 20, height: 12), pageBounds: shortPageBounds)
        ],
        state: shortPageState
    )
    try expect(gatsbyLikePage.contains("Real Gatsby paragraph."), "short-page body text should remain")
    try expect(!gatsbyLikePage.contains("Free eBooks"), "short-page repeated footer text should be filtered")
    try expect(!gatsbyLikePage.contains("52"), "short-page footer row should remove the page number too")

    let prideLikePage = PDFReadAloudChromeFilter.filteredText(
        lines: [
            PDFReadAloudChromeFilter.Line(text: "with you at the next ball.", bounds: CGRect(x: 72, y: 102, width: 220, height: 12), pageBounds: pageBounds),
            PDFReadAloudChromeFilter.Line(text: "Other body line.", bounds: CGRect(x: 72, y: 300, width: 220, height: 12), pageBounds: pageBounds)
        ],
        state: PDFReadAloudChromeFilter.State()
    )
    try expect(prideLikePage.contains("with you at the next ball."), "low body text should not be treated as footer chrome")
}

func testPaperStructureDetectorFindsStableSectionHeadings() throws {
    let headings = PaperStructureDetector.headings(from: [
        (
            pageIndex: 0,
            text: """
            A Reliable Paper Title
            Abstract
            This paper introduces a system and reports results.
            1 Introduction
            This is a long sentence that should not become a heading because it ends like normal prose.
            """
        ),
        (
            pageIndex: 2,
            text: """
            2 Related Work
            Prior work covers several areas.
            3.1 Experimental Setup
            We evaluate the model on two datasets.
            References
            """
        )
    ])

    try expectEqual(
        headings.map(\.title),
        ["Abstract", "1 Introduction", "2 Related Work", "3.1 Experimental Setup", "References"],
        "paper structure detector should keep stable paper section headings"
    )
    try expectEqual(headings.map(\.pageIndex), [0, 0, 2, 2, 2], "detected headings should keep source pages")
    try expectEqual(headings[3].level, 1, "numbered subsection should be nested")
}

func testPaperStructureDetectorRejectsWeakSectionSignals() throws {
    let headings = PaperStructureDetector.headings(from: [
        (
            pageIndex: 0,
            text: """
            Abstract
            This short note mentions prior work.
            """
        ),
        (
            pageIndex: 1,
            text: """
            References
            [1] Example citation.
            """
        )
    ])

    try expectEqual(headings.count, 0, "weak terminal headings should not replace the page-based PDF TOC")
}

func testCapturedPageScrollGuard() throws {
    try expect(shouldApplyCapturedPageScroll(capturedPageIndex: 2, documentPageCount: 5), "captured page in current document should be scrollable")
    try expect(!shouldApplyCapturedPageScroll(capturedPageIndex: -1, documentPageCount: 5), "negative captured page should be ignored")
    try expect(!shouldApplyCapturedPageScroll(capturedPageIndex: 5, documentPageCount: 5), "captured page outside current document should be ignored")
}

func testPDFBrightnessPolicy() throws {
    try expectEqual(PDFBrightnessPolicy.sliderMaximum, 0.6, "brightness slider maximum should stay explicit")
    try expectEqual(PDFBrightnessPolicy.sliderValue(forDimmingStrength: 0), 0.6, "no dimming should put brightness at the right edge")
    try expectEqual(PDFBrightnessPolicy.sliderValue(forDimmingStrength: 0.6), 0, "maximum dimming should put brightness at the left edge")
    try expectEqual(PDFBrightnessPolicy.dimmingStrength(forSliderValue: 0), 0.6, "left edge should be darkest")
    try expectEqual(PDFBrightnessPolicy.dimmingStrength(forSliderValue: 0.6), 0, "right edge should be brightest")
    try expectEqual(PDFBrightnessPolicy.sliderValue(forDimmingStrength: -1), 0.6, "dimming below range should clamp to brightest")
    try expectEqual(PDFBrightnessPolicy.sliderValue(forDimmingStrength: 2), 0, "dimming above range should clamp to darkest")
    try expectEqual(PDFBrightnessPolicy.dimmingStrength(forSliderValue: -1), 0.6, "slider below range should clamp to darkest")
    try expectEqual(PDFBrightnessPolicy.dimmingStrength(forSliderValue: 2), 0, "slider above range should clamp to brightest")
}

func testDebouncedTask() throws {
    let task = DebouncedTask(delay: 10)
    var value = 0
    task.schedule { value = 1 }
    task.schedule { value = 2 }
    task.flush()
    try expectEqual(value, 2, "flush should run only latest scheduled action")

    task.schedule { value = 3 }
    task.cancel()
    task.flush()
    try expectEqual(value, 2, "cancel should clear pending action")
}

func testSpeechTextPolicyNormalization() throws {
    let text = "well-\nknown  isn \u{2019} t rare\u{2026}"
    let normalized = SpeechTextPolicy.normalizedEnglishInput(text)

    try expectEqual(normalized, "wellknown isn't rare...", "TTS normalization should repair PDF line breaks and punctuation")
}

func testSpeechTextPolicyEnglishCandidate() throws {
    try expect(SpeechTextPolicy.isEnglishCandidate("A short English sentence."), "English text should be accepted")
    try expect(!SpeechTextPolicy.isEnglishCandidate("中文 mixed English"), "Chinese mixed text should be rejected for local English TTS")
    try expect(SpeechTextPolicy.isChineseCandidate("这是一段中文。"), "Chinese text should be accepted for Kokoro read aloud")
    try expect(SpeechTextPolicy.prefersChineseTTS("这是一段中文。"), "Chinese text should prefer Chinese TTS")
    try expect(
        !SpeechTextPolicy.prefersChineseTTS("A long English paragraph can contain a cached 中文 label without switching to Chinese TTS."),
        "mostly English text with a small Chinese label should still use English TTS"
    )
    try expect(
        !SpeechTextPolicy.prefersChineseReadAloudDocumentTTS("A long English paragraph can contain a cached 中文 label without switching to Chinese TTS."),
        "read-aloud document probing should ignore a few Chinese characters in mostly English text"
    )
    try expect(
        SpeechTextPolicy.prefersChineseReadAloudDocumentTTS(String(repeating: "这是一段中文内容。", count: 8)),
        "read-aloud document probing should detect a substantial Chinese passage"
    )
    try expect(SpeechTextPolicy.isLocalTTSCandidate("这是一段中文。"), "Chinese text should be accepted for local read aloud")
    try expect(!SpeechTextPolicy.isEnglishCandidate("12345"), "text without letters should be rejected")
}

func testSpeechTextPolicySegments() throws {
    let shortText = "One short sentence. Another short sentence."
    try expectEqual(
        SpeechTextPolicy.readAloudSegments(for: shortText),
        ["One short sentence. Another short sentence."],
        "short adjacent sentences should merge into a stable read-aloud segment"
    )

    let longText = Array(repeating: "word", count: 140).joined(separator: " ")
    let segments = SpeechTextPolicy.readAloudSegments(for: longText)
    try expect(segments.count > 1, "long text should split into multiple TTS segments")
    try expect(segments.allSatisfy { $0.count <= 520 }, "split TTS segments should stay within the max sentence length")

    let abbreviationText = "The careful witnesses described the room, hallway, window, clock, table, shelves, door, floor, ceiling, and Dr. Yueh calmly entered with a sealed note. Another sentence follows after the doctor arrives."
    let abbreviationSegments = SpeechTextPolicy.readAloudSegments(for: abbreviationText)
    try expect(abbreviationSegments.contains { $0.contains("Dr. Yueh") }, "TTS sentence splitting should keep title abbreviations with the following name")
    try expect(!abbreviationSegments.contains { $0.hasSuffix("Dr.") }, "TTS sentence splitting should not stop at title abbreviations")

    let initialsText = "The title page credits the author F. Scott Fitzgerald before the next line continues with enough words to make a separate speech segment. The reader should keep the initials attached."
    let initialsSegments = SpeechTextPolicy.readAloudSegments(for: initialsText)
    try expect(initialsSegments.contains { $0.contains("F. Scott Fitzgerald") }, "TTS sentence splitting should keep initials with following names")
    try expect(!initialsSegments.contains { $0.hasSuffix("F.") }, "TTS sentence splitting should not stop at initials")

    let quotedText = "He said, \"This quoted sentence contains enough words to make the speech segment flush only after the closing quotation mark arrives.\" Another narrator sentence follows with enough words to stand apart after the quoted line and keep this verification from merging back into the first segment."
    let quotedSegments = SpeechTextPolicy.readAloudSegments(for: quotedText)
    try expect(quotedSegments.first?.hasSuffix("\"") == true, "TTS sentence splitting should attach closing quotes to the sentence they close")
    try expect(!quotedSegments.dropFirst().contains { $0.hasPrefix("\"") }, "TTS sentence splitting should not start the next segment with a closing quote")

    let chineseSegments = SpeechTextPolicy.readAloudSegments(for: "第一句。第二句！第三句？")
    try expectEqual(chineseSegments, ["第一句。 第二句！ 第三句？"], "Chinese punctuation should split and merge into a stable read-aloud segment")

    let longChineseText = String(repeating: "这是一段没有空格的中文长句，需要按长度切分避免一次生成过久，", count: 12)
    let longChineseSegments = SpeechTextPolicy.readAloudSegments(for: longChineseText)
    try expect(longChineseSegments.count > 1, "long Chinese text should split into multiple TTS segments")
    try expect(longChineseSegments.allSatisfy { $0.count <= 120 }, "Chinese TTS segments should stay short for responsive Kokoro synthesis")
}

func testReadAloudTextMatcher() throws {
    let hyphenatedPage = "The well-\nknown explorer returned after winter."
    let hyphenatedRange = ReadAloudTextMatcher.range(of: "wellknown explorer", in: hyphenatedPage)
    try expect(hyphenatedRange != nil, "read-aloud matching should bridge PDF line-break hyphenation")

    let dropCapPage = "T he doorway opened quietly."
    let dropCapRange = ReadAloudTextMatcher.range(of: "The doorway", in: dropCapPage)
    try expect(dropCapRange != nil, "read-aloud matching should bridge separated drop-cap letters")

    let partialPage = "This opening sentence contains enough distinctive words for partial matching near the page edge."
    let partialQuery = "This opening sentence contains enough distinctive words for partial matching near the page edge and then continues on the next page."
    let partialRange = ReadAloudTextMatcher.range(of: partialQuery, in: partialPage)
    try expect(partialRange != nil, "read-aloud matching should fall back to a stable partial token range")
    let strictPartialRange = ReadAloudTextMatcher.range(of: partialQuery, in: partialPage, allowsPartialFallback: false)
    try expect(strictPartialRange == nil, "strict source matching should not accept partial read-aloud ranges")

    let repeatedPage = """
    They have tried to take the life of my son!
    A scraping metal racket vibrated through the tower, shook
    the parapet beneath his arms.
    They have tried to take the life of my son!
    The men were already boiling in from the field.
    """
    let repeatedQuery = """
    They have tried to take the life of my son!
    A scraping metal racket vibrated through the tower, shook
    the parapet beneath his arms.
    """
    guard let repeatedRange = ReadAloudTextMatcher.range(of: repeatedQuery, in: repeatedPage) else {
        throw TestFailure(description: "full repeated-page query should match")
    }
    try expectEqual(repeatedRange.location, 0, "full segment matching should not collapse to a later repeated sentence")

    let matcherPage = """
    They have tried to take the life of my son! A scraping metal racket vibrated through the tower, shook the parapet beneath his arms while the guards waited below.
    They have tried to take the life of my son! The men were already boiling in from the field when he reached the yellow domed room and carried their spacebags.
    """
    let matcherSource = """
    They have tried to take the life of my son! A scraping metal racket vibrated through the tower, shook the parapet beneath his arms while the guards waited below.
    They have tried to take the life of my son! The men were already boiling in from the field when he reached the yellow domed room and carried their spacebags.
    """
    let matchedSegments = PDFReadAloudSegmentMatcher.segments(from: [
        PDFReadAloudPageText(
            pageIndex: 160,
            speechSourceText: matcherSource,
            fullPageText: matcherPage
        )
    ])
    try expect(matchedSegments.count >= 2, "PDF read-aloud matcher should preserve sentence-level segments")
    try expectEqual(matchedSegments[0].range?.location, 0, "first repeated sentence should match its first occurrence")
    try expect(
        (matchedSegments[1].range?.location ?? 0) > (matchedSegments[0].range?.location ?? 0),
        "next PDF read-aloud segment should continue searching after the previous match"
    )
}

func testReadAloudManualAdvanceKeyPolicy() throws {
    try expectEqual(ReadAloudManualAdvanceKeyPolicy.action(for: "\\"), .next, "backslash should trigger manual TTS advance")
    try expectEqual(ReadAloudManualAdvanceKeyPolicy.action(for: "、"), .next, "Chinese enumeration comma should trigger manual TTS advance")
    try expectEqual(ReadAloudManualAdvanceKeyPolicy.action(for: "]"), .replayCurrent, "right bracket should replay current TTS segment")
    try expectEqual(ReadAloudManualAdvanceKeyPolicy.action(for: "】"), .replayCurrent, "Chinese right bracket should replay current TTS segment")
    try expectEqual(ReadAloudManualAdvanceKeyPolicy.action(for: "["), .replayPrevious, "left bracket should replay previous TTS segment")
    try expectEqual(ReadAloudManualAdvanceKeyPolicy.action(for: "【"), .replayPrevious, "Chinese left bracket should replay previous TTS segment")
    try expect(!ReadAloudManualAdvanceKeyPolicy.accepts("/"), "slash should not trigger manual TTS advance")
    try expect(!ReadAloudManualAdvanceKeyPolicy.accepts(nil), "nil key should not trigger manual TTS advance")
}

func testReadAloudPlaybackPhase() throws {
    try expect(!ReadAloudPlaybackPhase.idle.isActive, "idle read-aloud phase should not be active")
    try expect(ReadAloudPlaybackPhase.loading.isActive, "loading read-aloud phase should be active")
    try expect(ReadAloudPlaybackPhase.loading.isLoading, "loading read-aloud phase should report loading")
    try expect(ReadAloudPlaybackPhase.playing.isActive, "playing read-aloud phase should be active")
    try expect(ReadAloudPlaybackPhase.paused.isPaused, "paused read-aloud phase should report paused")
    try expect(!ReadAloudPlaybackPhase.paused.isLoading, "paused read-aloud phase should not report loading")
}

func testKokoroWorkerResponseReader() throws {
    var reader = KokoroWorkerResponseReader(requestID: "target")
    let payload = """
    not json
    {"id":"other","ok":true}
    {"id":"target","ok":false,"error":"bad input"}

    """
    let response = reader.append(Data(payload.utf8))

    try expectEqual(response, KokoroWorkerResponse(id: "target", ok: false, error: "bad input"), "reader should ignore bad JSON and wrong ids")
}

func testKokoroWorkerResponseReaderBuffersPartialLines() throws {
    var reader = KokoroWorkerResponseReader(requestID: "target")
    try expect(reader.append(Data(#"{"id":"target","#.utf8)) == nil, "partial worker responses should wait for a newline")
    var tail = Data(#""ok":true,"error":null}"#.utf8)
    tail.append(0x0A)
    let response = reader.append(tail)

    try expectEqual(response, KokoroWorkerResponse(id: "target", ok: true, error: nil), "reader should decode buffered partial JSON lines")
}
