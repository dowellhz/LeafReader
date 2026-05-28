import Foundation

enum ReadAloudManualAdvanceKeyPolicy {
    static func accepts(_ key: String?) -> Bool {
        guard let key else { return false }
        return key == "\\" || key == "、"
    }
}
