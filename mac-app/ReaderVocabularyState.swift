import Foundation

struct ReaderVocabularyState {
    var storedWordRecords: [StoredPDFWordRecord] = []
    var pendingPDFWordRecords: [String: ReaderWindowController.PendingPDFWordRecord] = [:]
    var pdfWordRecordStore: PDFWordRecordStore?
    var storedWebWordRecords: [StoredWebWordRecord] = []
    var pendingWebWordRecords: [String: ReaderWindowController.PendingWebWordRecord] = [:]
    var webWordRecordStore: WebWordRecordStore?
    var currentExportRecords: [VocabularyExportRecord] = []
}
