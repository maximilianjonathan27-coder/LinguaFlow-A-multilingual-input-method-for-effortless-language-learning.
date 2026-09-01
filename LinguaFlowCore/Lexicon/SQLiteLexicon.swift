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

    private let database: OpaquePointer
    private let lock = NSLock()

    public init(databaseURL: URL) throws {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        )
        guard result == SQLITE_OK, let database else {
            sqlite3_close(database)
            throw LexiconError.databaseUnavailable(databaseURL.path)
        }
        self.database = database
    }

    deinit {
        sqlite3_close(database)
    }

    public func candidates(
        for input: String,
        targetLanguage: String,
        limit: Int
    ) -> [Candidate] {
        let normalized = PinyinNormalizer.normalize(input)
        guard !normalized.isEmpty, limit > 0 else { return [] }

        return query(
            whereClause: "l.normalized_pinyin = ?",
            matchValues: [normalized],
            targetLanguage: targetLanguage,
            limit: limit
        )
    }

    public func prefixCandidates(
        for input: String,
        targetLanguage: String,
        limit: Int
    ) -> [Candidate] {
        let normalized = PinyinNormalizer.normalize(input)
        guard !normalized.isEmpty, limit > 0 else { return [] }
        return query(
            whereClause: "l.normalized_pinyin >= ? AND l.normalized_pinyin < ?",
            matchValues: [normalized, normalized + "{"],
            targetLanguage: targetLanguage,
            limit: limit
        )
    }

    public func abbreviationCandidates(
        for initials: String,
        targetLanguage: String,
        limit: Int
    ) -> [Candidate] {
        let normalized = PinyinNormalizer.normalize(initials)
        guard !normalized.isEmpty, limit > 0 else { return [] }
        return query(
            whereClause: "l.pinyin_initials = ?",
            matchValues: [normalized],
            targetLanguage: targetLanguage,
            limit: limit
        )
    }

    public func correctionCandidates(
        for input: String,
        targetLanguage: String,
        limit: Int
    ) -> [Candidate] {
        let normalized = PinyinNormalizer.normalize(input)
        guard normalized.count >= 4, limit > 0 else { return [] }
        let correctionKeys = PinyinNormalizer.singleEditCorrectionKeys(for: normalized)
        guard !correctionKeys.isEmpty else { return [] }
        let characters = Array(normalized)
        var repeatedKeyCorrections: Set<String> = []
        if characters.count > 1 {
            for index in 1..<characters.count where characters[index] == characters[index - 1] {
                var corrected = characters
                corrected.remove(at: index)
                repeatedKeyCorrections.insert(String(corrected))
            }
        }

        var results: [Candidate] = []
        if !repeatedKeyCorrections.isEmpty {
            let repeatedKeys = repeatedKeyCorrections.sorted()
            let placeholders = Array(repeating: "?", count: repeatedKeys.count)
                .joined(separator: ", ")
            results.append(contentsOf: query(
                whereClause: "l.normalized_pinyin IN (\(placeholders))",
                matchValues: repeatedKeys,
                targetLanguage: targetLanguage,
                limit: limit
            ))
        }

        let placeholders = Array(repeating: "?", count: correctionKeys.count)
            .joined(separator: ", ")
        results.append(contentsOf: query(
            whereClause: "l.normalized_pinyin IN (\(placeholders))",
            matchValues: correctionKeys,
            targetLanguage: targetLanguage,
            limit: max(100, limit * 5)
        ))

        var seenIDs: Set<String> = []
        return results
            .filter { seenIDs.insert($0.id).inserted }
            .prefix(limit)
            .map { $0 }
    }

    private func query(
        whereClause: String,
        matchValues: [String],
        targetLanguage: String,
        limit: Int
    ) -> [Candidate] {

        lock.lock()
        defer { lock.unlock() }

        let sql = """
            SELECT l.stable_id, l.pinyin, l.chinese, l.frequency,
                   COALESCE(t.target_language, ?), COALESCE(t.translation, ''),
                   t.part_of_speech, COALESCE(t.domain, 'general'),
                   COALESCE(t.style, 'neutral')
            FROM lexemes AS l
            LEFT JOIN translations AS t
              ON t.lexeme_id = l.stable_id AND t.target_language = ?
            WHERE \(whereClause)
            ORDER BY l.frequency DESC, l.stable_id ASC
            LIMIT ?
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, targetLanguage, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, targetLanguage, -1, sqliteTransient)
        for (offset, value) in matchValues.enumerated() {
            sqlite3_bind_text(statement, Int32(offset + 3), value, -1, sqliteTransient)
        }
        sqlite3_bind_int(
            statement,
            Int32(matchValues.count + 3),
            Int32(min(limit, Int(Int32.max)))
        )

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
