import Cocoa
import PDFKit

private enum PDFMarginCropPolicy {
    static let horizontalInsetRatio: CGFloat = 0.045
    static let verticalInsetRatio: CGFloat = 0.025
    static let minimumWidth: CGFloat = 120
    static let minimumHeight: CGFloat = 160
}

extension ReaderWindowController {
    @objc func togglePDFMarginCrop() {
        guard currentDocumentKind == .pdf else { return }
        let nextValue = !isPDFMarginCropEnabled()
        setPDFMarginCropEnabled(nextValue)
        applyPDFMarginCropIfNeeded()
        updatePDFMarginCropButton()
        saveSession()
        window?.makeFirstResponder(pdfView)
    }

    func updatePDFMarginCropButton() {
        let enabled = isPDFMarginCropEnabled()
        cropButton?.title = enabled
            ? AppText.localized("原边", "Original")
            : AppText.localized("裁边", "Crop")
        cropButton?.toolTip = enabled
            ? AppText.localized("恢复 PDF 原始页面边距", "Restore original PDF page margins")
            : AppText.localized("裁掉 PDF 页面外侧空白", "Crop outer PDF margins")
    }

    func captureOriginalPDFCropBoxes() {
        originalPDFCropBoxes.removeAll()
        guard let document = pdfView.document else { return }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            originalPDFCropBoxes[index] = page.bounds(for: .cropBox)
        }
    }

    func applyPDFMarginCropIfNeeded() {
        guard currentDocumentKind == .pdf,
              let document = pdfView.document else {
            return
        }
        if isPDFMarginCropEnabled() {
            applyTightPDFCrop(to: document)
        } else {
            restoreOriginalPDFCropBoxes(in: document)
        }
        pdfView.layoutDocumentView()
        pdfView.needsDisplay = true
        pdfView.documentView?.needsDisplay = true
    }

    func applyTightPDFCrop(to document: PDFDocument) {
        if originalPDFCropBoxes.isEmpty {
            captureOriginalPDFCropBoxes()
        }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let originalBounds = originalPDFCropBoxes[index] ?? page.bounds(for: .cropBox)
            let croppedBounds = croppedPDFBounds(from: originalBounds)
            page.setBounds(croppedBounds, for: .cropBox)
        }
    }

    func restoreOriginalPDFCropBoxes(in document: PDFDocument) {
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index),
                  let originalBounds = originalPDFCropBoxes[index] else {
                continue
            }
            page.setBounds(originalBounds, for: .cropBox)
        }
    }

    func croppedPDFBounds(from bounds: CGRect) -> CGRect {
        let dx = bounds.width * PDFMarginCropPolicy.horizontalInsetRatio
        let dy = bounds.height * PDFMarginCropPolicy.verticalInsetRatio
        let cropped = bounds.insetBy(dx: dx, dy: dy)
        guard cropped.width >= PDFMarginCropPolicy.minimumWidth,
              cropped.height >= PDFMarginCropPolicy.minimumHeight else {
            return bounds
        }
        return cropped
    }

    func isPDFMarginCropEnabled() -> Bool {
        let defaults = UserDefaults.standard
        let key = pdfMarginCropDefaultsKeyForCurrentBook()
        if defaults.object(forKey: key) != nil {
            return defaults.bool(forKey: key)
        }
        return defaults.bool(forKey: Self.pdfMarginCropDefaultsKey)
    }

    func setPDFMarginCropEnabled(_ enabled: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(enabled, forKey: pdfMarginCropDefaultsKeyForCurrentBook())
        defaults.set(enabled, forKey: Self.pdfMarginCropDefaultsKey)
    }

    func pdfMarginCropDefaultsKeyForCurrentBook() -> String {
        guard let currentFileMD5, !currentFileMD5.isEmpty else {
            return Self.pdfMarginCropDefaultsKey
        }
        return "\(Self.pdfMarginCropDefaultsKey).\(currentFileMD5)"
    }
}
