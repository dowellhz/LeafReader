import Foundation

enum AIConversationContextStoreTests {
    static func testLinkedWordHistoryRemovalKeepsSystemMessage() throws {
        let store = AIConversationContextStore(maxContextMessages: 4) { "system prompt" }
        store.appendTranscript(role: "Me", text: "word header", linkID: "word-1")
        store.appendTranscript(role: "AI", text: "word answer", linkID: "word-1")
        store.appendTranscript(role: "Me", text: "normal question")
        store.appendMessage(ChatMessage(role: "user", content: "word prompt", linkID: "word-1"))
        store.appendMessage(ChatMessage(role: "assistant", content: "word answer", linkID: "word-1"))
        store.appendMessage(ChatMessage(role: "user", content: "normal question"))

        store.removeLinkedWordHistory(ids: ["word-1"])

        try expectEqual(store.messages.map(\.content), ["system prompt", "normal question"], "linked messages should be removed")
        try expectEqual(store.transcriptEntries.map(\.content), ["normal question"], "linked transcript entries should be removed")
    }

    static func testContextTrimsRecentMessages() throws {
        let store = AIConversationContextStore(maxContextMessages: 2) { "system prompt" }
        store.appendMessage(ChatMessage(role: "user", content: "one"))
        store.appendMessage(ChatMessage(role: "assistant", content: "two"))
        store.appendMessage(ChatMessage(role: "user", content: "three"))

        try expectEqual(store.messages.map(\.content), ["system prompt", "two", "three"], "context should keep system plus recent messages")
    }
}
