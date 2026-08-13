import Foundation
import SQLite3

struct WordRecordSQLiteJSONCodec {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    func encode<T: Encodable>(_ value: T?) -> String? {
        guard let value, let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func decode<T: Decodable>(_ type: T.Type, from string: String?) -> T? {
        guard let string, let data = string.data(using: .utf8) else { return nil }
        return try? decoder.decode(type, from: data)
    }
}

enum WordRecordSQLiteBindIndex: Int32 {
    case documentID = 1
    case id = 2
    case word = 3
    case firstSourceField = 4
    case secondSourceField = 5
    case thirdSourceField = 6
    case question = 7
    case answer = 8
    case dictionaryTags = 9
    case dictionaryFrequency = 10
    case createdAt = 11
    case srsJSON = 12
}

struct PDFWordRecordSQLiteMapper {
    enum Column: Int32 {
        case id = 0
        case word = 1
        case pageIndex = 2
        case boundsJSON = 3
        case context = 4
        case question = 5
        case answer = 6
        case dictionaryTags = 7
        case dictionaryFrequency = 8
        case createdAt = 9
        case srsJSON = 10
        case textAnchorJSON = 11
    }

    static let selectSQL = """
    SELECT id, word, page_index, bounds_json, context, question, answer, dictionary_tags, dictionary_frequency, created_at, srs_json, text_anchor_json
    FROM pdf_word_records
    WHERE document_id = ?
    ORDER BY created_at ASC, id ASC
    """

    static let insertSQL = """
    INSERT OR REPLACE INTO pdf_word_records(
        document_id, id, word, page_index, bounds_json, context, question, answer, dictionary_tags, dictionary_frequency, created_at, srs_json, text_anchor_json
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """

    let codec: WordRecordSQLiteJSONCodec

    func decode(from statement: OpaquePointer?) -> StoredPDFWordRecord? {
        guard let id = stringColumn(statement, Column.id.rawValue),
              let word = stringColumn(statement, Column.word.rawValue),
              let boundsJSON = stringColumn(statement, Column.boundsJSON.rawValue),
              let bounds = codec.decode(StoredPDFWordRect.self, from: boundsJSON),
              let question = stringColumn(statement, Column.question.rawValue),
              let answer = stringColumn(statement, Column.answer.rawValue) else {
            return nil
        }
        return StoredPDFWordRecord(
            id: id,
            word: word,
            pageIndex: Int(sqlite3_column_int(statement, Column.pageIndex.rawValue)),
            bounds: bounds,
            textAnchor: codec.decode(TextQuoteAnchor.self, from: optionalStringColumn(statement, Column.textAnchorJSON.rawValue)),
            context: optionalStringColumn(statement, Column.context.rawValue),
            question: question,
            answer: answer,
            dictionaryTags: optionalStringColumn(statement, Column.dictionaryTags.rawValue),
            dictionaryFrequency: optionalIntColumn(statement, Column.dictionaryFrequency.rawValue),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, Column.createdAt.rawValue)),
            srs: codec.decode(VocabularySRSState.self, from: optionalStringColumn(statement, Column.srsJSON.rawValue))
        )
    }

    func bind(documentID: String, record: StoredPDFWordRecord, to statement: OpaquePointer?) {
        bindText(documentID, at: .documentID, statement: statement)
        bindText(record.id, at: .id, statement: statement)
        bindText(record.word, at: .word, statement: statement)
        sqlite3_bind_int(statement, WordRecordSQLiteBindIndex.firstSourceField.rawValue, Int32(record.pageIndex))
        bindText(codec.encode(record.bounds) ?? "{}", at: .secondSourceField, statement: statement)
        bindOptionalText(record.context, at: .thirdSourceField, statement: statement)
        bindText(record.question, at: .question, statement: statement)
        bindText(record.answer, at: .answer, statement: statement)
        bindOptionalText(record.dictionaryTags, at: .dictionaryTags, statement: statement)
        bindOptionalInt(record.dictionaryFrequency, at: .dictionaryFrequency, statement: statement)
        sqlite3_bind_double(statement, WordRecordSQLiteBindIndex.createdAt.rawValue, record.createdAt.timeIntervalSince1970)
        bindOptionalText(codec.encode(record.srs), at: .srsJSON, statement: statement)
        bindOptionalText(codec.encode(record.textAnchor), at: 13, statement: statement)
    }
}

struct WebWordRecordSQLiteMapper {
    enum Column: Int32 {
        case id = 0
        case word = 1
        case context = 2
        case occurrenceIndex = 3
        case scrollProgress = 4
        case question = 5
        case answer = 6
        case dictionaryTags = 7
        case dictionaryFrequency = 8
        case createdAt = 9
        case srsJSON = 10
    }

    static let selectSQL = """
    SELECT id, word, context, occurrence_index, scroll_progress, question, answer, dictionary_tags, dictionary_frequency, created_at, srs_json
    FROM web_word_records
    WHERE document_id = ?
    ORDER BY created_at ASC, id ASC
    """

    static let insertSQL = """
    INSERT OR REPLACE INTO web_word_records(
        document_id, id, word, context, occurrence_index, scroll_progress, question, answer, dictionary_tags, dictionary_frequency, created_at, srs_json
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """

    let codec: WordRecordSQLiteJSONCodec

    func decode(from statement: OpaquePointer?) -> StoredWebWordRecord? {
        guard let id = stringColumn(statement, Column.id.rawValue),
              let word = stringColumn(statement, Column.word.rawValue),
              let context = stringColumn(statement, Column.context.rawValue),
              let question = stringColumn(statement, Column.question.rawValue),
              let answer = stringColumn(statement, Column.answer.rawValue) else {
            return nil
        }
        return StoredWebWordRecord(
            id: id,
            word: word,
            context: context,
            occurrenceIndex: sqlite3_column_type(statement, Column.occurrenceIndex.rawValue) == SQLITE_NULL
                ? nil
                : Int(sqlite3_column_int(statement, Column.occurrenceIndex.rawValue)),
            scrollProgress: sqlite3_column_double(statement, Column.scrollProgress.rawValue),
            question: question,
            answer: answer,
            dictionaryTags: optionalStringColumn(statement, Column.dictionaryTags.rawValue),
            dictionaryFrequency: optionalIntColumn(statement, Column.dictionaryFrequency.rawValue),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, Column.createdAt.rawValue)),
            srs: codec.decode(VocabularySRSState.self, from: optionalStringColumn(statement, Column.srsJSON.rawValue))
        )
    }

    func bind(documentID: String, record: StoredWebWordRecord, to statement: OpaquePointer?) {
        bindText(documentID, at: .documentID, statement: statement)
        bindText(record.id, at: .id, statement: statement)
        bindText(record.word, at: .word, statement: statement)
        bindText(record.context, at: .firstSourceField, statement: statement)
        bindOptionalInt(record.occurrenceIndex, at: .secondSourceField, statement: statement)
        sqlite3_bind_double(statement, WordRecordSQLiteBindIndex.thirdSourceField.rawValue, record.scrollProgress)
        bindText(record.question, at: .question, statement: statement)
        bindText(record.answer, at: .answer, statement: statement)
        bindOptionalText(record.dictionaryTags, at: .dictionaryTags, statement: statement)
        bindOptionalInt(record.dictionaryFrequency, at: .dictionaryFrequency, statement: statement)
        sqlite3_bind_double(statement, WordRecordSQLiteBindIndex.createdAt.rawValue, record.createdAt.timeIntervalSince1970)
        bindOptionalText(codec.encode(record.srs), at: .srsJSON, statement: statement)
    }
}

func bindText(_ value: String, at index: WordRecordSQLiteBindIndex, statement: OpaquePointer?) {
    sqlite3_bind_text(statement, index.rawValue, value, -1, WORD_RECORD_SQLITE_TRANSIENT)
}

func bindOptionalText(_ value: String?, at index: WordRecordSQLiteBindIndex, statement: OpaquePointer?) {
    guard let value else {
        sqlite3_bind_null(statement, index.rawValue)
        return
    }
    bindText(value, at: index, statement: statement)
}

func bindOptionalText(_ value: String?, at index: Int32, statement: OpaquePointer?) {
    guard let value else {
        sqlite3_bind_null(statement, index)
        return
    }
    sqlite3_bind_text(statement, index, value, -1, WORD_RECORD_SQLITE_TRANSIENT)
}

func bindOptionalInt(_ value: Int?, at index: WordRecordSQLiteBindIndex, statement: OpaquePointer?) {
    guard let value else {
        sqlite3_bind_null(statement, index.rawValue)
        return
    }
    sqlite3_bind_int(statement, index.rawValue, Int32(value))
}

func stringColumn(_ statement: OpaquePointer?, _ index: Int32) -> String? {
    guard let pointer = sqlite3_column_text(statement, index) else { return nil }
    return String(cString: pointer)
}

func optionalStringColumn(_ statement: OpaquePointer?, _ index: Int32) -> String? {
    sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : stringColumn(statement, index)
}

func optionalIntColumn(_ statement: OpaquePointer?, _ index: Int32) -> Int? {
    sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, index))
}

let WORD_RECORD_SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
