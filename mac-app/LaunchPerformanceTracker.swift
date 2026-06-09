import Foundation

struct LaunchPerformanceSnapshot {
    let totalMilliseconds: Int
    let marks: [(name: String, milliseconds: Int)]

    var detailText: String {
        let items = marks.map { "\($0.name) \($0.milliseconds)ms" }.joined(separator: " · ")
        return items.isEmpty ? "\(totalMilliseconds)ms" : "\(totalMilliseconds)ms · \(items)"
    }
}

final class LaunchPerformanceTracker {
    static let shared = LaunchPerformanceTracker()

    private let lock = NSLock()
    private let startTime: TimeInterval
    private var marks: [(name: String, milliseconds: Int)] = []
    private var finishedSnapshot: LaunchPerformanceSnapshot?

    init(startTime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        self.startTime = startTime
    }

    func mark(_ name: String, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        let elapsed = elapsedMilliseconds(now: now)
        lock.lock()
        marks.append((name: name, milliseconds: elapsed))
        lock.unlock()
    }

    @discardableResult
    func finish(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> LaunchPerformanceSnapshot {
        let elapsed = elapsedMilliseconds(now: now)
        lock.lock()
        let snapshot = LaunchPerformanceSnapshot(totalMilliseconds: elapsed, marks: marks)
        finishedSnapshot = snapshot
        lock.unlock()
        NSLog("LeafReader launch performance: %@", snapshot.detailText)
        return snapshot
    }

    func snapshot() -> LaunchPerformanceSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return finishedSnapshot
    }

    private func elapsedMilliseconds(now: TimeInterval) -> Int {
        max(0, Int(((now - startTime) * 1000).rounded()))
    }
}
