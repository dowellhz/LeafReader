import Foundation
import CoreGraphics

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw TestFailure(description: message)
    }
}

func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) throws {
    if lhs != rhs {
        throw TestFailure(description: "\(message). expected \(rhs), got \(lhs)")
    }
}

private final class DebouncedTask {
    private let delay: TimeInterval
    private var workItem: DispatchWorkItem?
    private var pendingAction: (() -> Void)?

    init(delay: TimeInterval) {
        self.delay = delay
    }

    func schedule(_ action: @escaping () -> Void) {
        workItem?.cancel()
        pendingAction = action
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let action = self.pendingAction else { return }
            self.workItem = nil
            self.pendingAction = nil
            action()
        }
        self.workItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func flush() {
        guard let action = pendingAction else { return }
        workItem?.cancel()
        workItem = nil
        pendingAction = nil
        action()
    }

    func cancel() {
        workItem?.cancel()
        workItem = nil
        pendingAction = nil
    }
}

private enum ScrollPageDirection: Equatable {
    case previous
    case next
}

private func pageDirectionAtEdge(deltaY: Double, isAtTop: Bool, isAtBottom: Bool) -> ScrollPageDirection? {
    if isAtTop, deltaY > 0 {
        return .previous
    }
    if isAtBottom, deltaY < 0 {
        return .next
    }
    return nil
}

private func shouldApplyCapturedPageScroll(capturedPageIndex: Int, documentPageCount: Int) -> Bool {
    capturedPageIndex >= 0 && capturedPageIndex < documentPageCount
}

private func testEmbeddingWarmupIdlePolicy() throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    try expect(
        !EmbeddingWarmupPolicy.isReaderIdle(
            lastInteractionAt: now.addingTimeInterval(-(EmbeddingWarmupPolicy.idleThreshold - 0.1)),
            now: now
        ),
        "embedding warmup should wait until the reader has been idle long enough"
    )
    try expect(
        EmbeddingWarmupPolicy.isReaderIdle(
            lastInteractionAt: now.addingTimeInterval(-EmbeddingWarmupPolicy.idleThreshold),
            now: now
        ),
        "embedding warmup should start at the idle threshold"
    )
    try expectEqual(EmbeddingWarmupPolicy.cacheRestoreDelay, 5.0, "cache restore delay should remain explicit")
    try expectEqual(EmbeddingWarmupPolicy.warmupDelay, 18.0, "warmup delay should remain explicit")
}

private func testPageScrollDirection() throws {
    try expectEqual(pageDirectionAtEdge(deltaY: 12, isAtTop: true, isAtBottom: false), .previous, "scrolling upward at page top should go previous")
    try expectEqual(pageDirectionAtEdge(deltaY: -12, isAtTop: false, isAtBottom: true), .next, "scrolling downward at page bottom should go next")
    try expect(pageDirectionAtEdge(deltaY: 12, isAtTop: false, isAtBottom: true) == nil, "scrolling upward at bottom should not go previous")
    try expect(pageDirectionAtEdge(deltaY: -12, isAtTop: true, isAtBottom: false) == nil, "scrolling downward at top should not go next")
}

private func testPDFPagingPolicy() throws {
    try expectEqual(PDFPagingPolicy.wheelEdgeScrollThreshold, 40, "wheel edge threshold should remain explicit")
    try expectEqual(PDFPagingPolicy.wheelPageTurnCooldown, 0.45, "wheel cooldown should prevent double page turns")
    try expectEqual(PDFPagingPolicy.trackpadEdgeSlop, 12, "trackpad edge slop should remain explicit")
    try expectEqual(PDFPagingPolicy.trackpadScrollerTopLimit, 0.001, "trackpad top scroller limit should avoid early turns")
    try expectEqual(PDFPagingPolicy.trackpadScrollerBottomLimit, 0.999, "trackpad bottom scroller limit should avoid early turns")
    try expectEqual(PDFPagingPolicy.trackpadPageTurnCooldown, 0.8, "trackpad cooldown should prevent double page turns")
    try expectEqual(
        PDFPagingPolicy.trackpadPageTurnThreshold(clipHeight: 800, documentHeight: 801),
        PDFPagingPolicy.trackpadShortPageTurnThreshold,
        "short pages should require a stronger trackpad gesture"
    )
    try expectEqual(
        PDFPagingPolicy.trackpadPageTurnThreshold(clipHeight: 800, documentHeight: 1200),
        PDFPagingPolicy.trackpadLongPageTurnThreshold,
        "long pages should allow a lighter edge gesture"
    )
}

private func testReaderSessionPolicy() throws {
    try expectEqual(ReaderSessionPolicy.webProgressSaveInterval, 0.5, "web progress save interval should remain explicit")
    try expectEqual(ReaderSessionPolicy.lastPositionSaveDelay, 3.0, "last position should only save after a stable dwell")
    try expectEqual(ReaderSessionPolicy.initialRestoreDelay, 0.2, "initial restore delay should remain explicit")
    try expectEqual(ReaderSessionPolicy.pdfViewportAnchorTopInset, 24, "PDF viewport anchor inset should remain explicit")
    try expect(ReaderSessionPolicy.isRestorablePDFScale(0.1), "minimum PDF scale should restore")
    try expect(ReaderSessionPolicy.isRestorablePDFScale(8), "maximum PDF scale should restore")
    try expect(!ReaderSessionPolicy.isRestorablePDFScale(0.09), "too-small PDF scale should not restore")
    try expect(!ReaderSessionPolicy.isRestorablePDFScale(8.1), "too-large PDF scale should not restore")
}

private func testReaderSessionStorePDFAnchor() throws {
    let suiteName = "LeafReaderTests.ReaderSessionStorePDFAnchor.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        throw TestFailure(description: "could not create isolated defaults suite")
    }
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let store = ReaderSessionStore(fileMD5: "book", defaults: defaults)
    store.savePDFProgress(pageIndex: 4, scale: 1.25, anchorPoint: CGPoint(x: 12.5, y: 98.75))

    guard let progress = store.loadPDFProgress() else {
        throw TestFailure(description: "PDF progress should load after save")
    }
    try expectEqual(progress.pageIndex, 4, "PDF page index should round-trip")
    try expectEqual(progress.scale, 1.25, "PDF scale should round-trip")
    try expectEqual(progress.anchorPoint?.x, 12.5, "PDF anchor x should round-trip")
    try expectEqual(progress.anchorPoint?.y, 98.75, "PDF anchor y should round-trip")

    store.clearProgress()
    try expect(store.loadPDFProgress() == nil, "clearProgress should remove PDF page and anchor data")
}

private func testReaderSessionStoreFarthestProgress() throws {
    let suiteName = "LeafReaderTests.ReaderSessionStoreFarthestProgress.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        throw TestFailure(description: "could not create isolated defaults suite")
    }
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let store = ReaderSessionStore(fileMD5: "book", defaults: defaults)
    store.saveFarthestPDFProgress(pageIndex: 8, scale: 1.5, anchorPoint: CGPoint(x: 20, y: 40))
    store.saveFarthestPDFPageIndex(3)
    try expectEqual(store.loadFarthestPDFPageIndex(), 8, "farthest PDF page should not move backward")
    try expectEqual(store.loadFarthestPDFProgress()?.scale, 1.5, "farthest PDF scale should not be replaced by an earlier page")
    try expectEqual(store.loadFarthestPDFProgress()?.anchorPoint?.x, 20, "farthest PDF anchor should not be replaced by an earlier page")

    store.saveFarthestPDFProgress(pageIndex: 12, scale: 2.0, anchorPoint: CGPoint(x: 30, y: 60))
    try expectEqual(store.loadFarthestPDFPageIndex(), 12, "farthest PDF page should move forward")
    try expectEqual(store.loadFarthestPDFProgress()?.scale, 2.0, "farthest PDF scale should move with the farthest page")
    try expectEqual(store.loadFarthestPDFProgress()?.anchorPoint?.y, 60, "farthest PDF anchor should move with the farthest page")

    store.saveFarthestWebProgress(0.4, zoomPercent: 120)
    store.saveFarthestWebProgress(0.2, zoomPercent: 160)
    try expectEqual(store.loadFarthestWebProgress()?.scrollProgress, 0.4, "farthest web progress should not move backward")
    try expectEqual(store.loadFarthestWebProgress()?.zoomPercent, 120, "farthest web zoom should not be replaced by earlier progress")

    store.saveFarthestWebProgress(1.5, zoomPercent: 180)
    try expectEqual(store.loadFarthestWebProgress()?.scrollProgress, 1.0, "farthest web progress should clamp to one")
    try expectEqual(store.loadFarthestWebProgress()?.zoomPercent, 180, "farthest web zoom should move with farthest progress")

    store.clearProgress()
    try expect(store.loadFarthestPDFPageIndex() == nil, "clearProgress should remove farthest PDF page")
    try expect(store.loadFarthestWebProgress() == nil, "clearProgress should remove farthest web progress")
}

private func testReaderSessionStoreWebProgressBounds() throws {
    let suiteName = "LeafReaderTests.ReaderSessionStoreWebProgressBounds.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        throw TestFailure(description: "could not create isolated defaults suite")
    }
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let store = ReaderSessionStore(fileMD5: "book", defaults: defaults)
    try expect(store.loadWebProgress() == nil, "missing web progress should not load as zero")

    store.saveWebProgress(scrollProgress: 1.25, zoomPercent: 140)
    try expectEqual(store.loadWebProgress()?.scrollProgress, 1.0, "web progress should clamp high on save")
    try expectEqual(store.loadWebProgress()?.zoomPercent, 140, "web zoom should round-trip")

    store.saveWebProgress(scrollProgress: -0.5, zoomPercent: 40)
    try expectEqual(store.loadWebProgress()?.scrollProgress, 0.0, "web progress should clamp low on save")
    try expect(store.loadWebProgress()?.zoomPercent == nil, "invalid web zoom should not load")
}

private func testReaderProgressFormatter() throws {
    try expectEqual(ReaderProgressFormatter.pdfPageText(pageIndex: 0, pageCount: 10), "1  /  10", "PDF page text should be one-based")
    try expectEqual(ReaderProgressFormatter.pdfPageText(pageIndex: -4, pageCount: 10), "1  /  10", "PDF page text should clamp low page")
    try expectEqual(ReaderProgressFormatter.pdfPageText(pageIndex: 99, pageCount: 10), "10  /  10", "PDF page text should clamp high page")
    try expectEqual(ReaderProgressFormatter.pdfPageText(pageIndex: 0, pageCount: 0), "1  /  1", "PDF page text should handle empty counts")

    try expectEqual(ReaderProgressFormatter.pdfProgressPercent(pageIndex: 0, pageCount: 10), 10, "PDF progress should use the current one-based page")
    try expectEqual(ReaderProgressFormatter.pdfProgressPercent(pageIndex: 9, pageCount: 10), 100, "PDF progress should reach 100 on the last page")
    try expectEqual(ReaderProgressFormatter.pdfProgressPercent(pageIndex: -4, pageCount: 10), 10, "PDF progress should clamp low page")
    try expectEqual(ReaderProgressFormatter.pdfProgressPercent(pageIndex: 99, pageCount: 10), 100, "PDF progress should clamp high page")
    try expectEqual(ReaderProgressFormatter.pdfProgressPercent(pageIndex: 0, pageCount: 0), 0, "PDF progress should handle empty counts")

    try expectEqual(ReaderProgressFormatter.webProgressPercent(-0.2), 0, "web progress should clamp low")
    try expectEqual(ReaderProgressFormatter.webProgressPercent(0.126), 13, "web progress should round")
    try expectEqual(ReaderProgressFormatter.webProgressPercent(1.4), 100, "web progress should clamp high")
}

private func testReaderAIContextTextCleanup() throws {
    let stripped = ReaderAIContextBuilder.stripPDFPageChrome(
        from: "Book Title\n12\nReal content",
        previousText: "Book Title\nPrevious page",
        nextText: "Book Title\nNext page",
        title: "Book Title"
    )
    try expectEqual(stripped, "Real content", "PDF chrome lines should be stripped from page edges")
    try expect(ReaderAIContextBuilder.pdfTextAppearsToStartMidParagraph("and then the sentence continues"), "lowercase connector should look mid-paragraph")
    try expect(ReaderAIContextBuilder.pdfTextAppearsToEndMidParagraph("This sentence keeps going without punctuation"), "long unpunctuated line should look mid-paragraph")
    try expect(!ReaderAIContextBuilder.pdfTextAppearsToEndMidParagraph("This sentence is complete."), "terminal punctuation should end paragraph")
}

private func testReaderAIContextPolicy() throws {
    try expectEqual(ReaderAIContextPolicy.summaryContentLimit, 6000, "summary content limit should remain explicit")
    try expectEqual(ReaderAIContextPolicy.translationContentLimit, 9000, "translation content limit should remain explicit")
    try expectEqual(ReaderAIContextPolicy.questionContentLimit, 5000, "question content limit should remain explicit")
    try expectEqual(ReaderAIContextPolicy.combinedContextSuffixLimit, 6000, "combined context suffix limit should remain explicit")
    try expectEqual(ReaderAIContextPolicy.nearbyPageExcerptLimit, 1200, "nearby page excerpt limit should remain explicit")
    try expectEqual(ReaderAIContextPolicy.documentAgentCurrentPageLimit, 3500, "document agent current page limit should remain explicit")
    try expectEqual(ReaderAIContextPolicy.documentAgentNearbyTextLimit, 5000, "document agent nearby text limit should remain explicit")
    try expectEqual(ReaderAIContextPolicy.evidenceBubbleCount, 4, "evidence bubble count should remain explicit")
    try expectEqual(ReaderAIContextPolicy.evidenceBubbleTextLimit, 500, "evidence bubble text limit should remain explicit")
    try expectEqual(ReaderAIContextPolicy.prefix("abcdef", limit: 3), "abc", "prefix helper should clamp text")
    try expectEqual(ReaderAIContextPolicy.suffix("abcdef", limit: 3), "def", "suffix helper should clamp text")
}

private func testAIResponseTextFormatter() throws {
    try expectEqual(AIResponseTextFormatter.trimmed("  answer\n"), "answer", "formatter should trim text")
    try expect(!AIResponseTextFormatter.hasTrimmedText("   "), "blank text should not be meaningful")
    try expectEqual(AIResponseTextFormatter.indentedTranslationText("　　line one\n\nline two"), "line one\n\nline two", "translation text should trim model indentation")
    try expectEqual(
        AIResponseTextFormatter.partialTranslationText(["first", ""], currentIndex: 1, generatingText: "Generating"),
        "first\n\nGenerating",
        "partial translation should include completed chunks and generating text"
    )
    let longText = String(repeating: "a", count: AIResponseTextFormatter.translationChunkLimit + 20)
    try expectEqual(AIResponseTextFormatter.translationChunks(from: longText).count, 2, "long unparagraphized translations should split in two")
}

private func testAIConversationMarkdownExporter() throws {
    let markdown = AIConversationMarkdownExporter.markdown(
        title: "Dune",
        bubbles: [
            SavedAIConversationBubble(role: AppText.userRole, text: "Explain this.", collapsible: false, renderMarkdown: false, sourceLocation: nil),
            SavedAIConversationBubble(role: AppText.aiRole, text: "## Answer\n\nUse context.", collapsible: false, renderMarkdown: true, sourceLocation: nil),
            SavedAIConversationBubble(role: AppText.aiRole, text: "   ", collapsible: false, renderMarkdown: true, sourceLocation: nil)
        ],
        exportedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    try expect(markdown.contains("# Dune - "), "export should include document title")
    try expect(markdown.contains("- \(AppText.localized("气泡数", "Bubbles"))：3"), "export should include bubble count")
    try expect(markdown.contains("## \(AppText.localized("用户", "User"))\n\nExplain this."), "export should include user bubble")
    try expect(markdown.contains("## AI\n\n## Answer\n\nUse context."), "export should include AI markdown body unchanged")

    let html = AIConversationMarkdownExporter.html(
        title: "Dune & Notes",
        bubbles: [
            SavedAIConversationBubble(role: AppText.userRole, text: "Use <context>.", collapsible: false, renderMarkdown: false, sourceLocation: nil),
            SavedAIConversationBubble(role: AppText.aiRole, text: "## Answer\n\n- **原文** point", collapsible: false, renderMarkdown: true, sourceLocation: nil)
        ],
        exportedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    try expect(html.contains("<title>Dune &amp; Notes</title>"), "HTML export should escape the title")
    try expect(html.contains("Use &lt;context&gt;."), "HTML export should escape bubble text")
    try expect(html.contains("<h2>Answer</h2>"), "HTML export should render markdown headings")
    try expect(html.contains("<li><strong>原文</strong> point</li>"), "HTML export should render markdown lists and bold text")
}

private func testEmbeddingActionPolicy() throws {
    try expectEqual(EmbeddingActionPolicy.statusClearDelay, 1.5, "embedding status clear delay should remain explicit")
}

private func testReadingContextSnapshot() throws {
    let snapshot = ReadingContextSnapshot(
        title: "Book",
        documentKind: .pdf,
        locationLabel: " p. 2 ",
        visibleText: " visible ",
        nearbyText: " nearby ",
        selectedText: " selected ",
        selectedContext: " context "
    )
    try expectEqual(snapshot.currentContentTitle, "Book - p. 2", "content title should include trimmed location")
    try expectEqual(snapshot.readingText, "visible", "visible text should win over nearby text")
    try expectEqual(snapshot.focusedReadingText, "selected", "selected text should be preferred for focused AI actions")
    try expect(snapshot.contextText.contains("p. 2"), "context should include location")
    try expect(snapshot.contextText.contains("selected"), "context should include selection")
}

private func testReaderFocusedSelectionPriority() throws {
    var requestedContextTexts: [String] = []
    let explicit = ReaderFocusedSelection.resolve(
        explicitSelection: " selected ",
        readAloudSelection: " spoken ",
        contextProvider: { text in
            requestedContextTexts.append(text)
            return "\(text) context"
        }
    )
    try expectEqual(explicit?.origin, .explicitSelection, "explicit reader selection should win over read-aloud selection")
    try expectEqual(explicit?.text, "selected", "focused selection should trim explicit text")
    try expectEqual(explicit?.context, "selected context", "focused selection should use explicit context")
    try expectEqual(requestedContextTexts, ["selected"], "resolver should only request context for the winning explicit selection")

    let readAloud = ReaderFocusedSelection.resolve(
        explicitSelection: " ",
        readAloudSelection: " spoken ",
        contextProvider: { text in "\(text) context" }
    )
    try expectEqual(readAloud?.origin, .readAloudSegment, "read-aloud selection should be used when there is no explicit selection")
    try expectEqual(readAloud?.text, "spoken", "focused selection should trim read-aloud text")
    try expectEqual(
        ReaderAIContextResolver(explicitSelection: " ", readAloudSelection: " spoken ").preferredSelectionText,
        "spoken",
        "AI panel selection fallback should use read-aloud text when explicit selection is empty"
    )

    let snapshot = ReadingContextSnapshot(
        title: "Book",
        documentKind: .pdf,
        locationLabel: "Page 3",
        visibleText: "visible",
        nearbyText: "nearby",
        focusedSelection: readAloud
    )
    try expectEqual(snapshot.focusedReadingText, "spoken", "read-aloud text should drive focused AI actions")
    try expect(snapshot.contextText.contains("当前朗读内容") || snapshot.contextText.contains("Current read-aloud text"), "context should label read-aloud focused text")
}

private func testReaderAISourceMatcher() throws {
    let pdfBoundsSource = AIConversationSourceLocation(
        kind: .pdfPage,
        index: 2,
        progress: nil,
        selectedText: "different",
        pdfBounds: [StoredPDFWordRect(CGRect(x: 10, y: 10, width: 30, height: 10))]
    )
    let pdfTextSource = AIConversationSourceLocation(
        kind: .pdfPage,
        index: 2,
        progress: nil,
        selectedText: "Knowing where the trap is",
        pdfBounds: nil
    )
    let pdfMatcher = ReaderAISourceMatcher(
        currentDocumentKind: .pdf,
        currentWebProgress: 0,
        candidates: [pdfBoundsSource, pdfTextSource]
    )
    try expectEqual(
        pdfMatcher.readAloudSource(
            matching: "unrelated text",
            pageIndex: 2,
            pdfBounds: CGRect(x: 12, y: 11, width: 8, height: 4),
            webProgress: nil
        ),
        pdfBoundsSource,
        "PDF read-aloud source matching should prefer intersecting bounds"
    )
    try expectEqual(
        pdfMatcher.readAloudSource(
            matching: "Knowing where the trap is - that is the first step",
            pageIndex: 2,
            pdfBounds: nil,
            webProgress: nil
        ),
        pdfTextSource,
        "PDF read-aloud source matching should fall back to selected text overlap"
    )

    let webSource = AIConversationSourceLocation(
        kind: .webProgress,
        index: 0,
        progress: 0.42,
        selectedText: nil,
        webContext: nil,
        occurrenceIndex: nil
    )
    let webMatcher = ReaderAISourceMatcher(
        currentDocumentKind: .epub,
        currentWebProgress: 0.40,
        candidates: [webSource]
    )
    try expectEqual(
        webMatcher.readAloudSource(matching: "spoken web text", pageIndex: nil, pdfBounds: nil, webProgress: nil),
        webSource,
        "Web read-aloud source matching should fall back to nearby progress"
    )
    try expect(ReaderAISourceMatcher.linkedWordText("imperative", overlapsReadAloudText: "more imperative still"), "linked word text should match spoken phrase")
}

private func testCapturedPageScrollGuard() throws {
    try expect(shouldApplyCapturedPageScroll(capturedPageIndex: 2, documentPageCount: 5), "captured page in current document should be scrollable")
    try expect(!shouldApplyCapturedPageScroll(capturedPageIndex: -1, documentPageCount: 5), "negative captured page should be ignored")
    try expect(!shouldApplyCapturedPageScroll(capturedPageIndex: 5, documentPageCount: 5), "captured page outside current document should be ignored")
}

private func testPDFBrightnessPolicy() throws {
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

private func testDebouncedTask() throws {
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

private func testSpeechTextPolicyNormalization() throws {
    let text = "well-\nknown  isn \u{2019} t rare\u{2026}"
    let normalized = SpeechTextPolicy.normalizedEnglishInput(text)

    try expectEqual(normalized, "wellknown isn't rare...", "TTS normalization should repair PDF line breaks and punctuation")
}

private func testSpeechTextPolicyEnglishCandidate() throws {
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

private func testSpeechTextPolicySegments() throws {
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

private func testReadAloudTextMatcher() throws {
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

private func testReadAloudManualAdvanceKeyPolicy() throws {
    try expectEqual(ReadAloudManualAdvanceKeyPolicy.action(for: "\\"), .next, "backslash should trigger manual TTS advance")
    try expectEqual(ReadAloudManualAdvanceKeyPolicy.action(for: "、"), .next, "Chinese enumeration comma should trigger manual TTS advance")
    try expectEqual(ReadAloudManualAdvanceKeyPolicy.action(for: "]"), .replayCurrent, "right bracket should replay current TTS segment")
    try expectEqual(ReadAloudManualAdvanceKeyPolicy.action(for: "】"), .replayCurrent, "Chinese right bracket should replay current TTS segment")
    try expectEqual(ReadAloudManualAdvanceKeyPolicy.action(for: "["), .replayPrevious, "left bracket should replay previous TTS segment")
    try expectEqual(ReadAloudManualAdvanceKeyPolicy.action(for: "【"), .replayPrevious, "Chinese left bracket should replay previous TTS segment")
    try expect(!ReadAloudManualAdvanceKeyPolicy.accepts("/"), "slash should not trigger manual TTS advance")
    try expect(!ReadAloudManualAdvanceKeyPolicy.accepts(nil), "nil key should not trigger manual TTS advance")
}

private func testReadAloudPlaybackPhase() throws {
    try expect(!ReadAloudPlaybackPhase.idle.isActive, "idle read-aloud phase should not be active")
    try expect(ReadAloudPlaybackPhase.loading.isActive, "loading read-aloud phase should be active")
    try expect(ReadAloudPlaybackPhase.loading.isLoading, "loading read-aloud phase should report loading")
    try expect(ReadAloudPlaybackPhase.playing.isActive, "playing read-aloud phase should be active")
    try expect(ReadAloudPlaybackPhase.paused.isPaused, "paused read-aloud phase should report paused")
    try expect(!ReadAloudPlaybackPhase.paused.isLoading, "paused read-aloud phase should not report loading")
}

private func testKokoroWorkerResponseReader() throws {
    var reader = KokoroWorkerResponseReader(requestID: "target")
    let payload = """
    not json
    {"id":"other","ok":true}
    {"id":"target","ok":false,"error":"bad input"}

    """
    let response = reader.append(Data(payload.utf8))

    try expectEqual(response, KokoroWorkerResponse(id: "target", ok: false, error: "bad input"), "reader should ignore bad JSON and wrong ids")
}

private func testKokoroWorkerResponseReaderBuffersPartialLines() throws {
    var reader = KokoroWorkerResponseReader(requestID: "target")
    try expect(reader.append(Data(#"{"id":"target","#.utf8)) == nil, "partial worker responses should wait for a newline")
    var tail = Data(#""ok":true,"error":null}"#.utf8)
    tail.append(0x0A)
    let response = reader.append(tail)

    try expectEqual(response, KokoroWorkerResponse(id: "target", ok: true, error: nil), "reader should decode buffered partial JSON lines")
}

private let tests: [(String, () throws -> Void)] = [
    ("Vocabulary SRS", VocabularyLogicTests.testVocabularySRS),
    ("Vocabulary review card selector", VocabularyLogicTests.testVocabularyReviewCardSelector),
    ("Vocabulary daily goal policy", VocabularyLogicTests.testVocabularyDailyGoalPolicy),
    ("Vocabulary learning stats", VocabularyLogicTests.testVocabularyLearningStats),
    ("Personal vocabulary tokenizer and policy", VocabularyLogicTests.testPersonalVocabularyTokenizerAndPolicy),
    ("Vocabulary answer formatter", VocabularyLogicTests.testVocabularyAnswerFormatter),
    ("Recent document sorting/import", ReaderShelfLogicTests.testRecentDocumentSortingAndImport),
    ("Dropped document actions", ReaderShelfLogicTests.testDroppedDocumentActions),
    ("Embedding defaults", AISettingsLogicTests.testEmbeddingDefaults),
    ("AI settings injected defaults model selection", AISettingsLogicTests.testAISettingsStoreInjectedDefaultsModelSelection),
    ("AI provider descriptors", AISettingsLogicTests.testAIProviderDescriptors),
    ("AI settings injected defaults embedding and toggles", AISettingsLogicTests.testAISettingsStoreInjectedDefaultsEmbeddingAndToggles),
    ("AI settings speech selection validation", SpeechRuntimeLogicTests.testAISettingsStoreSpeechSelectionValidation),
    ("Piper speech speed length scale", SpeechRuntimeLogicTests.testPiperSpeechSpeedLengthScale),
    ("Kokoro speech speed multiplier", SpeechRuntimeLogicTests.testKokoroSpeechSpeedMultiplier),
    ("Piper worker input line normalization", SpeechRuntimeLogicTests.testPiperWorkerInputLineNormalizesNewlines),
    ("Piper worker output path validation", SpeechRuntimeLogicTests.testPiperWorkerOutputPathValidation),
    ("Piper worker restart threshold", SpeechRuntimeLogicTests.testPiperWorkerRestartThreshold),
    ("Piper CoreML fallback diagnostics", SpeechRuntimeLogicTests.testPiperCoreMLFallbackDiagnostics),
    ("Kokoro installed voice cache key", SpeechRuntimeLogicTests.testKokoroInstalledVoiceCacheKeyUsesVariantVoiceAndPath),
    ("Vocabulary audio cache key", SpeechRuntimeLogicTests.testVocabularyAudioCacheKeySeparatesSpeechSettings),
    ("Speech synthesis error messages", SpeechRuntimeLogicTests.testSpeechSynthesisErrorMessagesAreActionable),
    ("Speech runtime inference failure store", SpeechRuntimeLogicTests.testSpeechRuntimeInferenceFailureStore),
    ("Speech runtime release asset URLs", SpeechRuntimeLogicTests.testSpeechRuntimeDownloadURLsUseReleaseAssets),
    ("Speech runtime local runtime descriptors", SpeechRuntimeLogicTests.testSpeechRuntimeLocalRuntimeDescriptors),
    ("Speech runtime local runtime download plans", SpeechRuntimeLogicTests.testSpeechRuntimeLocalRuntimeDownloadPlans),
    ("Speech runtime local runtime registry", SpeechRuntimeLogicTests.testSpeechRuntimeLocalRuntimeRegistry),
    ("Speech model manifest checksum validation", SpeechRuntimeLogicTests.testSpeechModelManifestParsingAndChecksumValidation),
    ("Local runtime download manifest asset decoding", SpeechRuntimeLogicTests.testLocalRuntimeDownloadManifestAssetDecoding),
    ("Speech runtime resume range validation", SpeechRuntimeLogicTests.testSpeechRuntimeResumeContentRangeValidation),
    ("Speech runtime partial restart policy", SpeechRuntimeLogicTests.testSpeechRuntimePartialRestartPolicy),
    ("Speech runtime partial metadata validation", SpeechRuntimeLogicTests.testSpeechRuntimePartialMetadataValidationAndIfRange),
    ("Speech runtime download configuration", SpeechRuntimeLogicTests.testSpeechRuntimeDownloadConfigurationAndProgressTotals),
    ("Speech model manifest decode fallback", SpeechRuntimeLogicTests.testSpeechModelManifestDecodeFallsBackToBundledManifest),
    ("Speech runtime install disk space policy", SpeechRuntimeLogicTests.testSpeechRuntimeInstallDiskSpacePolicy),
    ("Bundled speech model manifest parsing", SpeechRuntimeLogicTests.testBundledSpeechModelManifestParses),
    ("Speech runtime availability text", SpeechRuntimeLogicTests.testSpeechRuntimeAvailabilityText),
    ("Local runtime status presenter", SpeechRuntimeLogicTests.testLocalRuntimeStatusPresenter),
    ("Piper runtime resource validation", SpeechRuntimeLogicTests.testPiperRuntimeRequiresPhonemizeResources),
    ("Piper non-default voice validation", SpeechRuntimeLogicTests.testPiperAnyVoiceAcceptsNonDefaultVoice),
    ("Piper model download availability", SpeechRuntimeLogicTests.testPiperModelDownloadMakesBundledRuntimeAvailable),
    ("Speech runtime install state detail", SpeechRuntimeLogicTests.testSpeechRuntimeInstallStateDistinguishesRuntimeAndModel),
    ("Speech runtime health detail", SpeechRuntimeLogicTests.testSpeechRuntimeHealthDistinguishesRuntimeAndModelPaths),
    ("Kokoro model download availability", SpeechRuntimeLogicTests.testKokoroModelDownloadMakesBundledRuntimeAvailable),
    ("Kokoro Mandarin model download availability", SpeechRuntimeLogicTests.testKokoroMandarinModelDownloadMakesBundledRuntimeAvailable),
    ("KittenTTS model download availability", SpeechRuntimeLogicTests.testKittenModelDownloadMakesBundledRuntimeAvailable),
    ("Piper archive voice validation", SpeechRuntimeLogicTests.testPiperArchiveValidationRequiresPackagedVoice),
    ("Speech runtime install manifest cache filtering", SpeechRuntimeLogicTests.testSpeechRuntimeInstallManifestFiltersExternalCachePaths),
    ("Local runtime install manifest compatibility", SpeechRuntimeLogicTests.testLocalRuntimeInstallManifestCompatibility),
    ("Kokoro cache install transaction", SpeechRuntimeLogicTests.testKokoroCacheInstallTransactionRollbackAndCommit),
    ("Network error sensitive body formatting", AISettingsLogicTests.testNetworkErrorFormattingSanitizesSensitiveBody),
    ("Network error long body formatting", AISettingsLogicTests.testNetworkErrorFormattingTruncatesLongBody),
    ("AI response parser non-streaming", AISettingsLogicTests.testAIResponseParserParsesNonStreamingResponses),
    ("AI response parser streaming", AISettingsLogicTests.testAIResponseParserParsesStreamingDeltas),
    ("Difficult sentence prompt sections", AISettingsLogicTests.testDifficultSentencePromptContainsRequiredSections),
    ("AI conversation linked history removal", AIConversationContextStoreTests.testLinkedWordHistoryRemovalKeepsSystemMessage),
    ("AI conversation context trimming", AIConversationContextStoreTests.testContextTrimsRecentMessages),
    ("ECDICT SQLite lookup", ECDICTLogicTests.testSQLiteLookupAndMarkdownAnswer),
    ("ECDICT CSV lookup", ECDICTLogicTests.testCSVLookup),
    ("ECDICT lookup key normalization", ECDICTLogicTests.testLookupKeyNormalization),
    ("Answer providers", ECDICTLogicTests.testAnswerProviders),
    ("Embedding key isolation", AISettingsLogicTests.testEmbeddingKeyIsolation),
    ("Embedding legacy key migration", AISettingsLogicTests.testEmbeddingLegacyKeyMigration),
    ("Embedding warmup idle policy", testEmbeddingWarmupIdlePolicy),
    ("Reader entity decoding", EPUBLogicTests.testReaderEntityDecoding),
    ("EPUB text decoding", EPUBLogicTests.testEPUBTextDecoding),
    ("EPUB spine linear parsing", EPUBLogicTests.testEPUBSpineLinearParsing),
    ("EPUB OPF XML parsing", EPUBLogicTests.testEPUBOPFXMLParsing),
    ("EPUB lazy images and safe paths", EPUBLogicTests.testEPUBLazyImagesAndSafePaths),
    ("EPUB unreadable body diagnostics", EPUBLogicTests.testEPUBUnreadableBodyDiagnostics),
    ("EPUB TOC href normalization", EPUBLogicTests.testEPUBTOCHrefNormalization),
    ("EPUB internal links and sanitizing", EPUBLogicTests.testEPUBInternalLinkTargetsAndSanitizing),
    ("Word record incremental store", VocabularyLogicTests.testWordRecordIncrementalStore),
    ("Word record legacy migration", VocabularyLogicTests.testWordRecordLegacyMigrationDoesNotReviveClearedData),
    ("Page scroll direction", testPageScrollDirection),
    ("PDF paging policy", testPDFPagingPolicy),
    ("Reader session policy", testReaderSessionPolicy),
    ("Reader session PDF anchor", testReaderSessionStorePDFAnchor),
    ("Reader session farthest progress", testReaderSessionStoreFarthestProgress),
    ("Reader session web progress bounds", testReaderSessionStoreWebProgressBounds),
    ("Reader progress formatter", testReaderProgressFormatter),
    ("Vocabulary text policy", VocabularyLogicTests.testVocabularyTextPolicy),
    ("Vocabulary exporter", VocabularyLogicTests.testVocabularyExporter),
    ("Reading note store round trip", ReadingNoteLogicTests.testReadingNoteStoreRoundTrip),
    ("Reading note store unavailable database", ReadingNoteLogicTests.testReadingNoteStoreUnavailableDatabase),
    ("Reading note exporter fallback quote", ReadingNoteLogicTests.testReadingNoteExporterFallbackQuote),
    ("Reading note exporter HTML and scope", ReadingNoteLogicTests.testReadingNoteExporterHTMLAndScope),
    ("Reading note display title uses first markdown line", ReadingNoteLogicTests.testReadingNoteDisplayTitleUsesFirstMarkdownLine),
    ("Reading note list presenter rows", ReadingNoteLogicTests.testReadingNoteListPresenterRows),
    ("Reading note quote soft line breaks", ReadingNoteLogicTests.testReadingNoteQuoteSoftLineBreaks),
    ("Reading note PDF line gaps preserve paragraph breaks", ReadingNoteLogicTests.testReadingNotePDFLineGapsPreserveParagraphBreaks),
    ("Reading note slash command groups", ReadingNoteLogicTests.testReadingNoteSlashCommandGroups),
    ("Reading note templates", ReadingNoteLogicTests.testReadingNoteTemplates),
    ("Reading note slash range policy", ReadingNoteLogicTests.testReadingNoteSlashRangePolicy),
    ("Reading note AI markdown body", ReadingNoteLogicTests.testReadingNoteAIMarkdownBodyStripsFence),
    ("Reading note AI markdown image protector", ReadingNoteLogicTests.testReadingNoteAIMarkdownImageProtector),
    ("Reading note AI document context", ReadingNoteLogicTests.testReadingNoteAIDocumentContext),
    ("Reading note markdown input policy", ReadingNoteLogicTests.testReadingNoteMarkdownInputPolicyRendersInlineStyles),
    ("Reading note markdown render range policy", ReadingNoteLogicTests.testReadingNoteMarkdownRenderRangePolicy),
    ("Markdown block parser parses blocks", ReadingNoteLogicTests.testMarkdownBlockParserParsesBlocks),
    ("Markdown inline parser applies styles", ReadingNoteLogicTests.testMarkdownInlineParserAppliesStyles),
    ("Reading note editing shortcuts", ReadingNoteLogicTests.testReadingNoteEditingShortcutsAcceptControlCopyPaste),
    ("Reading note text replacement policy", ReadingNoteLogicTests.testReadingNoteTextReplacementPolicyRestoresSelection),
    ("Reading note line prefix policy", ReadingNoteLogicTests.testReadingNoteLinePrefixPolicy),
    ("Reading note inline style policy", ReadingNoteLogicTests.testReadingNoteInlineStylePolicyTogglesTrait),
    ("Reading note markdown round trip", ReadingNoteLogicTests.testReadingNoteMarkdownRoundTrip),
    ("Reading note markdown list inline style round trip", ReadingNoteLogicTests.testReadingNoteMarkdownRoundTripPreservesInlineStylesInLists),
    ("Reading note document codec round trip", ReadingNoteLogicTests.testReadingNoteDocumentCodecRoundTrip),
    ("Reading note document appends AI section", ReadingNoteLogicTests.testReadingNoteDocumentAppendsAISection),
    ("Reading note document image markdown", ReadingNoteLogicTests.testReadingNoteDocumentImageMarkdown),
    ("Reading note image markdown round trip with spaced file path", ReadingNoteLogicTests.testReadingNoteImageMarkdownRoundTripWithSpacedFilePath),
    ("Reading note asset store imports image to managed directory", ReadingNoteLogicTests.testReadingNoteAssetStoreImportsImageToManagedDirectory),
    ("Reading note editor state stale AI", ReadingNoteLogicTests.testReadingNoteEditorStateRejectsStaleAIResults),
    ("Reading note AI insertion mode", ReadingNoteLogicTests.testReadingNoteAIInsertionModePlaceholderFlag),
    ("Reader AI context text cleanup", testReaderAIContextTextCleanup),
    ("Reader AI context policy", testReaderAIContextPolicy),
    ("AI response text formatter", testAIResponseTextFormatter),
    ("AI conversation markdown exporter", testAIConversationMarkdownExporter),
    ("Embedding action policy", testEmbeddingActionPolicy),
    ("Selection toolbar configuration", VocabularyLogicTests.testSelectionToolbarConfiguration),
    ("Vocabulary review display record loader", VocabularyLogicTests.testVocabularyReviewDisplayRecordLoaderLoadsOnlyCurrentRecord),
    ("Reading context snapshot", testReadingContextSnapshot),
    ("Reader focused selection priority", testReaderFocusedSelectionPriority),
    ("Reader AI source matcher", testReaderAISourceMatcher),
    ("Captured page scroll guard", testCapturedPageScrollGuard),
    ("PDF brightness policy", testPDFBrightnessPolicy),
    ("Debounced task", testDebouncedTask),
    ("Speech text normalization", testSpeechTextPolicyNormalization),
    ("Speech text English candidate", testSpeechTextPolicyEnglishCandidate),
    ("Speech text segments", testSpeechTextPolicySegments),
    ("Read-aloud text matcher", testReadAloudTextMatcher),
    ("Read-aloud manual advance key policy", testReadAloudManualAdvanceKeyPolicy),
    ("Read-aloud playback phase", testReadAloudPlaybackPhase),
    ("Kokoro worker response reader", testKokoroWorkerResponseReader),
    ("Kokoro worker response partial lines", testKokoroWorkerResponseReaderBuffersPartialLines)
]

@main
private struct LogicTestRunner {
    static func main() {
        var failures: [String] = []
        for (name, test) in tests {
            do {
                try test()
                print("PASS \(name)")
            } catch {
                failures.append("FAIL \(name): \(error)")
            }
        }

        if failures.isEmpty {
            print("All \(tests.count) logic tests passed.")
        } else {
            for failure in failures {
                print(failure)
            }
            exit(1)
        }
    }
}
