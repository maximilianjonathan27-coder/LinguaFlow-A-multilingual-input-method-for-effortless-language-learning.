import Foundation

public struct PinyinDecoder: Sendable {
    private struct Path {
        let candidates: [Candidate]
        let score: Int64
    }

    private let lexicon: any LexiconRepository
    private let targetLanguage: String

    public init(lexicon: any LexiconRepository, targetLanguage: String = "en") {
        self.lexicon = lexicon
        self.targetLanguage = targetLanguage
    }

    public func candidates(for input: String, limit: Int = 50) -> [Candidate] {
        let normalized = PinyinNormalizer.normalize(input)
        guard !normalized.isEmpty, limit > 0 else { return [] }

        let rawExactCandidates = lexicon.candidates(
            for: normalized,
            targetLanguage: targetLanguage,
            limit: limit
        )
        let inferredSentences = rawExactCandidates.contains { $0.translation.isEmpty }
            ? decodedSentences(for: normalized, limit: limit)
            : []
        let inferredTranslations = Dictionary(
            inferredSentences
                .filter { !$0.translation.isEmpty }
                .map { ($0.sourceText, $0.translation) },
            uniquingKeysWith: { first, _ in first }
        )
        let exactCandidates = rawExactCandidates.map { candidate in
            guard candidate.translation.isEmpty,
                  let translation = inferredTranslations[candidate.sourceText]
            else { return candidate }
            return candidate.replacingTranslation(translation)
        }
        let fallbackCharacters = characterCandidates(
            for: normalized,
            exactCandidates: exactCandidates,
            limit: limit
        )
        let mixedAbbreviations = mixedAbbreviationCandidates(
            for: normalized,
            limit: limit
        )
        var results: [Candidate]
        if exactCandidates.isEmpty, !mixedAbbreviations.isEmpty {
            results = mixedAbbreviations
        } else if exactCandidates.isEmpty {
            let decoded = inferredSentences.isEmpty
                ? decodedSentences(for: normalized, limit: limit)
                : inferredSentences
            let translated = decoded.filter { !$0.translation.isEmpty }
            results = Array((translated.isEmpty ? decoded : translated).prefix(5))
        } else if fallbackCharacters.isEmpty {
            results = exactCandidates
        } else {
            let commonWords = exactCandidates.filter {
                !$0.translation.isEmpty
                    && ($0.sourceText.count == 1 || $0.frequency >= 10_000)
            }
            let translatedExact = exactCandidates.filter { !$0.translation.isEmpty }
            let completeWords = translatedExact.filter { $0.sourceText.count > 1 }
            if !commonWords.isEmpty {
                results = Array(commonWords.prefix(5)) + completeWords
            } else if !translatedExact.isEmpty {
                results = Array(translatedExact.prefix(5)) + completeWords
            } else {
                results = Array(exactCandidates.prefix(1))
            }
        }

        let hasCompleteEnding = hasCompletePinyinEnding(normalized)
        if rawExactCandidates.isEmpty, hasCompleteEnding {
            let corrections = preferredFallbackCandidates(
                lexicon.correctionCandidates(
                    for: normalized,
                    targetLanguage: targetLanguage,
                    limit: limit
                )
            )
            if !corrections.isEmpty {
                results.insert(contentsOf: corrections, at: 0)
            }
        }

        if results.isEmpty || !hasCompleteEnding {
            results.append(contentsOf: lexicon.prefixCandidates(
                for: normalized,
                targetLanguage: targetLanguage,
                limit: limit
            ))
        }

        if results.isEmpty {
            results.append(contentsOf: preferredFallbackCandidates(
                lexicon.abbreviationCandidates(
                    for: normalized,
                    targetLanguage: targetLanguage,
                    limit: limit
                )
            ))
        }

        if results.isEmpty, !hasCompleteEnding {
            results.append(contentsOf: preferredFallbackCandidates(
                lexicon.correctionCandidates(
                    for: normalized,
                    targetLanguage: targetLanguage,
                    limit: limit
                )
            ))
        }

        results.append(contentsOf: partialPrefixCandidates(for: normalized, limit: limit))
        results.append(contentsOf: fallbackCharacters)
        let englishCandidates = EnglishWordCatalog.candidates(
            for: normalized,
            limit: min(12, limit)
        )
        if !englishCandidates.isEmpty {
            let chineseLimit = max(0, limit - englishCandidates.count)
            results = Array(results.prefix(chineseLimit)) + englishCandidates
        }

        var seenTexts: Set<String> = []
        return results
            .filter { seenTexts.insert($0.sourceText).inserted }
            .prefix(limit)
            .map { $0 }
    }

    /// Supports the mixed spelling commonly used by Chinese IMEs, where complete
    /// syllables and initials can appear together: `ni k y` -> `ni ke yi`.
    private func mixedAbbreviationCandidates(for input: String, limit: Int) -> [Candidate] {
        let components = PinyinNormalizer.segments(for: input)
        guard components.count > 1 else { return [] }

        let initialComponents = components.filter(isPinyinInitial)
        guard !initialComponents.isEmpty,
              initialComponents.count < components.count
        else { return [] }

        return abbreviationCandidates(matching: components, limit: limit)
    }

    /// After complete phrase candidates, a normal Pinyin IME also offers shorter
    /// prefix choices. With `n k y`, for example, `你看` consumes `n k` and `你`
    /// consumes `n`, leaving the remaining initials available for composition.
    private func partialPrefixCandidates(for input: String, limit: Int) -> [Candidate] {
        let components = PinyinNormalizer.segments(for: input)
        guard components.count > 1,
              components.contains(where: isPinyinInitial)
        else { return [] }

        var results: [Candidate] = []
        for componentCount in stride(from: components.count - 1, through: 1, by: -1) {
            let prefix = Array(components.prefix(componentCount))
            if componentCount == 1, let first = prefix.first {
                let matches = isPinyinInitial(first)
                    ? lexicon.abbreviationCandidates(
                        for: first,
                        targetLanguage: targetLanguage,
                        limit: max(80, limit * 4)
                    )
                    : lexicon.candidates(
                        for: first,
                        targetLanguage: targetLanguage,
                        limit: max(80, limit * 4)
                    )
                results.append(contentsOf: matches.filter {
                    $0.sourceText.count == 1
                        && candidateSyllables($0).count == 1
                        && componentsMatch(prefix, candidateSyllables($0))
                }.prefix(18))
            } else {
                results.append(contentsOf: abbreviationCandidates(
                    matching: prefix,
                    limit: min(24, limit)
                ).filter { $0.sourceText.count == componentCount })
            }
        }
        return Array(results.prefix(limit))
    }

    private func abbreviationCandidates(
        matching components: [String],
        limit: Int
    ) -> [Candidate] {
        let initials = components.compactMap(\.first).map(String.init).joined()
        return lexicon.abbreviationCandidates(
            for: initials,
            targetLanguage: targetLanguage,
            limit: max(200, limit * 20)
        )
        .filter { componentsMatch(components, candidateSyllables($0)) }
        .prefix(limit)
        .map { $0 }
    }

    private func candidateSyllables(_ candidate: Candidate) -> [String] {
        candidate.pinyin.lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0 == "'" })
            .map(String.init)
    }

    private func componentsMatch(_ typed: [String], _ candidate: [String]) -> Bool {
        guard candidate.count == typed.count else { return false }
        return zip(typed, candidate).allSatisfy { typed, candidate in
            isPinyinInitial(typed)
                ? candidate.hasPrefix(typed)
                : candidate == typed
        }
    }

    private func isPinyinInitial(_ component: String) -> Bool {
        Self.pinyinInitials.contains(component)
    }

    private static let pinyinInitials: Set<String> = [
        "b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h",
        "j", "q", "x", "zh", "ch", "sh", "r", "z", "c", "s", "y", "w",
    ]

    private func characterCandidates(
        for input: String,
        exactCandidates: [Candidate],
        limit: Int
    ) -> [Candidate] {
        let hintedSyllables = exactCandidates.first?.pinyin
            .split(whereSeparator: { $0 == " " || $0 == "'" })
            .map(String.init) ?? []
        let syllables: [String]
        if hintedSyllables.count > 1,
           hintedSyllables.joined() == input {
            syllables = hintedSyllables
        } else {
            syllables = PinyinNormalizer.segments(for: input)
        }

        guard syllables.count > 1 else { return [] }
        var characters: [Candidate] = []
        var seenTexts: Set<String> = []
        for syllable in syllables {
            let matches = lexicon.candidates(
                for: syllable,
                targetLanguage: targetLanguage,
                limit: min(24, limit)
            )
            let translatedMatches = matches.filter {
                $0.sourceText.count == 1 && !$0.translation.isEmpty
            }
            let usableMatches = translatedMatches.isEmpty
                ? matches.filter { $0.sourceText.count == 1 }
                : translatedMatches
            for candidate in usableMatches {
                if seenTexts.insert(candidate.sourceText).inserted {
                    characters.append(candidate)
                }
            }
        }
        return Array(characters.prefix(limit))
    }

    private func decodedSentences(for input: String, limit: Int) -> [Candidate] {
        let characters = Array(input)
        guard characters.count > 1 else { return [] }
        var paths = Array(repeating: [Path](), count: characters.count + 1)
        paths[0] = [Path(candidates: [], score: 0)]

        for start in characters.indices where !paths[start].isEmpty {
            let maximumEnd = min(characters.count, start + 24)
            for end in (start + 1)...maximumEnd {
                let chunk = String(characters[start..<end])
                let words = lexicon.candidates(
                    for: chunk,
                    targetLanguage: targetLanguage,
                    limit: 6
                ).filter(isChineseCandidate)
                guard !words.isEmpty else { continue }
                for path in paths[start].prefix(12) {
                    for word in words {
                        let frequencyScore = Int64(log(Double(max(1, word.frequency))) * 1_000)
                        // The old 25,000-point phrase bonus overwhelmed actual
                        // usage frequency, so rare chunks such as `逆袭 + 安邦`
                        // beat the everyday `你 + 先 + 帮` for `nixianbang`.
                        let cohesionBonus = Int64(max(0, word.sourceText.count - 1)) * 3_000
                        let wordScore = frequencyScore + cohesionBonus - 16_000
                        paths[end].append(Path(
                            candidates: path.candidates + [word],
                            score: path.score + wordScore
                        ))
                    }
                }
                paths[end] = Array(paths[end].sorted { $0.score > $1.score }.prefix(18))
            }
        }

        let completePaths = paths[characters.count]
            .filter { $0.candidates.count > 1 }
        if !completePaths.isEmpty {
            return completePaths.prefix(limit).map { sentenceCandidate(from: $0, input: input) }
        }

        // A normal IME keeps the decoded prefix and treats the final letters as an
        // unfinished syllable. For example: ni + bang + w -> 你 + 帮 + 我.
        var completionPaths: [Path] = []
        for tailStart in 1..<characters.count where !paths[tailStart].isEmpty {
            let tail = String(characters[tailStart...])
            guard tail.count <= 6 else { continue }
            let completions = lexicon.prefixCandidates(
                for: tail,
                targetLanguage: targetLanguage,
                limit: 12
            )
            .filter {
                PinyinNormalizer.normalize($0.pinyin) != tail
                    && isChineseCandidate($0)
            }
            guard !completions.isEmpty else { continue }

            for path in paths[tailStart].prefix(12) where !path.candidates.isEmpty {
                for completion in completions {
                    let normalizedCompletion = PinyinNormalizer.normalize(completion.pinyin)
                    let unfinishedLength = max(0, normalizedCompletion.count - tail.count)
                    let frequencyScore = Int64(log(Double(max(1, completion.frequency))) * 1_000)
                    let completionPenalty = Int64(unfinishedLength) * 2_000
                    let longCompletionPenalty = Int64(max(0, completion.sourceText.count - 1))
                        * 10_000
                    completionPaths.append(Path(
                        candidates: path.candidates + [completion],
                        score: path.score + frequencyScore - 20_000
                            - completionPenalty - longCompletionPenalty
                    ))
                }
            }
        }

        return completionPaths
            .filter { $0.candidates.count > 1 }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { sentenceCandidate(from: $0, input: input) }
    }

    private func sentenceCandidate(from path: Path, input: String) -> Candidate {
        let translations = path.candidates.map(\.translation).filter { !$0.isEmpty }
        return Candidate(
            id: "sentence:" + path.candidates.map(\.id).joined(separator: "+"),
            pinyin: input,
            sourceText: path.candidates.map(\.sourceText).joined(),
            translation: translations.count == path.candidates.count
                ? translations.joined(separator: " ")
                : "",
            frequency: Int(min(path.score, Int64(Int.max))),
            targetLanguage: targetLanguage,
            partOfSpeech: "sentence"
        )
    }

    private func hasCompletePinyinEnding(_ input: String) -> Bool {
        PinyinNormalizer.hasCompleteSyllableEnding(input)
    }

    private func isChineseCandidate(_ candidate: Candidate) -> Bool {
        candidate.sourceText.unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
        }
    }

    private func preferredFallbackCandidates(_ candidates: [Candidate]) -> [Candidate] {
        let translated = candidates.filter { !$0.translation.isEmpty }
        return translated.isEmpty ? candidates : translated
    }
}

private extension Candidate {
    func replacingTranslation(_ replacement: String) -> Candidate {
        Candidate(
            id: id,
            pinyin: pinyin,
            sourceText: sourceText,
            translation: replacement,
            frequency: frequency,
            targetLanguage: targetLanguage,
            partOfSpeech: partOfSpeech,
            domain: domain,
            style: style
        )
    }
}
