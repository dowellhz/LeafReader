import Foundation

enum PDFPagingPolicy {
    static let documentSizeTolerance: CGFloat = 2

    static let wheelEdgeScrollThreshold: CGFloat = 40
    static let wheelPageTurnCooldown: TimeInterval = 0.45

    static let trackpadEdgeSlop: CGFloat = 22
    static let trackpadScrollerTopLimit = 0.02
    static let trackpadScrollerBottomLimit = 0.98
    static let trackpadPageTurnCooldown: TimeInterval = 0.8
    static let trackpadFallbackPageTurnThreshold: CGFloat = 220
    static let trackpadShortPageTurnThreshold: CGFloat = 180
    static let trackpadLongPageTurnThreshold: CGFloat = 120

    static func trackpadPageTurnThreshold(clipHeight: CGFloat, documentHeight: CGFloat) -> CGFloat {
        if documentHeight <= clipHeight + documentSizeTolerance {
            return trackpadShortPageTurnThreshold
        }
        return trackpadLongPageTurnThreshold
    }
}
