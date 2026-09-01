import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class SQLiteLexicon: LexiconRepository, @unchecked Sendable {
    private struct LexemeResult {
        let id: String
        let pinyin: String
        let chinese: String
        let frequency: Int
        let isProperNoun: Bool
    }

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
        // Schema v2 stores the original syllable-separated pinyin instead of a
        // duplicated initials column. Match one initial per syllable so `nky`
        // still finds `ni ke yi` without coupling the reader to the old schema.
        let pattern = normalized.map { String($0) + "*" }.joined(separator: " ")
        return query(
            whereClause: "LOWER(l.pinyin) GLOB ?",
            matchValues: [pattern],
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
            SELECT l.stable_id, l.pinyin, l.chinese, l.frequency, l.is_proper_noun
            FROM lexemes AS l
            WHERE \(whereClause)
            ORDER BY
                CASE WHEN l.is_proper_noun = 1 THEN l.frequency / 3 ELSE l.frequency END DESC,
                l.is_proper_noun ASC,
                l.meaning_rank ASC,
                l.stable_id ASC
            LIMIT ?
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        for (offset, value) in matchValues.enumerated() {
            sqlite3_bind_text(statement, Int32(offset + 1), value, -1, sqliteTransient)
        }
        sqlite3_bind_int(
            statement,
            Int32(matchValues.count + 1),
            Int32(min(limit, Int(Int32.max)))
        )

        var lexemes: [LexemeResult] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            lexemes.append(LexemeResult(
                id: text(statement, 0),
                pinyin: text(statement, 1),
                chinese: text(statement, 2),
                frequency: Int(sqlite3_column_int64(statement, 3)),
                isProperNoun: sqlite3_column_int(statement, 4) != 0
            ))
        }
        return lexemes.map { lexeme in
            let senses = senses(for: lexeme.id, targetLanguage: targetLanguage)
            let primary = senses.first
            return Candidate(
                id: lexeme.id,
                pinyin: lexeme.pinyin,
                sourceText: lexeme.chinese,
                translation: primary?.glosses.first ?? "",
                frequency: lexeme.frequency,
                targetLanguage: targetLanguage,
                domain: primary?.domain ?? "general",
                style: primary?.style ?? "neutral",
                translationSenses: senses,
                isProperNoun: lexeme.isProperNoun
            )
        }
    }

    private func senses(for lexemeID: String, targetLanguage: String) -> [TranslationSense] {
        let sql = """
            SELECT s.sense_id, s.sense_order, s.commonness_rank, s.usage_label,
                   s.domain, s.style, g.gloss
            FROM translation_senses AS s
            JOIN translation_glosses AS g ON g.sense_id = s.sense_id
            WHERE s.lexeme_id = ? AND s.target_language = ?
            ORDER BY s.commonness_rank ASC, s.sense_order ASC, g.gloss_order ASC
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, lexemeID, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, targetLanguage, -1, sqliteTransient)

        var order: [String] = []
        var metadata: [String: (Int, Int, String?, String, String)] = [:]
        var glosses: [String: [String]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = text(statement, 0)
            if metadata[id] == nil {
                order.append(id)
                metadata[id] = (
                    Int(sqlite3_column_int(statement, 1)),
                    Int(sqlite3_column_int(statement, 2)),
                    optionalText(statement, 3),
                    text(statement, 4),
                    text(statement, 5)
                )
            }
            glosses[id, default: []].append(text(statement, 6))
        }
        return order.compactMap { id in
            guard let value = metadata[id] else { return nil }
            return TranslationSense(
                id: id,
                lexemeID: lexemeID,
                targetLanguage: targetLanguage,
                order: value.0,
                commonnessRank: value.1,
                glosses: glosses[id, default: []],
                usageLabel: value.2,
                domain: value.3,
                style: value.4
            )
        }
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
