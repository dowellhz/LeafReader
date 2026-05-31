import Foundation

struct ReaderAIContextResolver {
    typealias ContextProvider = (String) -> String

    let explicitSelection: String
    let readAloudSelection: String

    func focusedSelection(contextProvider: ContextProvider) -> ReaderFocusedSelection? {
        if let candidate = focusedCandidate {
            return ReaderFocusedSelection(
                origin: candidate.origin,
                text: candidate.text,
                context: contextProvider(candidate.text).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return nil
    }

    var preferredSelectionText: String {
        focusedCandidate?.text ?? ""
    }

    private var focusedCandidate: Candidate? {
        let explicitText = trimmed(explicitSelection)
        if !explicitText.isEmpty {
            return Candidate(origin: .explicitSelection, text: explicitText)
        }

        let readAloudText = trimmed(readAloudSelection)
        if !readAloudText.isEmpty {
            return Candidate(origin: .readAloudSegment, text: readAloudText)
        }

        return nil
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct Candidate {
        let origin: ReaderFocusedSelection.Origin
        let text: String
    }
}
