#!/usr/bin/env swift

import Foundation
import SQLite3

struct LexemeRow {
    let id: String
    let pinyin: String
    let chinese: String
    let frequency: Int
}

struct TranslationRow {
    let id: String
    let language: String
    let translation: String
    let partOfSpeech: String
    let domain: String
    let style: String
}

enum BuildError: LocalizedError {
    case invalidRow(URL, Int)
    case sqlite(String)

    var errorDescription: String? {
        switch self {
        case let .invalidRow(url, line): "Invalid TSV row at \(url.path):\(line)"
        case let .sqlite(message): "SQLite error: \(message)"
        }
    }
}

let arguments = CommandLine.arguments
let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceDirectory = arguments.count > 1
    ? URL(fileURLWithPath: arguments[1])
    : repositoryRoot.appendingPathComponent("LexiconSource", isDirectory: true)
let outputURL = arguments.count > 2
    ? URL(fileURLWithPath: arguments[2])
    : repositoryRoot.appendingPathComponent("LinguaFlowInputMethod/Resources/linguaflow.sqlite")

func rows(at url: URL, expectedColumns: Int) throws -> [[String]] {
    let content = try String(contentsOf: url, encoding: .utf8)
    return try content.split(whereSeparator: \.isNewline).dropFirst().enumerated().map { offset, line in
        let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard columns.count == expectedColumns else { throw BuildError.invalidRow(url, offset + 2) }
        return columns
    }
}

let lexemes = try rows(at: sourceDirectory.appendingPathComponent("lexicon.tsv"), expectedColumns: 4).map {
    guard let frequency = Int($0[3]) else { throw BuildError.invalidRow(sourceDirectory, 0) }
    return LexemeRow(id: $0[0], pinyin: $0[1], chinese: $0[2], frequency: frequency)
}
let translations = try rows(at: sourceDirectory.appendingPathComponent("translations.tsv"), expectedColumns: 6).map {
    TranslationRow(id: $0[0], language: $0[1], translation: $0[2], partOfSpeech: $0[3], domain: $0[4], style: $0[5])
}
let curatedPhraseRows = try rows(
    at: sourceDirectory.appendingPathComponent("curated_phrases.tsv"),
    expectedColumns: 8
)
let curatedLexemes = try curatedPhraseRows.map { row in
    guard let frequency = Int(row[3]) else {
        throw BuildError.invalidRow(sourceDirectory.appendingPathComponent("curated_phrases.tsv"), 0)
    }
    return LexemeRow(id: row[0], pinyin: row[1], chinese: row[2], frequency: frequency)
}
let curatedTranslations = curatedPhraseRows.map { row in
    TranslationRow(
        id: row[0],
        language: "en",
        translation: row[4],
        partOfSpeech: row[5],
        domain: row[6],
        style: row[7]
    )
}

func normalizedDictionaryPinyin(_ value: String) -> String {
    value.lowercased()
        .replacingOccurrences(of: "u:", with: "v")
        .replacingOccurrences(of: "ü", with: "v")
        .filter { $0.isASCII && $0.isLetter }
}

func cedictTranslationKey(chinese: String, pinyin: String) -> String {
    chinese + "\t" + normalizedDictionaryPinyin(pinyin)
}

func cedictTranslations(at url: URL) throws -> [String: String] {
    guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
    let content = try String(contentsOf: url, encoding: .utf8)
    var translationsByChinese: [String: String] = [:]
    var priorityByKey: [String: Int] = [:]
    let metadataPrefixes = [
        "CL:", "variant of ", "old variant of ", "archaic variant of ",
        "see ", "see also ", "used in ", "surname "
    ]

    for line in content.split(whereSeparator: \.isNewline) {
        guard line.first != "#",
              let pinyinStart = line.firstIndex(of: "["),
              let definitionStart = line.range(of: "] /", range: pinyinStart..<line.endIndex)
        else { continue }

        let head = line[..<pinyinStart].split(whereSeparator: \.isWhitespace)
        guard head.count >= 2 else { continue }
        let chinese = String(head[1])
        let pinyin = String(line[line.index(after: pinyinStart)..<definitionStart.lowerBound])
        let definitions = line[definitionStart.upperBound...]
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard let definition = definitions.first(where: { value in
            let lowercased = value.lowercased()
            return !metadataPrefixes.contains { lowercased.hasPrefix($0.lowercased()) }
        }) ?? definitions.first(where: { !$0.hasPrefix("CL:") }) else { continue }

        let compact = definition.count > 120
            ? String(definition.prefix(117)) + "…"
            : definition
        let lowercasedDefinitions = definitions.map { $0.lowercased() }
        var priority = 100
        let lowercasedDefinition = definition.lowercased()
        if lowercasedDefinition.hasPrefix("variant of ")
            || lowercasedDefinition.hasPrefix("old variant of ") {
            priority -= 500
        }
        if pinyin.first?.isUppercase == true { priority -= 200 }
        if lowercasedDefinition.hasPrefix("surname ") { priority -= 300 }
        if lowercasedDefinition.hasPrefix("(bound form)") { priority -= 40 }
        if lowercasedDefinition.hasPrefix("(literary)") { priority -= 20 }
        if lowercasedDefinitions.contains(where: { $0.hasPrefix("cl:") }) {
            priority += 20
        }
        let key = cedictTranslationKey(chinese: chinese, pinyin: pinyin)
        if priority > priorityByKey[key, default: Int.min] {
            translationsByChinese[key] = compact
            priorityByKey[key] = priority
        }
        let fallbackKey = chinese + "\t*"
        if priority > priorityByKey[fallbackKey, default: Int.min] {
            translationsByChinese[fallbackKey] = compact
            priorityByKey[fallbackKey] = priority
        }
    }
    return translationsByChinese
}

func rimeIceRows(
    at url: URL,
    maximumCount: Int,
    commonFrequencyFloor: Int? = nil
) throws -> [LexemeRow] {
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    let content = try String(contentsOf: url, encoding: .utf8)
    var bestByKey: [String: LexemeRow] = [:]

    for line in content.split(whereSeparator: \.isNewline) {
        guard line.first != "#" else { continue }
        let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard columns.count >= 3, let frequency = Int(columns[2]) else { continue }
        let chinese = String(columns[0])
        let pinyin = String(columns[1])
        guard !chinese.isEmpty, chinese.count <= 8 else { continue }
        let normalized = pinyin.lowercased().filter { $0.isASCII && $0.isLetter }
        guard !normalized.isEmpty else { continue }
        let key = normalized + "\t" + chinese
        let row = LexemeRow(
            id: "rime-ice:" + normalized + ":" + chinese,
            pinyin: pinyin,
            chinese: chinese,
            frequency: frequency
        )
        if bestByKey[key].map({ $0.frequency < frequency }) ?? true {
            bestByKey[key] = row
        }
    }

    let sorted = bestByKey.values.sorted {
        if $0.frequency != $1.frequency { return $0.frequency > $1.frequency }
        return $0.id < $1.id
    }
    let highFrequency = sorted.prefix(maximumCount)
    let commonWords = commonFrequencyFloor.map { floor in
        sorted.filter { $0.frequency >= floor }
    } ?? []
    let commonCharacters = sorted.filter { $0.chinese.count == 1 }
    var selectedByID: [String: LexemeRow] = [:]
    // A global top-N cut alone drops ordinary words such as 泥巴 because
    // unrelated proper nouns and long phrases consume the shared quota.
    for row in Array(highFrequency) + commonWords + commonCharacters {
        selectedByID[row.id] = row
    }
    return selectedByID.values.sorted {
        if $0.frequency != $1.frequency { return $0.frequency > $1.frequency }
        return $0.id < $1.id
    }
}

let externalLexemes = try rimeIceRows(
    at: sourceDirectory.appendingPathComponent("External/rime_ice_base.dict.yaml"),
    maximumCount: 100_000,
    commonFrequencyFloor: 2_000
)
let commonCharacters = try rimeIceRows(
    at: sourceDirectory.appendingPathComponent("External/rime_ice_8105.dict.yaml"),
    maximumCount: 20_000
)
// Curated entries precede imported rows so their stable identifiers and
// reviewed metadata win when the same Pinyin/Chinese pair exists upstream.
let allLexemes = lexemes + curatedLexemes + commonCharacters + externalLexemes
let cedict = try cedictTranslations(
    at: sourceDirectory.appendingPathComponent("External/cedict_ts.u8")
)
let reviewedTranslations = translations + curatedTranslations
let seedTranslationIDs = Set(reviewedTranslations.map(\.id))
var generatedTranslationsByID: [String: TranslationRow] = [:]
for lexeme in allLexemes where !seedTranslationIDs.contains(lexeme.id) {
    let key = cedictTranslationKey(chinese: lexeme.chinese, pinyin: lexeme.pinyin)
    guard let translation = cedict[key] ?? cedict[lexeme.chinese + "\t*"] else { continue }
    generatedTranslationsByID[lexeme.id] = TranslationRow(
        id: lexeme.id,
        language: "en",
        translation: translation,
        partOfSpeech: "",
        domain: "general",
        style: "neutral"
    )
}
let allTranslations = reviewedTranslations + generatedTranslationsByID.values.sorted { $0.id < $1.id }

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
let temporaryURL = outputURL.deletingLastPathComponent()
    .appendingPathComponent(".linguaflow-\(ProcessInfo.processInfo.processIdentifier).sqlite")
try? FileManager.default.removeItem(at: temporaryURL)

var database: OpaquePointer?
guard sqlite3_open(temporaryURL.path, &database) == SQLITE_OK, let database else {
    throw BuildError.sqlite("could not create \(temporaryURL.path)")
}
var databaseIsOpen = true
defer {
    if databaseIsOpen { sqlite3_close(database) }
}

func execute(_ sql: String) throws {
    var error: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(database, sql, nil, nil, &error) == SQLITE_OK else {
        defer { sqlite3_free(error) }
        throw BuildError.sqlite(error.map { String(cString: $0) } ?? "unknown error")
    }
}

try execute("""
    PRAGMA journal_mode = OFF;
    PRAGMA synchronous = OFF;
    CREATE TABLE lexemes (
        stable_id TEXT PRIMARY KEY,
        pinyin TEXT NOT NULL,
        normalized_pinyin TEXT NOT NULL,
        pinyin_initials TEXT NOT NULL,
        pinyin_length INTEGER NOT NULL,
        chinese TEXT NOT NULL,
        frequency INTEGER NOT NULL DEFAULT 0,
        UNIQUE (normalized_pinyin, chinese)
    );
    CREATE INDEX lexemes_pinyin_frequency
        ON lexemes(normalized_pinyin, frequency DESC);
    CREATE INDEX lexemes_initials_frequency
        ON lexemes(pinyin_initials, frequency DESC);
    CREATE INDEX lexemes_length_frequency
        ON lexemes(pinyin_length, frequency DESC);
    CREATE INDEX lexemes_chinese_frequency
        ON lexemes(chinese, frequency DESC);
    CREATE TABLE translations (
        lexeme_id TEXT NOT NULL REFERENCES lexemes(stable_id),
        target_language TEXT NOT NULL,
        translation TEXT NOT NULL,
        part_of_speech TEXT,
        domain TEXT NOT NULL DEFAULT 'general',
        style TEXT NOT NULL DEFAULT 'neutral',
        PRIMARY KEY (lexeme_id, target_language)
    );
    BEGIN IMMEDIATE;
    """)

let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

func prepare(_ sql: String) throws -> OpaquePointer {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
        throw BuildError.sqlite(String(cString: sqlite3_errmsg(database)))
    }
    return statement
}

func executePrepared(_ statement: OpaquePointer) throws {
    guard sqlite3_step(statement) == SQLITE_DONE else {
        throw BuildError.sqlite(String(cString: sqlite3_errmsg(database)))
    }
    sqlite3_reset(statement)
    sqlite3_clear_bindings(statement)
}

let lexemeStatement = try prepare("INSERT OR IGNORE INTO lexemes VALUES (?, ?, ?, ?, ?, ?, ?)")
for row in allLexemes {
    let normalized = row.pinyin.lowercased().filter { $0.isASCII && $0.isLetter }
    let syllables = row.pinyin.lowercased()
        .split(whereSeparator: { $0.isWhitespace || $0 == "'" })
    let initials = syllables.compactMap(\.first).map(String.init).joined()
    sqlite3_bind_text(lexemeStatement, 1, row.id, -1, transient)
    sqlite3_bind_text(lexemeStatement, 2, row.pinyin, -1, transient)
    sqlite3_bind_text(lexemeStatement, 3, normalized, -1, transient)
    sqlite3_bind_text(lexemeStatement, 4, initials, -1, transient)
    sqlite3_bind_int64(lexemeStatement, 5, sqlite3_int64(normalized.count))
    sqlite3_bind_text(lexemeStatement, 6, row.chinese, -1, transient)
    sqlite3_bind_int64(lexemeStatement, 7, sqlite3_int64(row.frequency))
    try executePrepared(lexemeStatement)
}

let translationStatement = try prepare("INSERT INTO translations VALUES (?, ?, ?, ?, ?, ?)")
for row in allTranslations {
    let values = [row.id, row.language, row.translation, row.partOfSpeech, row.domain, row.style]
    for (offset, value) in values.enumerated() {
        sqlite3_bind_text(translationStatement, Int32(offset + 1), value, -1, transient)
    }
    try executePrepared(translationStatement)
}

try execute("COMMIT; PRAGMA optimize;")
sqlite3_finalize(lexemeStatement)
sqlite3_finalize(translationStatement)
guard sqlite3_close(database) == SQLITE_OK else {
    throw BuildError.sqlite("could not finalize \(temporaryURL.path)")
}
databaseIsOpen = false
try? FileManager.default.removeItem(at: outputURL)
try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
print("Built \(outputURL.path) with \(allLexemes.count) source lexemes and \(allTranslations.count) translations.")
