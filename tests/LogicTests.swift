import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw TestFailure(description: message)
    }
}

func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) throws {
    if lhs != rhs {
        throw TestFailure(description: "\(message). expected \(rhs), got \(lhs)")
    }
}

private final class DebouncedTask {
    private let delay: TimeInterval
    private var workItem: DispatchWorkItem?
    private var pendingAction: (() -> Void)?

    init(delay: TimeInterval) {
        self.delay = delay
    }

    func schedule(_ action: @escaping () -> Void) {
        workItem?.cancel()
        pendingAction = action
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let action = self.pendingAction else { return }
            self.workItem = nil
            self.pendingAction = nil
            action()
        }
        self.workItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func flush() {
        guard let action = pendingAction else { return }
        workItem?.cancel()
        workItem = nil
        pendingAction = nil
        action()
    }

    func cancel() {
        workItem?.cancel()
        workItem = nil
        pendingAction = nil
    }
}

private struct VocabularySRSState {
    var easeFactor: Double
    var intervalDays: Int
    var repetition: Int
    var dueDate: Date
    var lastReviewedAt: Date?
    var reviewCount: Int
    var lapseCount: Int
    var activeRecallStreak: Int?
    var masteredAt: Date?

    static func initial(createdAt: Date = Date()) -> VocabularySRSState {
        VocabularySRSState(
            easeFactor: 2.5,
            intervalDays: 0,
            repetition: 0,
            dueDate: createdAt,
            lastReviewedAt: nil,
            reviewCount: 0,
            lapseCount: 0,
            activeRecallStreak: 0,
            masteredAt: nil
        )
    }

    var isDue: Bool {
        dueDate <= Date()
    }

    var isMastered: Bool {
        (activeRecallStreak ?? 0) >= 3 && intervalDays >= 7 && !isDue
    }

    func reviewed(grade: Int, at date: Date = Date()) -> VocabularySRSState {
        let boundedGrade = min(max(grade, 1), 4)
        let wasMastered = isMastered
        var next = self
        next.reviewCount += 1
        next.lastReviewedAt = date

        if boundedGrade == 1 {
            next.repetition = 0
            next.intervalDays = 0
            next.lapseCount += 1
            next.activeRecallStreak = 0
            next.masteredAt = nil
            next.easeFactor = max(1.3, next.easeFactor - 0.25)
            next.dueDate = Calendar.current.date(byAdding: .minute, value: 10, to: date) ?? date
            return next
        }

        let intervals = boundedGrade == 2
            ? [1, 2, 4, 7, 15]
            : [1, 3, 7, 15, 30]
        let baseInterval = next.repetition < intervals.count
            ? intervals[next.repetition]
            : Int((Double(max(1, next.intervalDays)) * next.easeFactor).rounded())
        next.intervalDays = max(1, baseInterval)
        next.repetition += 1
        if boundedGrade >= 3 {
            next.activeRecallStreak = (next.activeRecallStreak ?? 0) + 1
        } else {
            next.activeRecallStreak = 0
        }
        next.easeFactor = max(1.3, next.easeFactor + next.easeDelta(for: boundedGrade))
        next.dueDate = Calendar.current.date(byAdding: .day, value: next.intervalDays, to: date) ?? date
        if !wasMastered && next.isMastered {
            next.masteredAt = date
        }
        return next
    }

    private func easeDelta(for grade: Int) -> Double {
        let q: Double
        switch grade {
        case 2:
            q = 3
        case 4:
            q = 5
        default:
            q = 4
        }
        return 0.1 - (5 - q) * (0.08 + (5 - q) * 0.02)
    }
}

private struct RecentDocumentItem {
    let path: String
    let title: String
    let openedAt: Date
}

private struct StoredWordRecord: Equatable {
    let id: String
    var answer: String
    var srsReviewCount: Int
}

private struct InMemoryWordRecordStore {
    var sqliteRecords: [String: StoredWordRecord] = [:]
    var legacyRecords: [StoredWordRecord] = []
    var didMigrate = false

    mutating func load() -> [StoredWordRecord] {
        if !sqliteRecords.isEmpty {
            return sqliteRecords.values.sorted { $0.id < $1.id }
        }
        if didMigrate {
            return []
        }
        if !legacyRecords.isEmpty {
            for record in legacyRecords {
                sqliteRecords[record.id] = record
            }
            didMigrate = true
            return legacyRecords
        }
        return []
    }

    mutating func save(_ records: [StoredWordRecord]) {
        sqliteRecords = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        didMigrate = true
    }

    mutating func upsert(_ record: StoredWordRecord) {
        sqliteRecords[record.id] = record
        didMigrate = true
    }

    mutating func delete(ids: [String]) {
        for id in ids {
            sqliteRecords.removeValue(forKey: id)
        }
        didMigrate = true
    }
}

private func supportedUniquePaths(_ paths: [String]) -> [String] {
    var results: [String] = []
    var seen = Set<String>()
    for path in paths {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        guard ["pdf", "epub", "docx"].contains(ext), !seen.contains(path) else { continue }
        seen.insert(path)
        results.append(path)
    }
    return results
}

private func importedFrontPaths(existing: [RecentDocumentItem], droppedPaths: [String]) -> [String] {
    var existingItemsByPath: [String: RecentDocumentItem] = [:]
    for item in existing where existingItemsByPath[item.path] == nil {
        existingItemsByPath[item.path] = item
    }
    var frontPaths: [String] = []
    for path in supportedUniquePaths(droppedPaths) {
        if existingItemsByPath[path] != nil {
            frontPaths.append(path)
        } else {
            frontPaths.append(path)
        }
    }
    return frontPaths
}

private func storedPathsAfterImport(existing: [RecentDocumentItem], droppedPaths: [String]) -> [String] {
    var items = existing
    var existingItemsByPath: [String: RecentDocumentItem] = [:]
    for item in items where existingItemsByPath[item.path] == nil {
        existingItemsByPath[item.path] = item
    }
    for path in supportedUniquePaths(droppedPaths) where existingItemsByPath[path] == nil {
        items.append(RecentDocumentItem(
            path: path,
            title: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
            openedAt: .distantPast
        ))
        existingItemsByPath[path] = items.last
    }
    return items.map(\.path)
}

private enum DroppedDocumentAction: Equatable {
    case none
    case openSingle(String)
    case showShelf(priorityPaths: [String])
}

private func droppedDocumentAction(paths: [String]) -> DroppedDocumentAction {
    let supportedDropCount = paths.filter { ["pdf", "epub", "docx"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }.count
    let supported = supportedUniquePaths(paths)
    if supportedDropCount == 1, supported.count == 1 {
        return .openSingle(supported[0])
    }
    if supportedDropCount > 1, !supported.isEmpty {
        return .showShelf(priorityPaths: supported)
    }
    return .none
}

private func sortedRecentDocuments(_ items: [RecentDocumentItem], priorityPaths: [String]) -> [RecentDocumentItem] {
    guard !priorityPaths.isEmpty else {
        return items.sorted {
            if $0.openedAt != $1.openedAt {
                return $0.openedAt > $1.openedAt
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    var priorityIndex: [String: Int] = [:]
    for (index, path) in priorityPaths.enumerated() where priorityIndex[path] == nil {
        priorityIndex[path] = index
    }
    return items.sorted { lhs, rhs in
        let lhsPriority = priorityIndex[lhs.path]
        let rhsPriority = priorityIndex[rhs.path]
        switch (lhsPriority, rhsPriority) {
        case let (.some(left), .some(right)):
            return left < right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            if lhs.openedAt != rhs.openedAt {
                return lhs.openedAt > rhs.openedAt
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}

private struct EmbeddingEndpointOption {
    let id: String
    let endpoint: String
    let defaultModel: String
    let requiresAPIKey: Bool
    let payloadExtras: [String: String]

    init(id: String, endpoint: String, defaultModel: String, requiresAPIKey: Bool = true, payloadExtras: [String: String] = [:]) {
        self.id = id
        self.endpoint = endpoint
        self.defaultModel = defaultModel
        self.requiresAPIKey = requiresAPIKey
        self.payloadExtras = payloadExtras
    }
}

private let embeddingOptions = [
    EmbeddingEndpointOption(id: "openai", endpoint: "https://api.openai.com/v1/embeddings", defaultModel: "text-embedding-3-small"),
    EmbeddingEndpointOption(id: "siliconflow", endpoint: "https://api.siliconflow.cn/v1/embeddings", defaultModel: "Qwen/Qwen3-Embedding-8B", payloadExtras: ["encoding_format": "float"]),
    EmbeddingEndpointOption(id: "ollama", endpoint: "http://127.0.0.1:11434/api/embed", defaultModel: "nomic-embed-text", requiresAPIKey: false),
    EmbeddingEndpointOption(id: "other", endpoint: "", defaultModel: "")
]

private func selectedEmbeddingOption(savedEndpoint: String) -> EmbeddingEndpointOption {
    if let option = embeddingOptions.first(where: { $0.endpoint == savedEndpoint }) {
        return option
    }
    if savedEndpoint == "https://api.siliconflow.com/v1/embeddings" {
        return embeddingOptions.first { $0.id == "siliconflow" }!
    }
    let requiresKey = !(URL(string: savedEndpoint)?.isLocalEndpoint ?? false)
    return EmbeddingEndpointOption(id: "other", endpoint: savedEndpoint, defaultModel: "", requiresAPIKey: requiresKey)
}

private func embeddingModelName(savedModel: String, savedEndpoint: String) -> String {
    if !savedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return savedModel
    }
    let defaultModel = selectedEmbeddingOption(savedEndpoint: savedEndpoint).defaultModel
    return defaultModel.isEmpty ? "text-embedding-3-small" : defaultModel
}

private func embeddingPayload(option: EmbeddingEndpointOption, model: String, input: [String]) -> [String: Any] {
    var payload: [String: Any] = ["model": model, "input": input]
    for (key, value) in option.payloadExtras {
        payload[key] = value
    }
    return payload
}

private enum ScrollPageDirection: Equatable {
    case previous
    case next
}

private func pageDirectionAtEdge(deltaY: Double, isAtTop: Bool, isAtBottom: Bool) -> ScrollPageDirection? {
    if isAtTop, deltaY > 0 {
        return .previous
    }
    if isAtBottom, deltaY < 0 {
        return .next
    }
    return nil
}

private func shouldApplyCapturedPageScroll(capturedPageIndex: Int, documentPageCount: Int) -> Bool {
    capturedPageIndex >= 0 && capturedPageIndex < documentPageCount
}

private struct EmbeddingKeyStore {
    var encryptedKeys: [String: String] = [:]
    var legacyPlainKeys: [String: String] = [:]

    mutating func saveEmbeddingKey(_ key: String, optionID: String) {
        let storageKey = encryptedProviderKey(for: optionID)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            encryptedKeys.removeValue(forKey: storageKey)
        } else {
            encryptedKeys[storageKey] = trimmed
        }
        legacyPlainKeys.removeValue(forKey: "apiKey.embedding")
    }

    func embeddingKey(for optionID: String) -> String {
        encryptedKeys[encryptedProviderKey(for: optionID)] ?? ""
    }

    mutating func embeddingKeyMigratingLegacyIfNeeded(for optionID: String) -> String {
        let storageKey = encryptedProviderKey(for: optionID)
        if let key = encryptedKeys[storageKey], !key.isEmpty {
            return key
        }
        if let legacyEncrypted = encryptedKeys["encryptedApiKey.embedding"], !legacyEncrypted.isEmpty {
            encryptedKeys[storageKey] = legacyEncrypted
            encryptedKeys.removeValue(forKey: "encryptedApiKey.embedding")
            return legacyEncrypted
        }
        if let legacyPlain = legacyPlainKeys["apiKey.embedding"], !legacyPlain.isEmpty {
            encryptedKeys[storageKey] = legacyPlain
            legacyPlainKeys.removeValue(forKey: "apiKey.embedding")
            return legacyPlain
        }
        return ""
    }

    private func encryptedProviderKey(for optionID: String) -> String {
        "encryptedApiKey.embedding.\(optionID)"
    }
}

private extension URL {
    var isLocalEndpoint: Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}

private func testVocabularySRS() throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let initial = VocabularySRSState.initial(createdAt: date)

    let failed = initial.reviewed(grade: 1, at: date)
    try expectEqual(failed.intervalDays, 0, "failed review should stay same-day")
    try expectEqual(failed.repetition, 0, "failed review resets repetition")
    try expectEqual(failed.lapseCount, 1, "failed review increments lapse count")
    try expect(failed.dueDate > date, "failed review schedules short retry")

    let remembered = initial.reviewed(grade: 3, at: date)
    try expectEqual(remembered.intervalDays, 1, "first remembered review schedules one day")
    try expectEqual(remembered.repetition, 1, "remembered review increments repetition")
    try expectEqual(remembered.activeRecallStreak, 1, "remembered review increments recall streak")
}

private func testRecentDocumentSortingAndImport() throws {
    let old = Date(timeIntervalSince1970: 100)
    let mid = Date(timeIntervalSince1970: 200)
    let recent = Date(timeIntervalSince1970: 300)
    let items = [
        RecentDocumentItem(path: "/books/old.pdf", title: "Old", openedAt: old),
        RecentDocumentItem(path: "/books/recent.pdf", title: "Recent", openedAt: recent),
        RecentDocumentItem(path: "/books/mid.pdf", title: "Mid", openedAt: mid)
    ]

    try expectEqual(sortedRecentDocuments(items, priorityPaths: []).map(\.path), ["/books/recent.pdf", "/books/mid.pdf", "/books/old.pdf"], "plain shelf sorting should use recent reading")
    try expectEqual(sortedRecentDocuments(items, priorityPaths: ["/books/old.pdf", "/books/mid.pdf"]).map(\.path), ["/books/old.pdf", "/books/mid.pdf", "/books/recent.pdf"], "open shelf import should prioritize dropped paths")

    let frontPaths = importedFrontPaths(existing: items, droppedPaths: ["/books/old.pdf", "/books/new.epub", "/books/old.pdf", "/books/skip.txt"])
    try expectEqual(frontPaths, ["/books/old.pdf", "/books/new.epub"], "import should dedupe and ignore unsupported files")
    try expectEqual(storedPathsAfterImport(existing: items, droppedPaths: ["/books/old.pdf", "/books/new.epub", "/books/new.epub"]), ["/books/old.pdf", "/books/recent.pdf", "/books/mid.pdf", "/books/new.epub"], "import should not duplicate existing books and should append new books for later recent sorting")
}

private func testDroppedDocumentActions() throws {
    let items = [
        RecentDocumentItem(path: "/books/old.pdf", title: "Old", openedAt: Date(timeIntervalSince1970: 100)),
        RecentDocumentItem(path: "/books/recent.pdf", title: "Recent", openedAt: Date(timeIntervalSince1970: 300)),
        RecentDocumentItem(path: "/books/mid.pdf", title: "Mid", openedAt: Date(timeIntervalSince1970: 200))
    ]

    try expectEqual(droppedDocumentAction(paths: ["/books/a.pdf"]), .openSingle("/books/a.pdf"), "single dropped book should open directly")
    try expectEqual(
        droppedDocumentAction(paths: ["/books/a.pdf", "/books/b.epub", "/books/a.pdf", "/books/skip.txt"]),
        .showShelf(priorityPaths: ["/books/a.pdf", "/books/b.epub"]),
        "multiple dropped books should dedupe and keep shelf focus order"
    )
    try expectEqual(
        droppedDocumentAction(paths: ["/books/a.pdf", "/books/a.pdf"]),
        .showShelf(priorityPaths: ["/books/a.pdf"]),
        "multiple dropped files should open the shelf even when they dedupe to one book"
    )
    try expectEqual(
        sortedRecentDocuments(items, priorityPaths: ["/books/mid.pdf", "/books/old.pdf", "/books/mid.pdf"]).map(\.path),
        ["/books/mid.pdf", "/books/old.pdf", "/books/recent.pdf"],
        "open shelf import should move existing duplicate priority books to the front once"
    )
    try expectEqual(droppedDocumentAction(paths: ["/books/skip.txt"]), .none, "unsupported dropped files should be ignored")
}

private func testEmbeddingDefaults() throws {
    let legacySiliconFlow = selectedEmbeddingOption(savedEndpoint: "https://api.siliconflow.com/v1/embeddings")
    try expectEqual(legacySiliconFlow.id, "siliconflow", "legacy SiliconFlow endpoint should map to provider")
    try expectEqual(embeddingModelName(savedModel: "", savedEndpoint: "https://api.siliconflow.cn/v1/embeddings"), "Qwen/Qwen3-Embedding-8B", "SiliconFlow should default to its own model")

    let siliconFlow = selectedEmbeddingOption(savedEndpoint: "https://api.siliconflow.cn/v1/embeddings")
    let payload = embeddingPayload(option: siliconFlow, model: "Qwen/Qwen3-Embedding-8B", input: ["hello"])
    try expectEqual(payload["encoding_format"] as? String, "float", "SiliconFlow payload should request float embeddings")

    let localCustom = selectedEmbeddingOption(savedEndpoint: "http://127.0.0.1:9999/v1/embeddings")
    try expectEqual(localCustom.requiresAPIKey, false, "custom local embedding endpoints should not require API key")
}

private func testEmbeddingKeyIsolation() throws {
    var store = EmbeddingKeyStore()
    store.saveEmbeddingKey("openai-key", optionID: "openai")
    try expectEqual(store.embeddingKey(for: "openai"), "openai-key", "saved key should be returned for its provider")
    try expectEqual(store.embeddingKey(for: "siliconflow"), "", "unsaved provider should not inherit another provider key")

    store.saveEmbeddingKey("silicon-key", optionID: "siliconflow")
    try expectEqual(store.embeddingKey(for: "openai"), "openai-key", "saving another provider should not overwrite OpenAI key")
    try expectEqual(store.embeddingKey(for: "siliconflow"), "silicon-key", "provider should keep its own key")

    store.saveEmbeddingKey("", optionID: "siliconflow")
    try expectEqual(store.embeddingKey(for: "siliconflow"), "", "clearing one provider should not reveal fallback key")
    try expectEqual(store.embeddingKey(for: "openai"), "openai-key", "clearing one provider should not clear another provider")
}

private func testEmbeddingLegacyKeyMigration() throws {
    var store = EmbeddingKeyStore(encryptedKeys: ["encryptedApiKey.embedding": "legacy-encrypted"], legacyPlainKeys: [:])
    try expectEqual(store.embeddingKey(for: "openai"), "", "non-migrating lookup should not expose legacy key")
    try expectEqual(store.embeddingKeyMigratingLegacyIfNeeded(for: "openai"), "legacy-encrypted", "legacy encrypted key should migrate to selected provider")
    try expectEqual(store.embeddingKey(for: "openai"), "legacy-encrypted", "selected provider should receive migrated key")
    try expectEqual(store.embeddingKey(for: "siliconflow"), "", "other providers should not receive migrated legacy key")
    try expectEqual(store.encryptedKeys["encryptedApiKey.embedding"] ?? "", "", "legacy encrypted key should be removed after migration")

    var plainStore = EmbeddingKeyStore(encryptedKeys: [:], legacyPlainKeys: ["apiKey.embedding": "legacy-plain"])
    try expectEqual(plainStore.embeddingKeyMigratingLegacyIfNeeded(for: "siliconflow"), "legacy-plain", "legacy plain key should migrate to selected provider")
    try expectEqual(plainStore.embeddingKey(for: "siliconflow"), "legacy-plain", "selected provider should receive migrated plain key")
    try expectEqual(plainStore.embeddingKey(for: "openai"), "", "plain legacy migration should not leak to other providers")
    try expectEqual(plainStore.legacyPlainKeys["apiKey.embedding"] ?? "", "", "legacy plain key should be removed after migration")
}

private func testEmbeddingWarmupIdlePolicy() throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    try expect(
        !EmbeddingWarmupPolicy.isReaderIdle(
            lastInteractionAt: now.addingTimeInterval(-(EmbeddingWarmupPolicy.idleThreshold - 0.1)),
            now: now
        ),
        "embedding warmup should wait until the reader has been idle long enough"
    )
    try expect(
        EmbeddingWarmupPolicy.isReaderIdle(
            lastInteractionAt: now.addingTimeInterval(-EmbeddingWarmupPolicy.idleThreshold),
            now: now
        ),
        "embedding warmup should start at the idle threshold"
    )
    try expectEqual(EmbeddingWarmupPolicy.cacheRestoreDelay, 5.0, "cache restore delay should remain explicit")
    try expectEqual(EmbeddingWarmupPolicy.warmupDelay, 18.0, "warmup delay should remain explicit")
}

private func testWordRecordIncrementalStore() throws {
    var store = InMemoryWordRecordStore()
    store.upsert(StoredWordRecord(id: "a", answer: "old", srsReviewCount: 0))
    try expectEqual(store.load(), [StoredWordRecord(id: "a", answer: "old", srsReviewCount: 0)], "upsert should insert a record")

    store.upsert(StoredWordRecord(id: "a", answer: "new", srsReviewCount: 2))
    try expectEqual(store.load(), [StoredWordRecord(id: "a", answer: "new", srsReviewCount: 2)], "upsert should update answer and SRS")

    store.upsert(StoredWordRecord(id: "b", answer: "second", srsReviewCount: 0))
    store.delete(ids: ["a"])
    try expectEqual(store.load(), [StoredWordRecord(id: "b", answer: "second", srsReviewCount: 0)], "delete(ids:) should remove only requested records")

    store.save([])
    try expectEqual(store.load(), [], "bulk clear should leave store empty")
}

private func testWordRecordLegacyMigrationDoesNotReviveClearedData() throws {
    var store = InMemoryWordRecordStore(legacyRecords: [StoredWordRecord(id: "legacy", answer: "old", srsReviewCount: 0)])
    try expectEqual(store.load(), [StoredWordRecord(id: "legacy", answer: "old", srsReviewCount: 0)], "first load should migrate legacy records")
    store.save([])
    try expectEqual(store.load(), [], "cleared migrated store should not reload legacy records")
}

private func testPageScrollDirection() throws {
    try expectEqual(pageDirectionAtEdge(deltaY: 12, isAtTop: true, isAtBottom: false), .previous, "scrolling upward at page top should go previous")
    try expectEqual(pageDirectionAtEdge(deltaY: -12, isAtTop: false, isAtBottom: true), .next, "scrolling downward at page bottom should go next")
    try expect(pageDirectionAtEdge(deltaY: 12, isAtTop: false, isAtBottom: true) == nil, "scrolling upward at bottom should not go previous")
    try expect(pageDirectionAtEdge(deltaY: -12, isAtTop: true, isAtBottom: false) == nil, "scrolling downward at top should not go next")
}

private func testCapturedPageScrollGuard() throws {
    try expect(shouldApplyCapturedPageScroll(capturedPageIndex: 2, documentPageCount: 5), "captured page in current document should be scrollable")
    try expect(!shouldApplyCapturedPageScroll(capturedPageIndex: -1, documentPageCount: 5), "negative captured page should be ignored")
    try expect(!shouldApplyCapturedPageScroll(capturedPageIndex: 5, documentPageCount: 5), "captured page outside current document should be ignored")
}

private func testDebouncedTask() throws {
    let task = DebouncedTask(delay: 10)
    var value = 0
    task.schedule { value = 1 }
    task.schedule { value = 2 }
    task.flush()
    try expectEqual(value, 2, "flush should run only latest scheduled action")

    task.schedule { value = 3 }
    task.cancel()
    task.flush()
    try expectEqual(value, 2, "cancel should clear pending action")
}

private let tests: [(String, () throws -> Void)] = [
    ("Vocabulary SRS", testVocabularySRS),
    ("Recent document sorting/import", testRecentDocumentSortingAndImport),
    ("Dropped document actions", testDroppedDocumentActions),
    ("Embedding defaults", testEmbeddingDefaults),
    ("Embedding key isolation", testEmbeddingKeyIsolation),
    ("Embedding legacy key migration", testEmbeddingLegacyKeyMigration),
    ("Embedding warmup idle policy", testEmbeddingWarmupIdlePolicy),
    ("Reader entity decoding", EPUBLogicTests.testReaderEntityDecoding),
    ("EPUB text decoding", EPUBLogicTests.testEPUBTextDecoding),
    ("EPUB spine linear parsing", EPUBLogicTests.testEPUBSpineLinearParsing),
    ("EPUB OPF XML parsing", EPUBLogicTests.testEPUBOPFXMLParsing),
    ("EPUB lazy images and safe paths", EPUBLogicTests.testEPUBLazyImagesAndSafePaths),
    ("EPUB TOC href normalization", EPUBLogicTests.testEPUBTOCHrefNormalization),
    ("EPUB internal links and sanitizing", EPUBLogicTests.testEPUBInternalLinkTargetsAndSanitizing),
    ("Word record incremental store", testWordRecordIncrementalStore),
    ("Word record legacy migration", testWordRecordLegacyMigrationDoesNotReviveClearedData),
    ("Page scroll direction", testPageScrollDirection),
    ("Captured page scroll guard", testCapturedPageScrollGuard),
    ("Debounced task", testDebouncedTask)
]

@main
private struct LogicTestRunner {
    static func main() {
        var failures: [String] = []
        for (name, test) in tests {
            do {
                try test()
                print("PASS \(name)")
            } catch {
                failures.append("FAIL \(name): \(error)")
            }
        }

        if failures.isEmpty {
            print("All \(tests.count) logic tests passed.")
        } else {
            for failure in failures {
                print(failure)
            }
            exit(1)
        }
    }
}
