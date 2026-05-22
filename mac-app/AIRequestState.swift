import Cocoa

final class AIRequestState {
    private(set) var activeID: UUID?
    var currentStreamTask: Task<Void, Never>?
    var currentDataTask: URLSessionDataTask?
    private var cancelledID: UUID?
    weak var assistantBody: NSTextField?

    func begin(id: UUID, assistantBody: NSTextField? = nil) {
        cancelledID = nil
        activeID = id
        currentStreamTask = nil
        currentDataTask = nil
        self.assistantBody = assistantBody
    }

    func isActive(_ id: UUID) -> Bool {
        activeID == id
    }

    func shouldHandleCompletion(for id: UUID) -> Bool {
        activeID == id || cancelledID == id
    }

    func consumeCancellation(for id: UUID) -> Bool {
        guard cancelledID == id else { return false }
        cancelledID = nil
        return true
    }

    func finish(id: UUID? = nil) {
        guard id == nil || activeID == id else { return }
        if id == nil || cancelledID == id {
            cancelledID = nil
        }
        activeID = nil
        currentStreamTask = nil
        currentDataTask = nil
        assistantBody = nil
    }

    func cancelActive() -> NSTextField? {
        cancelledID = activeID
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
