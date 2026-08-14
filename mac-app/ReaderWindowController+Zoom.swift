import Cocoa

extension ReaderWindowController {
    @objc func zoomIn() {
        markReaderInteraction()
        guard let applied = activeReaderBackend?.stepZoom(.increment) else { return }
        syncZoomPercentFromBackend(applied)
        updateZoomLabel()
        saveSession()
    }

    @objc func zoomOut() {
        markReaderInteraction()
        guard let applied = activeReaderBackend?.stepZoom(.decrement) else { return }
        syncZoomPercentFromBackend(applied)
        updateZoomLabel()
        saveSession()
    }

    @objc func applyZoomFromField() {
        markReaderInteraction()
        let raw = zoomField.stringValue
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "％", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let percent = Double(raw), percent > 0,
              let applied = activeReaderBackend?.setZoomPercent(Int(percent.rounded())) else {
            updateZoomLabel()
            return
        }
        syncZoomPercentFromBackend(applied)
        updateZoomLabel()
        saveSession()
        activeReaderBackend?.focus()
    }

    func setWebZoom(_ percent: Int) {
        guard let applied = webReaderBackend.setZoomPercent(percent) else { return }
        webZoomPercent = applied
        zoomField.stringValue = "\(webZoomPercent)%"
        saveSession()
        webReaderBackend.focus()
    }

    func applyWebZoomToPage() {
        _ = webReaderBackend.setZoomPercent(webZoomPercent)
    }

    private func syncZoomPercentFromBackend(_ percent: Int) {
        guard currentDocumentKind != .pdf else { return }
        webZoomPercent = percent
        zoomField.stringValue = "\(webZoomPercent)%"
    }
}
