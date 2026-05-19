import Cocoa

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
