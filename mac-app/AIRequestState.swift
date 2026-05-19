import Cocoa

final class AIRequestState {
    private(set) var activeID: UUID?
    var currentStreamTask: Task<Void, Never>?
    var currentDataTask: URLSessionDataTask?
    private var cancelledIDs = Set<UUID>()
    weak var assistantBody: NSTextField?

    func begin(id: UUID, assistantBody: NSTextField? = nil) {
        activeID = id
        currentStreamTask = nil
        currentDataTask = nil
        self.assistantBody = assistantBody
    }

    func isActive(_ id: UUID) -> Bool {
        activeID == id
    }

    func shouldHandleCompletion(for id: UUID) -> Bool {
        activeID == id || cancelledIDs.contains(id)
    }

    func consumeCancellation(for id: UUID) -> Bool {
        cancelledIDs.remove(id) != nil
    }

    func finish(id: UUID? = nil) {
        guard id == nil || activeID == id else { return }
        activeID = nil
        currentStreamTask = nil
        currentDataTask = nil
        assistantBody = nil
    }

    func cancelActive() -> NSTextField? {
        if let activeID {
            cancelledIDs.insert(activeID)
        }
        let body = assistantBody
        activeID = nil
        currentStreamTask?.cancel()
        currentStreamTask = nil
        currentDataTask?.cancel()
        currentDataTask = nil
        assistantBody = nil
        return body
    }

    func cancelTasks() {
        currentStreamTask?.cancel()
        currentStreamTask = nil
        currentDataTask?.cancel()
        currentDataTask = nil
    }
}
