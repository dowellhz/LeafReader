import Foundation

enum ReadAloudAdvanceMode: String {
    case automatic
    case manual

    static let defaultsKey = "readAloudAdvanceMode"

    static func load() -> ReadAloudAdvanceMode {
        guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
              let mode = ReadAloudAdvanceMode(rawValue: rawValue) else {
            return .automatic
        }
        return mode
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }

    var toggled: ReadAloudAdvanceMode {
        self == .automatic ? .manual : .automatic
    }

    var title: String {
        switch self {
        case .automatic:
            return AppText.localized("自动", "Auto")
        case .manual:
            return AppText.localized("手动", "Manual")
        }
    }

    var tooltip: String {
        switch self {
        case .automatic:
            return AppText.localized("播完后自动进入下一句", "Automatically continue to the next sentence")
        case .manual:
            return AppText.localized("播完当前句后暂停", "Pause after each sentence")
        }
    }
}
