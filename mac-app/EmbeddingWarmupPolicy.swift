import Foundation

struct EmbeddingWarmupPolicy {
    static let cacheRestoreDelay: TimeInterval = 5.0
    static let warmupDelay: TimeInterval = 18.0
    static let idleThreshold: TimeInterval = 4.0

    static func isReaderIdle(lastInteractionAt: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(lastInteractionAt) >= idleThreshold
    }
}
