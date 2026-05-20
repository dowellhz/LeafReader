import Foundation

enum ReaderSessionPolicy {
    static let webRestoreDelay: TimeInterval = 0.35
    static let webProgressSaveInterval: TimeInterval = 0.5
    static let lastPositionSaveDelay: TimeInterval = 3.0
    static let initialRestoreDelay: TimeInterval = 0.2
    static let minimumRestoredPDFScale: CGFloat = 0.1
    static let maximumRestoredPDFScale: CGFloat = 8
    static let pdfViewportAnchorTopInset: CGFloat = 24

    static func isRestorablePDFScale(_ scale: CGFloat) -> Bool {
        scale >= minimumRestoredPDFScale && scale <= maximumRestoredPDFScale
    }
}
