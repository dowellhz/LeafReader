import Foundation

enum ReadAloudManualAdvanceKeyPolicy {
    enum Action: Equatable {
        case next
        case replayCurrent
        case replayPrevious
    }

    static func action(for key: String?) -> Action? {
        guard let key else { return nil }
        switch key {
        case "\\", "、":
            return .next
        case "]", "】":
            return .replayCurrent
        case "[", "【":
            return .replayPrevious
        default:
            return nil
        }
    }

    static func accepts(_ key: String?) -> Bool {
        action(for: key) != nil
    }
}
