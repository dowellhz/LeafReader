import Foundation

enum WebReadAloudBatchParser {
    struct Batch {
        let segments: [SpeechPlaybackCoordinator.ReadAloudSegment]
        let hasMore: Bool
    }

    static let prepareBatchScript = """
    (() => {
      if (window.leafReaderPrepareReadAloudBatch) {
        return window.leafReaderPrepareReadAloudBatch();
      }
      if (window.leafReaderPrepareReadAloudSegments) {
        return { segments: window.leafReaderPrepareReadAloudSegments(), hasMore: false };
      }
      return { segments: [], hasMore: false };
    })();
    """

    static let advanceBatchScript = """
    (() => {
      if (!window.leafReaderAdvanceReadAloudBatch) return { ok: false };
      return window.leafReaderAdvanceReadAloudBatch();
    })();
    """

    static func batch(from value: Any?) -> Batch {
        if let dictionary = value as? [String: Any] {
            return Batch(
                segments: segments(from: dictionary["segments"]),
                hasMore: dictionary["hasMore"] as? Bool ?? false
            )
        }
        return Batch(
            segments: segments(from: value),
            hasMore: false
        )
    }

    private static func segments(from value: Any?) -> [SpeechPlaybackCoordinator.ReadAloudSegment] {
        guard let rows = value as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            let text = (row["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let speechText = (row["speechText"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? text
            guard !text.isEmpty, !speechText.isEmpty else { return nil }
            return SpeechPlaybackCoordinator.ReadAloudSegment(speechText: speechText, displayText: text)
        }
    }
}
