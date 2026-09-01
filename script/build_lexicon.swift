#!/usr/bin/env swift

import Foundation
import SQLite3

struct SourceLexeme { let id: String; let pinyin: String; let chinese: String; let frequency: Int }
struct SeedTranslation { let id: String; let language: String; let text: String; let partOfSpeech: String; let domain: String; let style: String }
struct SenseRecord: Hashable { let glosses: [String]; let usageLabel: String?; let commonnessRank: Int; let domain: String; let style: String }
struct CEDICTEntry {
    let traditional: String; let simplified: String; let pinyin: String
    let pronunciationKey: String; let normalizedPinyin: String
    let isProperNoun: Bool; let senses: [SenseRecord]
}
struct LexemeRecord {
    var id: String; var pinyin: String; var normalizedPinyin: String
    var pronunciationKey: String; var traditional: String; var chinese: String
    var frequency: Int; var isProperNoun: Bool; var source: String
    var senses: [SenseRecord]
}

enum BuildError: LocalizedError {
    case invalidRow(URL, Int), invalidCEDICT(String), sqlite(String)
    var errorDescription: String? {
        switch self {
        case let .invalidRow(url, line): "Invalid TSV row at \(url.path):\(line)"
        case let .invalidCEDICT(message): "Invalid CC-CEDICT V2 source: \(message)"
        case let .sqlite(message): "SQLite error: \(message)"
        }
    }
}

let arguments = CommandLine.arguments
let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceDirectory = arguments.count > 1 ? URL(fileURLWithPath: arguments[1]) : repositoryRoot.appendingPathComponent("LexiconSource")
let outputURL = arguments.count > 2 ? URL(fileURLWithPath: arguments[2]) : repositoryRoot.appendingPathComponent("LinguaFlowInputMethod/Resources/linguaflow.sqlite")

func rows(at url: URL, expectedColumns: Int) throws -> [[String]] {
    let content = try String(contentsOf: url, encoding: .utf8)
    return try content.split(whereSeparator: \.isNewline).dropFirst().enumerated().map { offset, line in
        let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard columns.count == expectedColumns else { throw BuildError.invalidRow(url, offset + 2) }
        return columns
    }
}

func normalizedPinyin(_ value: String) -> String {
    value.lowercased().replacingOccurrences(of: "u:", with: "v")
        .replacingOccurrences(of: "ü", with: "v").filter { $0.isASCII && $0.isLetter }
}
func pronunciationKey(_ value: String) -> String {
    value.replacingOccurrences(of: "u:", with: "v")
        .replacingOccurrences(of: "ü", with: "v").filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
}
func lookupKey(pinyin: String, chinese: String) -> String { normalizedPinyin(pinyin) + "\t" + chinese }
func leadingUsageLabel(_ gloss: String) -> String? {
    guard gloss.first == "(", let end = gloss.firstIndex(of: ")") else { return nil }
    return String(gloss[gloss.startIndex...end])
}
func senseRank(glosses: [String], order: Int, proper: Bool) -> Int {
    let text = glosses.joined(separator: " ").lowercased()
    let lowPriority = ["variant of ", "old variant", "archaic", "obsolete", "literary", "classifier for", "cl:", "see also ", "used in ", "dialect"]
    var rank = 100 + order * 10
    if proper { rank += 400 }
    if lowPriority.contains(where: text.contains) { rank += 300 }
    if glosses.first?.count ?? 0 > 100 { rank += 20 }
    return rank
}

func parseCEDICTV2(at url: URL) throws -> [CEDICTEntry] {
    let content = try String(contentsOf: url, encoding: .utf8)
    guard content.contains("#! version=2") else { throw BuildError.invalidCEDICT("expected a '#! version=2' header") }
    var entries: [CEDICTEntry] = []
    entries.reserveCapacity(125_000)
    for rawLine in content.split(whereSeparator: \.isNewline) {
        guard rawLine.first != "#" else { continue }
        let line = String(rawLine)
        guard let start = line.range(of: "[["), let end = line.range(of: "]] /", range: start.upperBound..<line.endIndex) else { continue }
        let head = line[..<start.lowerBound].split(whereSeparator: \.isWhitespace)
        guard head.count >= 2 else { continue }
        let traditional = String(head[0]), simplified = String(head[1])
        let pinyin = String(line[start.upperBound..<end.lowerBound]), key = pronunciationKey(pinyin)
        guard !key.isEmpty else { continue }
        let proper = pinyin.contains { $0.isASCII && $0.isUppercase }
        let rawSenses = String(line[end.upperBound...]).split(separator: "/", omittingEmptySubsequences: true)
        var senses: [SenseRecord] = []
        for (order, rawSense) in rawSenses.enumerated() {
            let glosses = rawSense.split(separator: ";", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !glosses.isEmpty else { continue }
            senses.append(SenseRecord(glosses: glosses, usageLabel: leadingUsageLabel(glosses[0]), commonnessRank: senseRank(glosses: glosses, order: order, proper: proper), domain: "general", style: "neutral"))
        }
        if !senses.isEmpty {
            entries.append(CEDICTEntry(traditional: traditional, simplified: simplified, pinyin: pinyin, pronunciationKey: key, normalizedPinyin: normalizedPinyin(pinyin), isProperNoun: proper, senses: senses))
        }
    }
    return entries
}

func rimeRows(at url: URL, maximumCount: Int) throws -> [SourceLexeme] {
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    let content = try String(contentsOf: url, encoding: .utf8)
    var best: [String: SourceLexeme] = [:]
    for line in content.split(whereSeparator: \.isNewline) {
        guard line.first != "#" else { continue }
        let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard columns.count >= 3, let frequency = Int(columns[2]) else { continue }
        let chinese = String(columns[0]), pinyin = String(columns[1])
        guard !chinese.isEmpty, chinese.count <= 8, !normalizedPinyin(pinyin).isEmpty else { continue }
        let key = lookupKey(pinyin: pinyin, chinese: chinese)
        let row = SourceLexeme(id: "rime-ice:" + normalizedPinyin(pinyin) + ":" + chinese, pinyin: pinyin, chinese: chinese, frequency: frequency)
        if best[key].map({ $0.frequency < frequency }) ?? true { best[key] = row }
    }
    let sorted = best.values.sorted { $0.frequency == $1.frequency ? $0.id < $1.id : $0.frequency > $1.frequency }
    let selected = Array(sorted.prefix(maximumCount)) + sorted.filter { $0.chinese.count == 1 }
    return Dictionary(selected.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values.sorted { $0.id < $1.id }
}

let seedLexemes = try rows(at: sourceDirectory.appendingPathComponent("lexicon.tsv"), expectedColumns: 4).map {
    guard let frequency = Int($0[3]) else { throw BuildError.invalidRow(sourceDirectory, 0) }
    return SourceLexeme(id: $0[0], pinyin: $0[1], chinese: $0[2], frequency: frequency)
}
let seedTranslations = try rows(at: sourceDirectory.appendingPathComponent("translations.tsv"), expectedColumns: 6).map {
    SeedTranslation(id: $0[0], language: $0[1], text: $0[2], partOfSpeech: $0[3], domain: $0[4], style: $0[5])
}
// These were useful visual-prototype suggestions, but their stored pinyin does
// not cover the complete Chinese phrase. The phrase database now owns them
// under their real full pinyin so sentence decoding cannot duplicate words.
let legacySuggestionIDs: Set<String> = [
    "anpai.meeting", "anpai.time", "yanqi.meeting", "yanqi.submission",
    "shenqing.university", "shenqing.submit", "fangfa.approach", "fangfa.learning",
]
let searchableSeedLexemes = seedLexemes.filter { !legacySuggestionIDs.contains($0.id) }
let rimeLexemes = try rimeRows(at: sourceDirectory.appendingPathComponent("External/rime_ice_base.dict.yaml"), maximumCount: 100_000)
    + rimeRows(at: sourceDirectory.appendingPathComponent("External/rime_ice_8105.dict.yaml"), maximumCount: 20_000)
let cedictEntries = try parseCEDICTV2(at: sourceDirectory.appendingPathComponent("External/cedict_ts.u8"))
let seedsByLookup = Dictionary(searchableSeedLexemes.map { (lookupKey(pinyin: $0.pinyin, chinese: $0.chinese), $0) }, uniquingKeysWith: { first, _ in first })
let seedTranslationsByID = Dictionary(seedTranslations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
let rimeByLookup = Dictionary(rimeLexemes.map { (lookupKey(pinyin: $0.pinyin, chinese: $0.chinese), $0) }, uniquingKeysWith: { $0.frequency >= $1.frequency ? $0 : $1 })
let preferredGlosses = ["大学\tda4xue2": "university", "行\txing2": "okay", "行\thang2": "profession", "王\twang2": "king", "明\tming2": "bright"]

var lexemesByIdentity: [String: LexemeRecord] = [:]
var representedLookups: Set<String> = []
for entry in cedictEntries {
    let lookup = entry.normalizedPinyin + "\t" + entry.simplified
    representedLookups.insert(lookup)
    let identity = entry.simplified + "\t" + entry.pronunciationKey
    let seed = !entry.isProperNoun ? seedsByLookup[lookup] : nil
    let rime = rimeByLookup[lookup]
    let stableID = seed?.id ?? "cedict:" + entry.pronunciationKey + ":" + entry.simplified
    var senses = entry.senses
    if let preferred = preferredGlosses[entry.simplified + "\t" + entry.pronunciationKey] {
        senses.insert(SenseRecord(glosses: [preferred], usageLabel: "LinguaFlow preferred common meaning", commonnessRank: 0, domain: "general", style: "neutral"), at: 0)
    }
    if let translation = seed.flatMap({ seedTranslationsByID[$0.id] }) {
        senses.insert(SenseRecord(glosses: [translation.text], usageLabel: "LinguaFlow reviewed", commonnessRank: -100, domain: translation.domain, style: translation.style), at: 0)
    }
    if var existing = lexemesByIdentity[identity] {
        for sense in senses where !existing.senses.contains(sense) { existing.senses.append(sense) }
        existing.frequency = max(existing.frequency, seed?.frequency ?? 0, rime?.frequency ?? 0)
        lexemesByIdentity[identity] = existing
    } else {
        lexemesByIdentity[identity] = LexemeRecord(id: stableID, pinyin: entry.pinyin, normalizedPinyin: entry.normalizedPinyin, pronunciationKey: entry.pronunciationKey, traditional: entry.traditional, chinese: entry.simplified, frequency: max(seed?.frequency ?? 0, rime?.frequency ?? 0), isProperNoun: entry.isProperNoun, source: "cc-cedict-v2", senses: senses)
    }
}

for row in searchableSeedLexemes where !representedLookups.contains(lookupKey(pinyin: row.pinyin, chinese: row.chinese)) {
    let sense = seedTranslationsByID[row.id].map { SenseRecord(glosses: [$0.text], usageLabel: "LinguaFlow reviewed", commonnessRank: -100, domain: $0.domain, style: $0.style) }
    lexemesByIdentity["seed\t" + row.id] = LexemeRecord(id: row.id, pinyin: row.pinyin, normalizedPinyin: normalizedPinyin(row.pinyin), pronunciationKey: "seed" + pronunciationKey(row.pinyin), traditional: row.chinese, chinese: row.chinese, frequency: row.frequency, isProperNoun: false, source: "linguaflow", senses: sense.map { [$0] } ?? [])
}
for row in rimeLexemes {
    let lookup = lookupKey(pinyin: row.pinyin, chinese: row.chinese)
    guard !representedLookups.contains(lookup), seedsByLookup[lookup] == nil else { continue }
    lexemesByIdentity["rime\t" + lookup] = LexemeRecord(id: row.id, pinyin: row.pinyin, normalizedPinyin: normalizedPinyin(row.pinyin), pronunciationKey: "rime" + pronunciationKey(row.pinyin), traditional: row.chinese, chinese: row.chinese, frequency: row.frequency, isProperNoun: false, source: "rime-ice", senses: [])
}

let allLexemes = lexemesByIdentity.values.sorted { $0.id < $1.id }
try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
let temporaryURL = outputURL.deletingLastPathComponent().appendingPathComponent(".linguaflow-\(ProcessInfo.processInfo.processIdentifier).sqlite")
try? FileManager.default.removeItem(at: temporaryURL)
var database: OpaquePointer?
guard sqlite3_open(temporaryURL.path, &database) == SQLITE_OK, let database else { throw BuildError.sqlite("could not create \(temporaryURL.path)") }
var databaseIsOpen = true
defer { if databaseIsOpen { sqlite3_close(database) } }
func execute(_ sql: String) throws {
    var error: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(database, sql, nil, nil, &error) == SQLITE_OK else {
        defer { sqlite3_free(error) }
        throw BuildError.sqlite(error.map { String(cString: $0) } ?? "unknown error")
    }
}
try execute("""
PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF; PRAGMA user_version=2;
CREATE TABLE lexemes (stable_id TEXT PRIMARY KEY, pinyin TEXT NOT NULL, normalized_pinyin TEXT NOT NULL, pronunciation_key TEXT NOT NULL, traditional TEXT NOT NULL, chinese TEXT NOT NULL, frequency INTEGER NOT NULL DEFAULT 0, is_proper_noun INTEGER NOT NULL DEFAULT 0, meaning_rank INTEGER NOT NULL DEFAULT 9999, source TEXT NOT NULL, UNIQUE(chinese, pronunciation_key));
CREATE INDEX lexemes_pinyin_frequency ON lexemes(normalized_pinyin, is_proper_noun, meaning_rank, frequency DESC);
CREATE TABLE translation_senses (sense_id TEXT PRIMARY KEY, lexeme_id TEXT NOT NULL REFERENCES lexemes(stable_id), target_language TEXT NOT NULL, sense_order INTEGER NOT NULL, commonness_rank INTEGER NOT NULL, usage_label TEXT, domain TEXT NOT NULL DEFAULT 'general', style TEXT NOT NULL DEFAULT 'neutral');
CREATE INDEX senses_lexeme_rank ON translation_senses(lexeme_id, target_language, commonness_rank, sense_order);
CREATE TABLE translation_glosses (sense_id TEXT NOT NULL REFERENCES translation_senses(sense_id), gloss_order INTEGER NOT NULL, gloss TEXT NOT NULL, PRIMARY KEY(sense_id, gloss_order));
CREATE TABLE lexicon_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
INSERT INTO lexicon_metadata VALUES ('schema_version','2'); INSERT INTO lexicon_metadata VALUES ('cedict_format','CC-CEDICT V2'); BEGIN IMMEDIATE;
""")
let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
func prepare(_ sql: String) throws -> OpaquePointer { var s: OpaquePointer?; guard sqlite3_prepare_v2(database, sql, -1, &s, nil) == SQLITE_OK, let s else { throw BuildError.sqlite(String(cString: sqlite3_errmsg(database))) }; return s }
func run(_ statement: OpaquePointer) throws { guard sqlite3_step(statement) == SQLITE_DONE else { throw BuildError.sqlite(String(cString: sqlite3_errmsg(database))) }; sqlite3_reset(statement); sqlite3_clear_bindings(statement) }
func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) { sqlite3_bind_text(statement, index, value, -1, transient) }
let lexemeStatement = try prepare("INSERT INTO lexemes VALUES (?,?,?,?,?,?,?,?,?,?)")
let senseStatement = try prepare("INSERT INTO translation_senses VALUES (?,?,?,?,?,?,?,?)")
let glossStatement = try prepare("INSERT INTO translation_glosses VALUES (?,?,?)")
var senseCount = 0, glossCount = 0
for row in allLexemes {
    for (index, value) in [row.id, row.pinyin, row.normalizedPinyin, row.pronunciationKey, row.traditional, row.chinese].enumerated() { bind(value, lexemeStatement, Int32(index + 1)) }
    sqlite3_bind_int64(lexemeStatement, 7, sqlite3_int64(row.frequency)); sqlite3_bind_int(lexemeStatement, 8, row.isProperNoun ? 1 : 0)
    sqlite3_bind_int(lexemeStatement, 9, Int32(row.senses.map(\.commonnessRank).min() ?? 9999)); bind(row.source, lexemeStatement, 10); try run(lexemeStatement)
    let ordered = row.senses.enumerated().sorted { $0.element.commonnessRank == $1.element.commonnessRank ? $0.offset < $1.offset : $0.element.commonnessRank < $1.element.commonnessRank }
    for (senseOrder, indexed) in ordered.enumerated() {
        let sense = indexed.element, senseID = row.id + ":en:" + String(senseOrder)
        bind(senseID, senseStatement, 1); bind(row.id, senseStatement, 2); bind("en", senseStatement, 3)
        sqlite3_bind_int(senseStatement, 4, Int32(senseOrder)); sqlite3_bind_int(senseStatement, 5, Int32(sense.commonnessRank))
        if let label = sense.usageLabel { bind(label, senseStatement, 6) } else { sqlite3_bind_null(senseStatement, 6) }
        bind(sense.domain, senseStatement, 7); bind(sense.style, senseStatement, 8); try run(senseStatement); senseCount += 1
        for (glossOrder, gloss) in sense.glosses.enumerated() { bind(senseID, glossStatement, 1); sqlite3_bind_int(glossStatement, 2, Int32(glossOrder)); bind(gloss, glossStatement, 3); try run(glossStatement); glossCount += 1 }
    }
}
try execute("COMMIT; PRAGMA optimize;")
sqlite3_finalize(lexemeStatement); sqlite3_finalize(senseStatement); sqlite3_finalize(glossStatement)
guard sqlite3_close(database) == SQLITE_OK else { throw BuildError.sqlite("could not finalize database") }
databaseIsOpen = false
try? FileManager.default.removeItem(at: outputURL); try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
print("Built \(outputURL.path) with \(allLexemes.count) lexemes, \(senseCount) senses, and \(glossCount) glosses.")
