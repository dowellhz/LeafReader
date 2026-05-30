import Foundation

extension ReaderWindowController {
    var storedWordRecords: [StoredPDFWordRecord] {
        get { vocabularyState.storedWordRecords }
        set { vocabularyState.storedWordRecords = newValue }
    }

    var pendingPDFWordRecords: [String: PendingPDFWordRecord] {
        get { vocabularyState.pendingPDFWordRecords }
        set { vocabularyState.pendingPDFWordRecords = newValue }
    }

    var pdfWordRecordStore: PDFWordRecordStore? {
        get { vocabularyState.pdfWordRecordStore }
        set { vocabularyState.pdfWordRecordStore = newValue }
    }

    var storedWebWordRecords: [StoredWebWordRecord] {
        get { vocabularyState.storedWebWordRecords }
        set { vocabularyState.storedWebWordRecords = newValue }
    }

    var pendingWebWordRecords: [String: PendingWebWordRecord] {
        get { vocabularyState.pendingWebWordRecords }
        set { vocabularyState.pendingWebWordRecords = newValue }
    }

    var webWordRecordStore: WebWordRecordStore? {
        get { vocabularyState.webWordRecordStore }
        set { vocabularyState.webWordRecordStore = newValue }
    }

    var currentVocabularyExportRecords: [VocabularyExportRecord] {
        get { vocabularyState.currentExportRecords }
        set { vocabularyState.currentExportRecords = newValue }
    }
}
