import Foundation

struct ReaderFocusedSelection: Equatable {
    enum Origin: Equatable {
        case explicitSelection
        case readAloudSegment
    }

    let origin: Origin
    let text: String
    let context: String

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func make(
        explicitSelection: String,
        readAloudSelection: String,
        explicitContext: String,
        readAloudContext: String
    ) -> ReaderFocusedSelection? {
        let explicitText = explicitSelection.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitText.isEmpty {
            return ReaderFocusedSelection(
                origin: .explicitSelection,
                text: explicitText,
                context: explicitContext.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let readAloudText = readAloudSelection.trimmingCharacters(in: .whitespacesAndNewlines)
        if !readAloudText.isEmpty {
            return ReaderFocusedSelection(
                origin: .readAloudSegment,
                text: readAloudText,
                context: readAloudContext.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return nil
    }

    static func resolve(
        explicitSelection: String,
        readAloudSelection: String,
        contextProvider: ReaderAIContextResolver.ContextProvider
    ) -> ReaderFocusedSelection? {
        ReaderAIContextResolver(
            explicitSelection: explicitSelection,
            readAloudSelection: readAloudSelection
        )
        .focusedSelection(contextProvider: contextProvider)
    }
}
