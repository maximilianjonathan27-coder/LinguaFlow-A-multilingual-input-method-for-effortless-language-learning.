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
        chinese TEXT NOT NULL,
        frequency INTEGER NOT NULL DEFAULT 0
    );
    CREATE INDEX lexemes_pinyin_frequency
        ON lexemes(normalized_pinyin, frequency DESC);
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

func insert(_ sql: String, values: [String]) throws {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
        throw BuildError.sqlite(String(cString: sqlite3_errmsg(database)))
    }
    defer { sqlite3_finalize(statement) }
    for (offset, value) in values.enumerated() {
        sqlite3_bind_text(statement, Int32(offset + 1), value, -1, transient)
    }
    guard sqlite3_step(statement) == SQLITE_DONE else {
        throw BuildError.sqlite(String(cString: sqlite3_errmsg(database)))
    }
}

for row in lexemes {
    let normalized = row.pinyin.lowercased().filter { $0.isASCII && $0.isLetter }
    try insert(
        "INSERT INTO lexemes VALUES (?, ?, ?, ?, ?)",
        values: [row.id, row.pinyin, normalized, row.chinese, String(row.frequency)]
    )
}
for row in translations {
    try insert(
        "INSERT INTO translations VALUES (?, ?, ?, ?, ?, ?)",
        values: [row.id, row.language, row.translation, row.partOfSpeech, row.domain, row.style]
    )
}

try execute("COMMIT; PRAGMA optimize;")
guard sqlite3_close(database) == SQLITE_OK else {
    throw BuildError.sqlite("could not finalize \(temporaryURL.path)")
}
databaseIsOpen = false
try? FileManager.default.removeItem(at: outputURL)
try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
print("Built \(outputURL.path) with \(lexemes.count) lexemes and \(translations.count) translations.")
