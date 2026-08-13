import Foundation
import CoreGraphics

final class DebouncedTask {
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

enum ScrollPageDirection: Equatable {
    case previous
    case next
}

func pageDirectionAtEdge(deltaY: Double, isAtTop: Bool, isAtBottom: Bool) -> ScrollPageDirection? {
    if isAtTop, deltaY > 0 {
        return .previous
    }
    if isAtBottom, deltaY < 0 {
        return .next
    }
    return nil
}

func shouldApplyCapturedPageScroll(capturedPageIndex: Int, documentPageCount: Int) -> Bool {
    capturedPageIndex >= 0 && capturedPageIndex < documentPageCount
}

func testEmbeddingWarmupIdlePolicy() throws {
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

func testPageScrollDirection() throws {
    try expectEqual(pageDirectionAtEdge(deltaY: 12, isAtTop: true, isAtBottom: false), .previous, "scrolling upward at page top should go previous")
    try expectEqual(pageDirectionAtEdge(deltaY: -12, isAtTop: false, isAtBottom: true), .next, "scrolling downward at page bottom should go next")
    try expect(pageDirectionAtEdge(deltaY: 12, isAtTop: false, isAtBottom: true) == nil, "scrolling upward at bottom should not go previous")
    try expect(pageDirectionAtEdge(deltaY: -12, isAtTop: true, isAtBottom: false) == nil, "scrolling downward at top should not go next")
}

func testPDFPagingPolicy() throws {
    try expect(PDFReadingMode.paged.allowsEdgePaging, "paged mode should keep edge-triggered page turns")
    try expect(!PDFReadingMode.continuous.allowsEdgePaging, "continuous mode should use native scrolling without edge-triggered page turns")
    try expectEqual(PDFReadingMode(rawValue: "continuous"), .continuous, "continuous reading mode should round-trip through persistence")
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

func testReaderSessionPolicy() throws {
    try expectEqual(ReaderSessionPolicy.webProgressSaveInterval, 0.5, "web progress save interval should remain explicit")
    try expectEqual(ReaderSessionPolicy.lastPositionSaveDelay, 3.0, "last position should only save after a stable dwell")
    try expectEqual(ReaderSessionPolicy.initialRestoreDelay, 0.2, "initial restore delay should remain explicit")
    try expectEqual(ReaderSessionPolicy.pdfViewportAnchorTopInset, 24, "PDF viewport anchor inset should remain explicit")
    try expect(ReaderSessionPolicy.isRestorablePDFScale(0.1), "minimum PDF scale should restore")
    try expect(ReaderSessionPolicy.isRestorablePDFScale(8), "maximum PDF scale should restore")
    try expect(!ReaderSessionPolicy.isRestorablePDFScale(0.09), "too-small PDF scale should not restore")
    try expect(!ReaderSessionPolicy.isRestorablePDFScale(8.1), "too-large PDF scale should not restore")
}

func testReaderSessionStorePDFAnchor() throws {
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

func testReaderSessionStoreFarthestProgress() throws {
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

func testReaderSessionStoreWebProgressBounds() throws {
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

func testReaderProgressFormatter() throws {
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

    try expectEqual(ReaderProgressFormatter.searchResultText(resultIndex: nil, resultCount: 0, isSearching: true), "0 / …", "search should show an indeterminate total while finding")
    try expectEqual(ReaderProgressFormatter.searchResultText(resultIndex: 1, resultCount: 4, isSearching: true), "2 / …", "search should keep the current match while finding")
    try expectEqual(ReaderProgressFormatter.searchResultText(resultIndex: 9, resultCount: 4, isSearching: false), "4 / 4", "search should clamp the current match")
    try expectEqual(ReaderProgressFormatter.searchResultText(resultIndex: nil, resultCount: 0, isSearching: false), "0 / 0", "finished empty search should show zero results")

    try expectEqual(ReaderProgressFormatter.webSectionProgress(index: 2, locationCount: 5), 0.5, "web source progress should use the section index")
    try expectEqual(ReaderProgressFormatter.webSectionProgress(index: -2, locationCount: 5), 0, "web source progress should clamp low")
    try expectEqual(ReaderProgressFormatter.webSectionProgress(index: 20, locationCount: 5), 1, "web source progress should clamp high")
    try expectEqual(ReaderProgressFormatter.webSectionProgress(index: 2, locationCount: 1), 0, "single-section sources should start at zero")
}

func testReaderAIContextTextCleanup() throws {
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

func testReaderAIContextPolicy() throws {
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

func testAIResponseTextFormatter() throws {
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

func testAIConversationMarkdownExporter() throws {
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

func testEmbeddingActionPolicy() throws {
    try expectEqual(EmbeddingActionPolicy.statusClearDelay, 1.5, "embedding status clear delay should remain explicit")
}

func testReadingContextSnapshot() throws {
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

func testReaderFocusedSelectionPriority() throws {
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

func testReaderAISourceMatcher() throws {
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
