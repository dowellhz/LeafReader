import Foundation

protocol StreamingAnswerProvider {
    func answerStream(
        messages: [ChatMessage],
        onDelta: @escaping (String) -> Void,
        completion: @escaping (Result<String, Error>) -> Void
    ) -> Task<Void, Never>?
}

final class LLMAnswerProvider: StreamingAnswerProvider {
    private let client: AIClient

    init(client: AIClient) {
        self.client = client
    }

    func answerStream(
        messages: [ChatMessage],
        onDelta: @escaping (String) -> Void,
        completion: @escaping (Result<String, Error>) -> Void
    ) -> Task<Void, Never>? {
        client.sendStream(messages: messages, onDelta: onDelta, completion: completion)
    }
}
