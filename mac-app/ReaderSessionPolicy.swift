import Foundation

enum ReaderSessionPolicy {
    static let webRestoreDelay: TimeInterval = 0.35
    static let webProgressSaveInterval: TimeInterval = 0.5
    static let initialRestoreDelay: TimeInterval = 0.2
    static let minimumRestoredPDFScale: CGFloat = 0.1
    static let maximumRestoredPDFScale: CGFloat = 8

    static func isRestorablePDFScale(_ scale: CGFloat) -> Bool {
        scale >= minimumRestoredPDFScale && scale <= maximumRestoredPDFScale
    }
}
