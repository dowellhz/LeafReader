import Cocoa

extension AIChatPanel {
    func shouldUseLocalDictionaryFallback(for error: Error) -> Bool {
        RequestAvailabilityPolicy.shouldUseLocalDictionaryFallback(for: error)
    }

    func handleAIRequestFailure(
        _ error: Error,
        streamedText: String,
        assistantBody: NSTextField?,
        requestMessages: [ChatMessage],
        linkID: String?,
        linkedQuestion: String?,
        fallbackAnswer: String?,
        answerSuffix: String?
    ) {
        let shouldUseDictionaryFallback = shouldUseLocalDictionaryFallback(for: error)
        logAIRequestFailure(error, usesDictionaryFallback: shouldUseDictionaryFallback)

        if shouldUseDictionaryFallback {
            if let fallbackAnswer, let assistantBody {
                applyOfflineDictionaryFallback(
                    fallbackAnswer,
                    assistantBody: assistantBody,
                    linkID: linkID,
                    linkedQuestion: linkedQuestion
                )
                return
            }
        }

        lastFailedAIRequest = FailedAIRequest(
            messages: requestMessages,
            linkID: linkID,
            linkedQuestion: linkedQuestion,
            fallbackAnswer: fallbackAnswer,
            answerSuffix: answerSuffix
        )
        showAIRequestError(error, streamedText: streamedText, assistantBody: assistantBody)
        appendRetryButton()
        if let fallbackAnswer, !shouldUseDictionaryFallback {
            appendLocalDictionaryFallbackAnswer(fallbackAnswer, linkID: linkID, linkedQuestion: linkedQuestion)
        }
    }

    func applyOfflineDictionaryFallback(
        _ answer: String,
        assistantBody: NSTextField,
        linkID: String?,
        linkedQuestion: String?
    ) {
        recordTranscript(role: AppText.aiRole, text: answer, linkID: linkID)
        appendMessage(ChatMessage(role: "assistant", content: answer, linkID: linkID))
        updateBubble(assistantBody, role: AppText.aiRole, text: answer, notify: false)
        persistBubbleIfNeeded(assistantBody)
        scrollToDictionaryAnswer(assistantBody)
        if let linkID, let linkedQuestion {
            onLinkedAnswerCompleted?(linkID, linkedQuestion, answer)
        }
    }

    func showAIRequestError(_ error: Error, streamedText: String, assistantBody: NSTextField?) {
        let message = userFacingAIError(error)
        if streamedText.isEmpty, let assistantBody {
            updateBubble(assistantBody, role: AppText.errorRole, text: message, notify: false)
        } else {
            appendBubble(role: AppText.errorRole, text: message, persist: false)
        }
    }

    func appendLocalDictionaryFallbackAnswer(_ answer: String, linkID: String?, linkedQuestion: String?) {
        let text = AppText.localized(
            "AI 暂时连接失败。以下为本地词典结果：\n\n\(answer)",
            "AI is temporarily unavailable. Local dictionary result:\n\n\(answer)"
        )
        let body = appendBubble(role: AppText.aiRole, text: text, renderMarkdown: true, linkID: linkID, persist: false)
        scrollToDictionaryAnswer(body)
        if let linkID, let linkedQuestion {
            onLinkedAnswerCompleted?(linkID, linkedQuestion, answer)
        }
    }

    func logAIRequestFailure(_ error: Error, usesDictionaryFallback: Bool) {
        NSLog(
            "LeafReader AI request failed providerFallback=%@ isOnline=%@ error=%@",
            usesDictionaryFallback ? "true" : "false",
            NetworkConnectivityMonitor.shared.isOnline ? "true" : "false",
            (error as NSError).localizedDescription
        )
    }
}
