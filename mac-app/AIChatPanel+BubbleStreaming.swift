import Cocoa

extension AIChatPanel {
    func scheduleStreamUpdate(_ body: NSTextField, text: String) {
        pendingStreamText = text
        let minimumInterval: TimeInterval = 0.10
        let elapsed = Date().timeIntervalSince(lastStreamUpdateAt)
        if streamUpdateWorkItem == nil, elapsed >= minimumInterval {
            applyPendingStreamUpdate(body)
            return
        }
        guard streamUpdateWorkItem == nil else { return }
        let delay = max(0, minimumInterval - elapsed)
        let workItem = DispatchWorkItem { [weak self, weak body] in
            guard let self, let body else { return }
            guard self.streamUpdateWorkItem?.isCancelled == false else {
                self.streamUpdateWorkItem = nil
                return
            }
            self.streamUpdateWorkItem = nil
            self.applyPendingStreamUpdate(body)
        }
        streamUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func flushStreamUpdate(_ body: NSTextField?) {
        streamUpdateWorkItem?.cancel()
        streamUpdateWorkItem = nil
        guard let body, !pendingStreamText.isEmpty else { return }
        applyPendingStreamUpdate(body)
    }

    private func applyPendingStreamUpdate(_ body: NSTextField) {
        guard !pendingStreamText.isEmpty else { return }
        lastStreamUpdateAt = Date()
        updateBubble(body, role: AppText.aiRole, text: pendingStreamText, renderMarkdown: false, notify: false)
    }
}
