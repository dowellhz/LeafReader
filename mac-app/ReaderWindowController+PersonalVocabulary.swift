import Foundation

extension ReaderWindowController {
    func recordPersonalVocabularyExposureForCurrentPosition() {
        guard let documentID = currentFileMD5 else { return }
        if currentDocumentKind == .pdf {
            recordPersonalVocabularyPDFExposure(documentID: documentID)
            return
        }
        recordPersonalVocabularyWebExposure(documentID: documentID)
    }

    func recordPersonalVocabularyQuery(_ text: String) {
        PersonalVocabularyProfileStore.shared.recordQuery(text: text)
    }

    private func recordPersonalVocabularyPDFExposure(documentID: String) {
        guard let pageIndex = currentPDFViewportAnchor()?.pageIndex ?? currentPageIndex(),
              pageIndex != lastPersonalVocabularyPDFPageIndex,
              let text = pdfView.document?.page(at: pageIndex)?.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        lastPersonalVocabularyPDFPageIndex = pageIndex
        DispatchQueue.global(qos: .utility).async {
            PersonalVocabularyProfileStore.shared.recordExposure(documentID: documentID, text: text)
        }
    }

    private func recordPersonalVocabularyWebExposure(documentID: String) {
        let bucket = PersonalVocabularyExposurePolicy.webProgressBucket(webScrollProgress)
        guard bucket != lastPersonalVocabularyWebProgressBucket else { return }
        let text = ReaderAIContextBuilder.webProgressTextWindow(
            plainText: currentWebPlainText,
            progress: webScrollProgress
        )
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        lastPersonalVocabularyWebProgressBucket = bucket
        DispatchQueue.global(qos: .utility).async {
            PersonalVocabularyProfileStore.shared.recordExposure(documentID: documentID, text: text)
        }
    }
}
