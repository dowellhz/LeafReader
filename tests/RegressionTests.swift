import Cocoa
import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw TestFailure(description: message)
    }
}

private func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) throws {
    if lhs != rhs {
        throw TestFailure(description: "\(message). expected \(rhs), got \(lhs)")
    }
}

private func bubble(_ role: String, _ text: String) -> SavedAIConversationBubble {
    SavedAIConversationBubble(
        role: role,
        text: text,
        collapsible: false,
        renderMarkdown: true,
        sourceLocation: nil
    )
}

private func testMarkdownRendererCompactsOriginalTranslationGap() throws {
    let input = """
    **原文**
    "We'll move in strengthened by two legions."

    **翻译**
    "我们将得到两个军团的增援。"


    * strengthened by：得到增援。
    """
    let rendered = MarkdownRenderer.render(input, textColor: .black).string
    try expect(!rendered.contains("legions.\"\n\n翻译"), "blank line before translation heading should be folded")
    try expect(!rendered.contains("\n\n\n"), "consecutive blank lines should be folded")
    try expect(rendered.contains("legions.\"\n翻译"), "translation heading should follow original content directly")
}

private func testMarkdownRendererKeepsAISectionHeadingBold() throws {
    let rendered = MarkdownRenderer.render("### 解析\n\n内容\n\n笔记\n\n补充\n\n润色\n\n结果", textColor: .black)
    let string = rendered.string as NSString
    for heading in ["解析", "笔记", "润色"] {
        let range = string.range(of: heading)
        try expect(range.location != NSNotFound, "rendered text should include \(heading) heading")
        guard let font = rendered.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont else {
            throw TestFailure(description: "\(heading) heading should have a font")
        }
        try expect(font.fontDescriptor.symbolicTraits.contains(.bold), "\(heading) heading should be bold")
    }
}

private func testDocumentIdentityPreservesLegacyDataWhenOnlyLegacyHasData() throws {
    let fastID = "fast-new"
    let legacyID = "legacy-md5"
    try expectEqual(
        DocumentIdentity.selectedID(fastID: fastID, legacyID: legacyID, legacyHasData: true, fastHasData: false),
        legacyID,
        "legacy ID should be used when old data exists and fast ID has no data"
    )
    try expectEqual(
        DocumentIdentity.selectedID(fastID: fastID, legacyID: legacyID, legacyHasData: true, fastHasData: true),
        fastID,
        "fast ID should win once fast ID already has data"
    )
    try expectEqual(
        DocumentIdentity.selectedID(fastID: fastID, legacyID: nil, legacyHasData: false, fastHasData: false),
        fastID,
        "fast ID should be used when no legacy cache exists"
    )
}

private func testDocumentIdentityFastIDIsStableAndNotMD5Length() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("leafreader-document-id-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let fileURL = directory.appendingPathComponent("sample.pdf")
    try Data("sample".utf8).write(to: fileURL)
    let firstID = DocumentIdentity.fastID(for: fileURL)
    let secondID = DocumentIdentity.fastID(for: fileURL)
    try expectEqual(firstID, secondID, "fast document ID should be stable for unchanged file metadata")
    try expect(firstID.hasPrefix("fast-"), "fast document ID should be namespaced")
    try expectEqual(firstID.count, 37, "fast document ID should use the fast- prefix plus a 16-byte hex hash")
}

private func testAIConversationMergeKeepsUnloadedHistory() throws {
    let loaded = SavedAIConversation(bubbles: [
        bubble("user", "old question"),
        bubble("assistant", "old answer"),
        bubble("user", "visible question")
    ])
    let visible = SavedAIConversation(bubbles: [
        bubble("user", "visible question"),
        bubble("assistant", "new answer")
    ])

    let merged = SavedAIConversation.mergedForSave(loaded: loaded, visible: visible, maxBubbles: 10)
    try expectEqual(
        merged.bubbles.map(\.text),
        ["old question", "old answer", "visible question", "new answer"],
        "merge should preserve unloaded history and append only new visible bubbles"
    )
}

private func testAIConversationMergeTrimsToLimitAfterPreservingNewest() throws {
    let loaded = SavedAIConversation(bubbles: [
        bubble("user", "old-1"),
        bubble("assistant", "old-2"),
        bubble("user", "old-3")
    ])
    let visible = SavedAIConversation(bubbles: [
        bubble("assistant", "new-1"),
        bubble("assistant", "new-2")
    ])

    let merged = SavedAIConversation.mergedForSave(loaded: loaded, visible: visible, maxBubbles: 3)
    try expectEqual(
        merged.bubbles.map(\.text),
        ["old-3", "new-1", "new-2"],
        "merge should trim the oldest bubbles after appending new visible bubbles"
    )
}

private func testAIConversationRemovalPreventsMergeRestore() throws {
    let deletedQuestion = bubble("user", "deleted question")
    let deletedAnswer = bubble("assistant", "deleted answer")
    let loaded = SavedAIConversation(bubbles: [
        bubble("user", "old question"),
        deletedQuestion,
        deletedAnswer
    ])
    let visible = SavedAIConversation(bubbles: [
        bubble("user", "old question")
    ])

    let prunedLoaded = loaded.removing([deletedQuestion, deletedAnswer])
    let merged = SavedAIConversation.mergedForSave(loaded: prunedLoaded, visible: visible, maxBubbles: 10)
    try expectEqual(
        merged.bubbles.map(\.text),
        ["old question"],
        "deleted visible conversation bubbles should not be restored from loaded history during merge"
    )
}

private func testAIConversationSourceLocationPreservesWebOccurrenceIndex() throws {
    let source = AIConversationSourceLocation(
        kind: .webProgress,
        index: 3,
        progress: 0.5,
        selectedText: "repeat",
        webContext: "repeat repeat",
        occurrenceIndex: 1
    )
    let data = try JSONEncoder().encode(source)
    let decoded = try JSONDecoder().decode(AIConversationSourceLocation.self, from: data)

    try expectEqual(decoded, source, "web source location should preserve occurrence index")
    try expectEqual(decoded.occurrenceIndex, 1, "web occurrence index should round-trip through saved AI source")
}

private func testAIConversationSourceLocationDecodesLegacyWithoutOccurrenceIndex() throws {
    let json = """
    {
      "kind": "webProgress",
      "index": 2,
      "progress": 0.25,
      "selectedText": "repeat",
      "webContext": "repeat repeat"
    }
    """
    let decoded = try JSONDecoder().decode(AIConversationSourceLocation.self, from: Data(json.utf8))

    try expectEqual(decoded.kind, .webProgress, "legacy web source should decode")
    try expectEqual(decoded.occurrenceIndex, nil, "legacy web source should keep missing occurrence index as nil")
}

private func testAIRequestStateLifecycle() throws {
    let state = AIRequestState()
    let firstID = UUID()
    let secondID = UUID()

    state.begin(id: firstID)
    try expect(state.isActive(firstID), "new request should become active")
    try expect(!state.isActive(secondID), "unrelated request should not be active")
    try expect(state.shouldHandleCompletion(for: firstID), "active request completion should be handled")

    state.begin(id: secondID)
    try expect(!state.shouldHandleCompletion(for: firstID), "replaced request completion should be ignored")
    try expect(state.isActive(secondID), "newer request should replace older active request")

    _ = state.cancelActive()
    try expect(!state.isActive(secondID), "cancel should clear active request")
    try expect(state.shouldHandleCompletion(for: secondID), "cancelled request completion should be consumed once")
    try expect(state.consumeCancellation(for: secondID), "cancelled request should report cancellation")
    try expect(!state.shouldHandleCompletion(for: secondID), "cancelled completion should not be handled twice")

    state.begin(id: firstID)
    _ = state.cancelActive()
    try expect(state.shouldHandleCompletion(for: firstID), "latest cancelled request should still be consumable")
    state.finish()
    try expect(!state.shouldHandleCompletion(for: firstID), "finish should clear pending cancellation state")

    state.begin(id: firstID)
    _ = state.cancelActive()
    try expect(state.shouldHandleCompletion(for: firstID), "cancelled request should be restored for replacement test")
    state.begin(id: secondID)
    try expect(!state.shouldHandleCompletion(for: firstID), "new requests should clear stale cancellation state")
}

private func testLaunchPerformanceTrackerSnapshot() throws {
    let tracker = LaunchPerformanceTracker(startTime: 10)
    tracker.mark("window", now: 10.12)
    tracker.mark("menu", now: 10.2)
    let snapshot = tracker.finish(now: 10.25)

    try expectEqual(snapshot.totalMilliseconds, 250, "launch tracker should report total elapsed milliseconds")
    try expectEqual(snapshot.marks.count, 2, "launch tracker should keep phase marks")
    try expect(snapshot.detailText.contains("window 120ms"), "launch tracker detail should include phase timing")
    try expect(tracker.snapshot()?.totalMilliseconds == 250, "launch tracker should retain the finished snapshot")
}

private func testProcessRunnerCapturesOutputAndTimeout() throws {
    let echo = try ProcessRunner.run(
        executableURL: URL(fileURLWithPath: "/bin/echo"),
        arguments: ["hello"],
        timeout: 2
    )
    try expectEqual(echo.terminationStatus, 0, "successful process should return status zero")
    try expectEqual(
        String(data: echo.stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
        "hello",
        "process runner should capture stdout"
    )
    try expect(!echo.timedOut, "successful process should not report timeout")

    let sleep = try ProcessRunner.run(
        executableURL: URL(fileURLWithPath: "/bin/sleep"),
        arguments: ["2"],
        timeout: 0.1
    )
    try expect(sleep.timedOut, "long-running process should time out")
}

@main
struct RegressionTestRunner {
    static func main() {
        do {
            try testMarkdownRendererCompactsOriginalTranslationGap()
            print("PASS Markdown compact original/translation spacing")
            try testMarkdownRendererKeepsAISectionHeadingBold()
            print("PASS Markdown AI section heading bold")
            try testDocumentIdentityPreservesLegacyDataWhenOnlyLegacyHasData()
            print("PASS Fast document ID legacy compatibility")
            try testDocumentIdentityFastIDIsStableAndNotMD5Length()
            print("PASS Fast document ID stability")
            try testAIConversationMergeKeepsUnloadedHistory()
            print("PASS AI conversation lazy-save merge")
            try testAIConversationMergeTrimsToLimitAfterPreservingNewest()
            print("PASS AI conversation merge trim")
            try testAIConversationRemovalPreventsMergeRestore()
            print("PASS AI conversation deleted bubbles stay deleted")
            try testAIConversationSourceLocationPreservesWebOccurrenceIndex()
            print("PASS AI source web occurrence index")
            try testAIConversationSourceLocationDecodesLegacyWithoutOccurrenceIndex()
            print("PASS AI source legacy decode")
            try testAIRequestStateLifecycle()
            print("PASS AI request state lifecycle")
            try testLaunchPerformanceTrackerSnapshot()
            print("PASS launch performance tracker")
            try testProcessRunnerCapturesOutputAndTimeout()
            print("PASS process runner output and timeout")
            print("RegressionTests passed")
        } catch {
            fputs("RegressionTests failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
