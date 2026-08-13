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
        guard let store = pdfWordRecordStore else { return }
        let fallbackRecords = storedWordRecords
        VocabularyPersistenceQueue.enqueue {
            guard !store.upsert(record) else { return }
            if !store.save(fallbackRecords) {
                NSLog("LeafReader vocabulary: failed to persist a PDF word record and its fallback snapshot")
            }
        }
    }

    func loadStoredWebWordRecords() -> [StoredWebWordRecord] {
        webWordRecordStore?.load() ?? []
    }

    func saveStoredWebWordRecords() {
        scheduleStoredWebWordRecordsSave()
    }

    func saveStoredWebWordRecord(_ record: StoredWebWordRecord) {
        guard let store = webWordRecordStore else { return }
        let fallbackRecords = storedWebWordRecords
        VocabularyPersistenceQueue.enqueue {
            guard !store.upsert(record) else { return }
            if !store.save(fallbackRecords) {
                NSLog("LeafReader vocabulary: failed to persist a web word record and its fallback snapshot")
            }
        }
    }

    func deleteStoredWordRecords(ids: [String]) {
        guard let store = pdfWordRecordStore else { return }
        let fallbackRecords = storedWordRecords
        VocabularyPersistenceQueue.enqueue {
            guard !store.delete(ids: ids) else { return }
            if !store.save(fallbackRecords) {
                NSLog("LeafReader vocabulary: failed to delete PDF word records and persist the fallback snapshot")
            }
        }
    }

    func deleteStoredWebWordRecords(ids: [String]) {
        guard let store = webWordRecordStore else { return }
        let fallbackRecords = storedWebWordRecords
        VocabularyPersistenceQueue.enqueue {
            guard !store.delete(ids: ids) else { return }
            if !store.save(fallbackRecords) {
                NSLog("LeafReader vocabulary: failed to delete web word records and persist the fallback snapshot")
            }
        }
    }

    @discardableResult
    func updateStoredVocabularyRecords(
        ids: Set<String>,
        updatePDF: (inout StoredPDFWordRecord) -> Bool,
        updateWeb: (inout StoredWebWordRecord) -> Bool
    ) -> VocabularyRecordMutationResult {
        var updatedPDFRecords: [StoredPDFWordRecord] = []
        for index in storedWordRecords.indices where ids.contains(storedWordRecords[index].id) {
            guard updatePDF(&storedWordRecords[index]) else { continue }
            updatedPDFRecords.append(storedWordRecords[index])
        }
        if !updatedPDFRecords.isEmpty, let store = pdfWordRecordStore {
            let recordsToUpdate = updatedPDFRecords
            let fallbackRecords = storedWordRecords
            VocabularyPersistenceQueue.enqueue {
                guard !store.upsert(recordsToUpdate) else { return }
                if !store.save(fallbackRecords) {
                    NSLog("LeafReader vocabulary: failed to batch-update PDF word records and persist the fallback snapshot")
                }
            }
        }

        var updatedWebRecords: [StoredWebWordRecord] = []
        for index in storedWebWordRecords.indices where ids.contains(storedWebWordRecords[index].id) {
            guard updateWeb(&storedWebWordRecords[index]) else { continue }
            updatedWebRecords.append(storedWebWordRecords[index])
        }
        if !updatedWebRecords.isEmpty, let store = webWordRecordStore {
            let recordsToUpdate = updatedWebRecords
            let fallbackRecords = storedWebWordRecords
            VocabularyPersistenceQueue.enqueue {
                guard !store.upsert(recordsToUpdate) else { return }
                if !store.save(fallbackRecords) {
                    NSLog("LeafReader vocabulary: failed to batch-update web word records and persist the fallback snapshot")
                }
            }
        }

        return VocabularyRecordMutationResult(
            didUpdatePDF: !updatedPDFRecords.isEmpty,
            didUpdateWeb: !updatedWebRecords.isEmpty
        )
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
        guard let store = pdfWordRecordStore else { return }
        let records = storedWordRecords
        VocabularyPersistenceQueue.enqueue {
            if !store.save(records) {
                NSLog("LeafReader vocabulary: failed to persist the PDF word-record snapshot")
            }
        }
    }

    func flushStoredWebWordRecordsSave() {
        webWordRecordsSaveTask.cancel()
        guard let store = webWordRecordStore else { return }
        let records = storedWebWordRecords
        VocabularyPersistenceQueue.enqueue {
            if !store.save(records) {
                NSLog("LeafReader vocabulary: failed to persist the web word-record snapshot")
            }
        }
    }

    func flushCurrentBookWordRecordSaves(waitForCompletion: Bool = false) {
        flushStoredWordRecordsSave()
        flushStoredWebWordRecordsSave()
        if waitForCompletion {
            VocabularyPersistenceQueue.waitForPendingWrites()
        }
    }
}
