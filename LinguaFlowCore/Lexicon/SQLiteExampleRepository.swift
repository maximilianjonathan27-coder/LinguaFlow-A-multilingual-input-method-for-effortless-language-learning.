import Foundation
import SQLite3

private let exampleSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class SQLiteExampleRepository: ExampleRepository, @unchecked Sendable {
    public enum RepositoryError: LocalizedError {
        case databaseUnavailable(String)

        public var errorDescription: String? {
            switch self {
            case let .databaseUnavailable(path): "Unable to open the LinguaFlow examples database at \(path)."
            }
        }
    }

    private let database: OpaquePointer
    private let lock = NSLock()

    public init(databaseURL: URL) throws {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard result == SQLITE_OK, let database else {
            sqlite3_close(database)
            throw RepositoryError.databaseUnavailable(databaseURL.path)
        }
        self.database = database
    }

    deinit { sqlite3_close(database) }

    public func phraseCandidates(for input: String, targetLanguage: String, limit: Int) -> [Candidate] {
        let normalized = PinyinNormalizer.normalize(input)
        guard !normalized.isEmpty, targetLanguage == "en", limit > 0 else { return [] }
        lock.lock()
        defer { lock.unlock() }
        let sql = """
            SELECT stable_id,pinyin,chinese,english,priority
            FROM phrases
            WHERE normalized_pinyin=?
            ORDER BY length(chinese) DESC,priority DESC,stable_id ASC
            LIMIT ?
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, normalized, -1, exampleSQLiteTransient)
        sqlite3_bind_int(statement, 2, Int32(min(limit, Int(Int32.max))))
        var results: [Candidate] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = text(statement, 0)
            let chinese = text(statement, 2)
            results.append(Candidate(
                id: id,
                pinyin: text(statement, 1),
                sourceText: chinese,
                translation: text(statement, 3),
                frequency: 10_000_000 + Int(sqlite3_column_int64(statement, 4)),
                targetLanguage: targetLanguage,
                partOfSpeech: "phrase",
                domain: "general",
                style: "neutral",
                examples: examplesLocked(for: chinese, limit: 3)
            ))
        }
        return results
    }

    public func examples(for term: String, limit: Int) -> [ExampleSentence] {
        guard !term.isEmpty, limit > 0 else { return [] }
        lock.lock()
        defer { lock.unlock() }
        return examplesLocked(for: term, limit: limit)
    }

    private func examplesLocked(for term: String, limit: Int) -> [ExampleSentence] {
        let sql = """
            SELECT e.example_id,e.chinese,e.english,e.source,e.quality_score
            FROM example_terms t
            JOIN examples e ON e.example_id=t.example_id
            WHERE t.term=?
            ORDER BY e.quality_score DESC,e.example_id ASC
            LIMIT ?
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, term, -1, exampleSQLiteTransient)
        sqlite3_bind_int(statement, 2, Int32(min(limit, Int(Int32.max))))
        var results: [ExampleSentence] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            results.append(ExampleSentence(
                id: sqlite3_column_int64(statement, 0),
                chinese: text(statement, 1),
                english: text(statement, 2),
                source: text(statement, 3),
                qualityScore: Int(sqlite3_column_int64(statement, 4))
            ))
        }
        return results
    }

    private func text(_ statement: OpaquePointer, _ column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: value)
    }
}
