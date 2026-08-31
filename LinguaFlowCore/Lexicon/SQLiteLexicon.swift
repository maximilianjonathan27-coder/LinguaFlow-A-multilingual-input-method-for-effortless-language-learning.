import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class SQLiteLexicon: LexiconRepository, @unchecked Sendable {
    public enum LexiconError: LocalizedError {
        case databaseUnavailable(String)

        public var errorDescription: String? {
            switch self {
            case let .databaseUnavailable(path):
                "Unable to open the LinguaFlow lexicon at \(path)."
            }
        }
    }

    private let databaseURL: URL

    public init(databaseURL: URL) throws {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        )
        sqlite3_close(database)
        guard result == SQLITE_OK else {
            throw LexiconError.databaseUnavailable(databaseURL.path)
        }
        self.databaseURL = databaseURL
    }

    public func candidates(
        for input: String,
        targetLanguage: String,
        limit: Int
    ) -> [Candidate] {
        let normalized = PinyinNormalizer.normalize(input)
        guard !normalized.isEmpty, limit > 0 else { return [] }

        var database: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            sqlite3_close(database)
            return []
        }
        defer { sqlite3_close(database) }

        let sql = """
            SELECT l.stable_id, l.pinyin, l.chinese, l.frequency,
                   t.target_language, t.translation, t.part_of_speech,
                   t.domain, t.style
            FROM lexemes AS l
            JOIN translations AS t ON t.lexeme_id = l.stable_id
            WHERE l.normalized_pinyin = ? AND t.target_language = ?
            ORDER BY l.frequency DESC, l.stable_id ASC
            LIMIT ?
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, normalized, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, targetLanguage, -1, sqliteTransient)
        sqlite3_bind_int(statement, 3, Int32(min(limit, Int(Int32.max))))

        var results: [Candidate] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            results.append(Candidate(
                id: text(statement, 0),
                pinyin: text(statement, 1),
                sourceText: text(statement, 2),
                translation: text(statement, 5),
                frequency: Int(sqlite3_column_int64(statement, 3)),
                targetLanguage: text(statement, 4),
                partOfSpeech: optionalText(statement, 6),
                domain: text(statement, 7),
                style: text(statement, 8)
            ))
        }
        return results
    }

    private func text(_ statement: OpaquePointer, _ column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: value)
    }

    private func optionalText(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        return text(statement, column)
    }
}
