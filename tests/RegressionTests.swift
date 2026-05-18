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

@main
struct RegressionTestRunner {
    static func main() {
        do {
            try testMarkdownRendererCompactsOriginalTranslationGap()
            print("PASS Markdown compact original/translation spacing")
            try testDocumentIdentityPreservesLegacyDataWhenOnlyLegacyHasData()
            print("PASS Fast document ID legacy compatibility")
            try testDocumentIdentityFastIDIsStableAndNotMD5Length()
            print("PASS Fast document ID stability")
            try testAIConversationMergeKeepsUnloadedHistory()
            print("PASS AI conversation lazy-save merge")
            try testAIConversationMergeTrimsToLimitAfterPreservingNewest()
            print("PASS AI conversation merge trim")
            print("RegressionTests passed")
        } catch {
            fputs("RegressionTests failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
