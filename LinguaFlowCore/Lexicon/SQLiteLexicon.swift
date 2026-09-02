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

    public func continuationCandidates(
        after sourcePrefix: String,
        matchingPinyinPrefix input: String,
        targetLanguage: String,
        limit: Int
    ) -> [Candidate] {
        let normalized = PinyinNormalizer.normalize(input)
        guard sourcePrefix.count >= 2, normalized.count >= 4, limit > 0 else { return [] }
        return query(
            whereClause: """
                l.normalized_pinyin >= ? AND l.normalized_pinyin < ?
                AND length(l.normalized_pinyin) > \(normalized.count)
                AND l.chinese LIKE ? ESCAPE '\\'
                AND length(l.chinese) > \(sourcePrefix.count)
                AND length(l.chinese) <= \(sourcePrefix.count + 6)
                """,
            matchValues: [
                normalized,
                normalized + "{",
                escapedLikePrefix(sourcePrefix) + "%",
            ],
            targetLanguage: targetLanguage,
            limit: limit
        )
    }

    public func metadata(
        for sourceTexts: [String],
        targetLanguage: String
    ) -> [String: Candidate] {
        let uniqueTexts = Array(Set(sourceTexts)).filter { !$0.isEmpty }
        guard !uniqueTexts.isEmpty else { return [:] }
        let placeholders = Array(repeating: "?", count: uniqueTexts.count)
            .joined(separator: ", ")
        let matches = query(
            whereClause: "l.chinese IN (\(placeholders)) AND t.translation <> ''",
            matchValues: uniqueTexts,
            targetLanguage: targetLanguage,
            limit: max(uniqueTexts.count * 8, 64)
        )
        var result: [String: Candidate] = [:]
        for candidate in matches where result[candidate.sourceText] == nil {
            result[candidate.sourceText] = candidate
        }
        return result
    }

    /// Additive reverse lookup used only by English → Chinese mode. Existing
    /// Pinyin queries and their ordering continue to use the methods above.
    public func englishCandidates(for input: String, limit: Int) -> [Candidate] {
        let normalized = input.lowercased().filter { $0.isASCII && $0.isLetter }
        guard !normalized.isEmpty, limit > 0 else { return [] }

        lock.lock()
        defer { lock.unlock() }
        let sql = """
            SELECT normalized_term, frequency, chinese
            FROM english_terms
            WHERE normalized_term >= ? AND normalized_term < ?
            ORDER BY CASE WHEN normalized_term = ? THEN 0 ELSE 1 END,
                     frequency DESC, normalized_term ASC
            LIMIT ?
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return [] }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, normalized, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, normalized + "{", -1, sqliteTransient)
        sqlite3_bind_text(statement, 3, normalized, -1, sqliteTransient)
        sqlite3_bind_int(statement, 4, Int32(min(limit, Int(Int32.max))))

        var results: [Candidate] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let term = text(statement, 0)
            results.append(Candidate(
                id: "en-zh:word:\(term)",
                pinyin: term,
                sourceText: term,
                translation: text(statement, 2),
                frequency: Int(sqlite3_column_int64(statement, 1)),
                sourceLanguage: .english,
                targetLanguage: SupportedLanguage.chineseSimplified.rawValue
            ))
        }
        return results
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

    private func escapedLikePrefix(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
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

public struct EnglishCandidateDecoder: CandidateDecoding, Sendable {
    private let lexicon: SQLiteLexicon

    public init(lexicon: SQLiteLexicon) {
        self.lexicon = lexicon
    }

    public func candidates(for input: String, limit: Int) -> [Candidate] {
        lexicon.englishCandidates(for: input, limit: limit)
    }
}
