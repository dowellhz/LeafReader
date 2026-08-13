import Foundation

enum VocabularyPersistenceQueue {
    private static let queueKey = DispatchSpecificKey<Void>()
    private static let queue: DispatchQueue = {
        let queue = DispatchQueue(label: "com.linlu.leafreader.vocabulary-persistence", qos: .utility)
        queue.setSpecific(key: queueKey, value: ())
        return queue
    }()

    static func enqueue(_ action: @escaping () -> Void) {
        queue.async(execute: action)
    }

    static func waitForPendingWrites() {
        guard DispatchQueue.getSpecific(key: queueKey) == nil else { return }
        queue.sync {}
    }
}
