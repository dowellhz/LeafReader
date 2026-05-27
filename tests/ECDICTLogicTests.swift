import Foundation
import SQLite3

enum ECDICTLogicTests {
    static func testSQLiteLookupAndMarkdownAnswer() throws {
        let directory = temporaryDirectory("ecdict-sqlite")
        let databaseURL = directory.appendingPathComponent("ecdict.db")
        try createECDICTDatabase(at: databaseURL)

        let dictionary = ECDICTDictionary(databaseURLs: [databaseURL], csvURLs: [])
        let entry = dictionary.lookup(" Apple ")
        try expectEqual(entry?.word, "apple", "ECDICT SQLite lookup should be case-insensitive")
        try expectEqual(entry?.translation, "n. 苹果", "ECDICT SQLite lookup should read translation")

        let answer = dictionary.markdownAnswer(for: "apple", context: "I ate an apple.") ?? ""
        try expect(answer.contains("**apple**"), "dictionary answer should include the word heading")
        try expect(answer.contains("n. 苹果"), "dictionary answer should include Chinese translation")
        try expect(answer.contains("I ate an apple."), "dictionary answer should include source context")
    }

    static func testCSVLookup() throws {
        let directory = temporaryDirectory("ecdict-csv")
        let csvURL = directory.appendingPathComponent("ecdict.csv")
        let csv = """
        word,phonetic,definition,translation,pos,collins,oxford,tag,bnc,frq,exchange,detail,audio
        book,buk,"a written work","n. 书\nv. 预订",n/v,3,1,cet4,500,400,s:books,,
        """
        try csv.write(to: csvURL, atomically: true, encoding: .utf8)

        let dictionary = ECDICTDictionary(databaseURLs: [], csvURLs: [csvURL])
        let entry = dictionary.lookup("book")
        try expectEqual(entry?.word, "book", "ECDICT CSV lookup should find word")
        try expectEqual(entry?.translation, "n. 书\nv. 预订", "ECDICT CSV lookup should unescape newline text")
    }

    static func testLookupKeyNormalization() throws {
        try expectEqual(ECDICTDictionary.lookupKey(" Long-time "), "long-time", "dictionary lookup should preserve hyphenated words")
        try expectEqual(ECDICTDictionary.lookupKey("  Long   Time  "), "long time", "dictionary lookup should normalize spacing")
    }

    private static func temporaryDirectory(_ name: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeafReaderTests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func createECDICTDatabase(at url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            throw TestFailure(description: "could not create ECDICT test database")
        }
        defer { sqlite3_close(db) }

        let createSQL = """
        CREATE TABLE stardict (
          word TEXT,
          phonetic TEXT,
          definition TEXT,
          translation TEXT,
          pos TEXT,
          collins INTEGER,
          oxford INTEGER,
          tag TEXT,
          bnc TEXT,
          frq TEXT,
          exchange TEXT
        );
        """
        guard sqlite3_exec(db, createSQL, nil, nil, nil) == SQLITE_OK else {
            throw TestFailure(description: "could not create ECDICT test table")
        }
        let insertSQL = """
        INSERT INTO stardict (word, phonetic, definition, translation, pos, tag, bnc, frq, exchange)
        VALUES ('apple', 'apəl', 'a round fruit', 'n. 苹果', 'n', 'cet4', '1200', '900', 's:apples');
        """
        guard sqlite3_exec(db, insertSQL, nil, nil, nil) == SQLITE_OK else {
            throw TestFailure(description: "could not insert ECDICT test row")
        }
    }
}

