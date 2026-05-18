import Cocoa

extension AIChatPanel {
    func installInteractionMonitor() {
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            if self.shouldPreserveSelection(for: event) {
                self.preserveActiveBubbleSelection()
            } else {
                self.clearSelectionForNonPreservingInteraction()
            }
            let point = self.convert(event.locationInWindow, from: nil)
            if self.bounds.contains(point) {
                self.ignoreEmptySelectionUntil = Date().addingTimeInterval(1.5)
            }
            return event
        }
    }

    func shouldPreserveSelection(for event: NSEvent) -> Bool {
        isMouseEvent(event, inside: inputBar)
            || isMouseEvent(event, inside: sendButton)
            || [askButton, summaryButton, translateButton].contains { isMouseEvent(event, inside: $0) }
    }

    func isMouseEvent(_ event: NSEvent, inside view: NSView) -> Bool {
        let point = view.convert(event.locationInWindow, from: nil)
        return view.bounds.contains(point)
    }

    func preserveActiveBubbleSelection() {
        guard let bubble = activeBubbleTextField,
              activeBubbleSelectionRange != nil else { return }
        let selected = activeBubbleSelectedText
        guard !selected.isEmpty else { return }
        setSelectedBubbleText(selected)
        restoreBubbleRendering(bubble)
    }

    func clearSelectionForNonPreservingInteraction() {
        clearActiveBubbleSelection(restoreRendering: true, clearSelectedTextState: false)
        updateSelectedText("")
        onNonFollowUpSelectionInteraction?()
    }

    func clearActiveBubbleSelection(restoreRendering: Bool, clearSelectedTextState: Bool = true) {
        guard let bubble = activeBubbleTextField else { return }
        bubble.clearTextSelection()
        activeBubbleSelectionRange = nil
        activeBubbleSelectedText = ""
        if restoreRendering {
            restoreBubbleRendering(bubble)
        }
        activeBubbleTextField = nil
        if clearSelectedTextState {
            updateSelectedText("")
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if let bubble = obj.object as? ChatBubbleTextField {
            if captureBubbleSelection(from: bubble) {
                return
            }
            if activeBubbleTextField === bubble,
               activeBubbleSelectionRange != nil,
               !activeBubbleSelectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                setSelectedBubbleText(activeBubbleSelectedText)
                restoreBubbleRendering(bubble)
                return
            }
            restoreBubbleRendering(bubble)
            if activeBubbleTextField === bubble {
                activeBubbleSelectionRange = nil
                activeBubbleSelectedText = ""
                activeBubbleTextField = nil
            }
            return
        }

        guard obj.object as? NSTextField === inputField else { return }
        isEditingFollowUp = false
        if let movement = obj.userInfo?["NSTextMovement"] as? Int, movement == NSReturnTextMovement {
            sendFollowUp()
        }
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        if let bubble = obj.object as? ChatBubbleTextField {
            activeBubbleTextField = bubble
            return
        }

        guard obj.object as? NSTextField === inputField else { return }
        isEditingFollowUp = true
    }

}
