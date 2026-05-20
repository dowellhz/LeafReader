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
    try expectEqual(PDFPagingPolicy.trackpadEdgeSlop, 22, "trackpad edge slop should remain explicit")
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
    try expect(snapshot.contextText.contains("p. 2"), "context should include location")
    try expect(snapshot.contextText.contains("selected"), "context should include selection")
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

private let tests: [(String, () throws -> Void)] = [
    ("Vocabulary SRS", VocabularyLogicTests.testVocabularySRS),
    ("Recent document sorting/import", ReaderShelfLogicTests.testRecentDocumentSortingAndImport),
    ("Dropped document actions", ReaderShelfLogicTests.testDroppedDocumentActions),
    ("Embedding defaults", AISettingsLogicTests.testEmbeddingDefaults),
    ("AI settings injected defaults model selection", AISettingsLogicTests.testAISettingsStoreInjectedDefaultsModelSelection),
    ("AI settings injected defaults embedding and toggles", AISettingsLogicTests.testAISettingsStoreInjectedDefaultsEmbeddingAndToggles),
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
    ("Reader AI context text cleanup", testReaderAIContextTextCleanup),
    ("Reader AI context policy", testReaderAIContextPolicy),
    ("AI response text formatter", testAIResponseTextFormatter),
    ("Embedding action policy", testEmbeddingActionPolicy),
    ("Reading context snapshot", testReadingContextSnapshot),
    ("Captured page scroll guard", testCapturedPageScrollGuard),
    ("PDF brightness policy", testPDFBrightnessPolicy),
    ("Debounced task", testDebouncedTask)
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
