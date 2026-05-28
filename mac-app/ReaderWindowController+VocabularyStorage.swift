import Cocoa

struct VocabularyRecordMutationResult {
    let didUpdatePDF: Bool
    let didUpdateWeb: Bool

    var didUpdate: Bool {
        didUpdatePDF || didUpdateWeb
    }
}

extension ReaderWindowController {
    func loadStoredWordRecords() -> [StoredPDFWordRecord] {
        pdfWordRecordStore?.load() ?? []
    }

    func saveStoredWordRecords() {
        scheduleStoredWordRecordsSave()
    }

    func saveStoredWordRecord(_ record: StoredPDFWordRecord) {
        if pdfWordRecordStore?.upsert(record) != true {
            saveStoredWordRecords()
        }
    }

    func loadStoredWebWordRecords() -> [StoredWebWordRecord] {
        webWordRecordStore?.load() ?? []
    }

    func saveStoredWebWordRecords() {
        scheduleStoredWebWordRecordsSave()
    }

    func saveStoredWebWordRecord(_ record: StoredWebWordRecord) {
        if webWordRecordStore?.upsert(record) != true {
            saveStoredWebWordRecords()
        }
    }

    func deleteStoredWordRecords(ids: [String]) {
        if pdfWordRecordStore?.delete(ids: ids) != true {
            saveStoredWordRecords()
        }
    }

    func deleteStoredWebWordRecords(ids: [String]) {
        if webWordRecordStore?.delete(ids: ids) != true {
            saveStoredWebWordRecords()
        }
    }

    @discardableResult
    func updateStoredVocabularyRecords(
        ids: Set<String>,
        updatePDF: (inout StoredPDFWordRecord) -> Bool,
        updateWeb: (inout StoredWebWordRecord) -> Bool
    ) -> VocabularyRecordMutationResult {
        var didUpdatePDF = false
        for index in storedWordRecords.indices where ids.contains(storedWordRecords[index].id) {
            guard updatePDF(&storedWordRecords[index]) else { continue }
            saveStoredWordRecord(storedWordRecords[index])
            didUpdatePDF = true
        }
        if didUpdatePDF {
            saveStoredWordRecords()
        }

        var didUpdateWeb = false
        for index in storedWebWordRecords.indices where ids.contains(storedWebWordRecords[index].id) {
            guard updateWeb(&storedWebWordRecords[index]) else { continue }
            saveStoredWebWordRecord(storedWebWordRecords[index])
            didUpdateWeb = true
        }
        if didUpdateWeb {
            saveStoredWebWordRecords()
        }

        return VocabularyRecordMutationResult(didUpdatePDF: didUpdatePDF, didUpdateWeb: didUpdateWeb)
    }

    func scheduleStoredWordRecordsSave() {
        pdfWordRecordsSaveTask.schedule { [weak self] in
            self?.flushStoredWordRecordsSave()
        }
    }

    func scheduleStoredWebWordRecordsSave() {
        webWordRecordsSaveTask.schedule { [weak self] in
            self?.flushStoredWebWordRecordsSave()
        }
    }

    func flushStoredWordRecordsSave() {
        pdfWordRecordsSaveTask.cancel()
        pdfWordRecordStore?.save(storedWordRecords)
    }

    func flushStoredWebWordRecordsSave() {
        webWordRecordsSaveTask.cancel()
        webWordRecordStore?.save(storedWebWordRecords)
    }

    func flushCurrentBookWordRecordSaves() {
        flushStoredWordRecordsSave()
        flushStoredWebWordRecordsSave()
    }
}
