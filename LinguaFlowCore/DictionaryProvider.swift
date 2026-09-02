import CoreServices
import Foundation

public struct DictionaryEntry: Equatable, Sendable {
    public let term: String
    public let definition: String

    public init(term: String, definition: String) {
        self.term = term
        self.definition = definition
    }
}

public protocol DictionaryProviding: Sendable {
    func lookup(_ term: String) -> DictionaryEntry?
}

public struct AppleDictionaryProvider: DictionaryProviding {
    public init() {}

    public func lookup(_ rawTerm: String) -> DictionaryEntry? {
        let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return nil }

        var definitions: [(String, String)] = []
        for lookupTerm in DictionaryLookupPlanner.lookupTerms(for: term) {
            guard let definition = definition(for: lookupTerm) else { continue }
            definitions.append((lookupTerm, definition))
            if definitions.count == 3 { break }
        }
        guard !definitions.isEmpty else { return nil }

        let combined = definitions.count == 1
            ? definitions[0].1
            : definitions.map { "\($0.0)\n\($0.1)" }.joined(separator: "\n\n")
        return DictionaryEntry(term: term, definition: combined)
    }

    private func definition(for term: String) -> String? {
        let range = CFRange(location: 0, length: (term as NSString).length)
        return DCSCopyTextDefinition(nil, term as CFString, range)?.takeRetainedValue() as String?
    }
}

public enum DictionaryLookupPlanner {
    public static func lookupTerms(for rawGloss: String) -> [String] {
        let normalized = rawGloss
            .replacingOccurrences(of: "…", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        var terms: [String] = [normalized]
        let alternatives = normalized.split(whereSeparator: { ";/|,".contains($0) })
            .map(String.init)
        terms.append(contentsOf: alternatives)

        for alternative in alternatives.isEmpty ? [normalized] : alternatives {
            var cleaned = alternative
                .replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            for prefix in ["to ", "a ", "an ", "the ", "one's ", "sb's "] where cleaned.lowercased().hasPrefix(prefix) {
                cleaned.removeFirst(prefix.count)
                break
            }
            if !cleaned.isEmpty { terms.append(cleaned) }
            if let headword = cleaned.split(separator: " ").first, headword.count > 2 {
                terms.append(String(headword))
            }
        }

        var seen: Set<String> = []
        return terms.compactMap {
            let term = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = term.lowercased()
            guard !term.isEmpty, seen.insert(key).inserted else { return nil }
            return term
        }
    }
}

public final class DictionaryCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: DictionaryEntry] = [:]
    private var misses: Set<String> = []

    public init() {}

    public func value(for term: String, loader: () -> DictionaryEntry?) -> DictionaryEntry? {
        lock.lock()
        if let cached = entries[term] { lock.unlock(); return cached }
        if misses.contains(term) { lock.unlock(); return nil }
        lock.unlock()
        let loaded = loader()
        lock.lock()
        if let loaded { entries[term] = loaded } else { misses.insert(term) }
        lock.unlock()
        return loaded
    }
}

public struct DictionaryCardContent: Equatable, Sendable {
    public let headword: String
    public let pronunciation: String?
    public let partOfSpeech: String?
    public let englishDefinition: String
    public let examples: [String]
    public let phrasesAndIdioms: [DictionaryPhraseEntry]

    public init(
        headword: String,
        pronunciation: String?,
        partOfSpeech: String?,
        englishDefinition: String,
        examples: [String],
        phrasesAndIdioms: [DictionaryPhraseEntry]
    ) {
        self.headword = headword
        self.pronunciation = pronunciation
        self.partOfSpeech = partOfSpeech
        self.englishDefinition = englishDefinition
        self.examples = examples
        self.phrasesAndIdioms = phrasesAndIdioms
    }
}

public struct DictionaryPhraseEntry: Equatable, Sendable {
    public let category: String
    public let expression: String
    public let explanation: String?

    public init(category: String, expression: String, explanation: String?) {
        self.category = category
        self.expression = expression
        self.explanation = explanation
    }
}

public enum DictionaryCardContentParser {
    private static let sectionHeaders = ["PHRASES", "PHRASAL VERBS", "IDIOMS", "DERIVATIVES", "ORIGIN", "USAGE"]
    private static let partsOfSpeech = ["noun", "verb", "adjective", "adverb", "preposition", "pronoun", "determiner", "conjunction", "exclamation"]

    public static func parse(_ rawDefinition: String, fallbackTerm: String) -> DictionaryCardContent {
        let normalized = rawDefinition.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let firstBlock = rawDefinition.components(separatedBy: "\n\n").first ?? rawDefinition
        let blockLines = firstBlock.split(separator: "\n", maxSplits: 1).map(String.init)
        let raw = (blockLines.count == 2 ? blockLines[1] : blockLines[0])
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let pronunciation = firstMatch(in: raw, pattern: #"\|\s*([^|]+?)\s*\|"#, group: 1)
        let partOfSpeech = partsOfSpeech.first { raw.range(of: #"\b\#($0)\b"#, options: .regularExpression) != nil }
        let headword: String = {
            if blockLines.count == 2 { return blockLines[0].trimmingCharacters(in: .whitespacesAndNewlines) }
            let beforePronunciation = raw.components(separatedBy: "|").first ?? fallbackTerm
            return beforePronunciation.split(separator: " ").first.map(String.init) ?? fallbackTerm
        }()

        let mainEnd = sectionHeaders.compactMap { raw.range(of: " \($0) ")?.lowerBound }.min() ?? raw.endIndex
        var main = String(raw[..<mainEnd])
        if let partOfSpeech, let range = main.range(of: #"\b\#(partOfSpeech)\b"#, options: .regularExpression) {
            main = String(main[range.upperBound...])
        }
        let summary = (main.components(separatedBy: ":").first ?? main)
            .replacingOccurrences(of: #"^\s*\d+\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let examples = matches(in: main, pattern: #":\s*([^•]+?)(?=\s+•|\s+\d+\s+|$)"#)
            .flatMap { $0.components(separatedBy: " | ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "."))) }
            .filter { !$0.isEmpty && $0.count < 240 }
            .prefix(4)

        let phraseEntries = ["PHRASES", "PHRASAL VERBS", "IDIOMS"].flatMap { header -> [DictionaryPhraseEntry] in
            guard let start = raw.range(of: " \(header) ") else { return [] }
            let remainder = raw[start.upperBound...]
            let end = sectionHeaders.compactMap { candidate in
                remainder.range(of: " \(candidate) ")?.lowerBound
            }.min() ?? remainder.endIndex
            let section = String(remainder[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            return parsePhraseEntries(section, category: categoryTitle(for: header))
        }

        return DictionaryCardContent(
            headword: headword,
            pronunciation: pronunciation,
            partOfSpeech: partOfSpeech,
            englishDefinition: summary.isEmpty ? normalized : summary,
            examples: Array(examples),
            phrasesAndIdioms: phraseEntries
        )
    }

    private static func parsePhraseEntries(_ section: String, category: String) -> [DictionaryPhraseEntry] {
        let colonRanges = section.ranges(of: ":")
        guard !colonRanges.isEmpty else {
            return section.isEmpty ? [] : [.init(category: category, expression: section, explanation: nil)]
        }

        var entries: [DictionaryPhraseEntry] = []
        var currentHead = String(section[..<colonRanges[0].lowerBound])
        var explanationStart = colonRanges[0].upperBound

        for colonRange in colonRanges.dropFirst() {
            let between = String(section[explanationStart..<colonRange.lowerBound])
            let boundary = lastSentenceBoundary(in: between)
            let explanation = String(between[..<boundary]).trimmingCharacters(in: .whitespacesAndNewlines)
            appendPhraseEntry(headAndDefinition: currentHead, example: explanation, category: category, to: &entries)
            currentHead = String(between[boundary...])
            explanationStart = colonRange.upperBound
        }

        let finalExplanation = String(section[explanationStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if let boundary = firstSentenceBoundary(in: finalExplanation) {
            let trailingHead = String(finalExplanation[boundary...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let trailingParts = splitExpressionAndDefinition(trailingHead)
            if trailingParts.definition != nil {
                let currentExplanation = String(finalExplanation[..<boundary]).trimmingCharacters(in: .whitespacesAndNewlines)
                appendPhraseEntry(headAndDefinition: currentHead, example: currentExplanation, category: category, to: &entries)
                appendPhraseEntry(headAndDefinition: trailingHead, example: "", category: category, to: &entries)
                return entries
            }
        }
        appendPhraseEntry(headAndDefinition: currentHead, example: finalExplanation, category: category, to: &entries)
        return entries
    }

    private static func appendPhraseEntry(
        headAndDefinition: String,
        example: String,
        category: String,
        to entries: inout [DictionaryPhraseEntry]
    ) {
        let parts = splitExpressionAndDefinition(headAndDefinition)
        let explanation = [parts.definition, example]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard !parts.expression.isEmpty else { return }
        entries.append(.init(
            category: category,
            expression: parts.expression,
            explanation: explanation.isEmpty ? nil : explanation
        ))
    }

    private static func splitExpressionAndDefinition(_ raw: String) -> (expression: String, definition: String?) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let starters = [
            " be ", " provide ", " derive ", " trying ", " while ", " cease ", " carry ",
            " attempt ", " collide ", " become ", " have ", " talk ", " force ", " dominate ",
            " suffer ", " chase ", " find ", " fall ", " meet ", " leave ", " continue ",
            " use ", " accept ", " experience ", " reach ", " extend ", " proceed ", " associate ",
            " criticize ", " discover ", " stop ", " cause ", " win ", " tell ", " blend ",
            " abandon ", " raise ", " make ", " allow ", " achieve ", " exceed ", " overflow ",
            " knock ", " spend ", " show ", " try ", " without ", " intended ", " indulge ",
            " an ", " the ",
        ]
        let splitRange = starters.compactMap { text.range(of: $0, options: .caseInsensitive) }
            .filter { text.distance(from: text.startIndex, to: $0.lowerBound) >= 3 }
            .min { $0.lowerBound < $1.lowerBound }
        guard let splitRange else { return (text, nil) }
        let expression = String(text[..<splitRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let definition = String(text[splitRange.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (expression, definition)
    }

    private static func lastSentenceBoundary(in text: String) -> String.Index {
        guard let regex = try? NSRegularExpression(pattern: #"[.!?]\s+"#),
              let match = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
              let range = Range(match.range, in: text) else { return text.startIndex }
        return range.upperBound
    }

    private static func firstSentenceBoundary(in text: String) -> String.Index? {
        guard let regex = try? NSRegularExpression(pattern: #"[.!?]\s+"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text),
              range.upperBound < text.endIndex else { return nil }
        return range.upperBound
    }

    private static func categoryTitle(for header: String) -> String {
        switch header {
        case "PHRASAL VERBS": return "Phrasal verb"
        case "IDIOMS": return "Idiom"
        default: return "Phrase / Idiom"
        }
    }

    private static func firstMatch(in text: String, pattern: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range])
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            guard let range = Range($0.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }
}

private extension String {
    func ranges(of searchString: String) -> [Range<String.Index>] {
        var results: [Range<String.Index>] = []
        var searchStart = startIndex
        while searchStart < endIndex,
              let range = range(of: searchString, range: searchStart..<endIndex) {
            results.append(range)
            searchStart = range.upperBound
        }
        return results
    }
}
