import Foundation

public struct PinyinDecoder: Sendable {
    private struct Path {
        let candidates: [Candidate]
        let score: Int64
    }

    private let lexicon: any LexiconRepository
    private let examples: (any ExampleRepository)?
    private let targetLanguage: String

    public init(
        lexicon: any LexiconRepository,
        examples: (any ExampleRepository)? = nil,
        targetLanguage: String = "en"
    ) {
        self.lexicon = lexicon
        self.examples = examples
        self.targetLanguage = targetLanguage
    }

    public func candidates(for input: String, limit: Int = 50) -> [Candidate] {
        let normalized = PinyinNormalizer.normalize(input)
        guard !normalized.isEmpty, limit > 0 else { return [] }

        let exactPhrases = examples?.phraseCandidates(
            for: normalized,
            targetLanguage: targetLanguage,
            limit: limit
        ) ?? []
        let lexiconCandidates = lexicon.candidates(
            for: normalized,
            targetLanguage: targetLanguage,
            limit: limit
        ).map { attachingExamples(to: $0) }
        let rawExactCandidates = exactPhrases.isEmpty ? lexiconCandidates : exactPhrases
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
                if results.isEmpty {
                    results = corrections
                } else {
                    // A complete multi-syllable decode is stronger evidence than
                    // a one-key typo guess. Keep corrections available without
                    // letting `nidianba` displace valid `ni xian ba` decoding.
                    results.append(contentsOf: corrections)
                }
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
        guard !initialComponents.isEmpty else { return [] }

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
                let phraseWords = examples?.phraseCandidates(
                    for: chunk,
                    targetLanguage: targetLanguage,
                    limit: 6
                ) ?? []
                let rawWords = phraseWords.isEmpty ? lexicon.candidates(
                    for: chunk,
                    targetLanguage: targetLanguage,
                    limit: 6
                ) : phraseWords
                let words = rawWords.filter(isChineseCandidate)
                guard !words.isEmpty else { continue }
                for path in paths[start].prefix(12) {
                    for word in words {
                        let frequencyScore = Int64(log(Double(max(1, word.frequency))) * 1_000)
                        // A small cohesion bonus keeps genuine common words together,
                        // while frequency still decides whether a split is plausible.
                        // The previous 25,000-point bonus made any two-character word
                        // dominate, so `nixianba` became `逆袭 + 按 + 把` instead of
                        // the much more frequent `你 + 先 + 把`.
                        let cohesionBonus = Int64(max(0, word.sourceText.count - 1)) * 3_000
                        let reviewedPhraseBonus: Int64 = word.id.hasPrefix("phrase.")
                            ? 30_000
                            : 0
                        let wordScore = frequencyScore
                            + cohesionBonus
                            + reviewedPhraseBonus
                            - 16_000
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
        return Candidate(
            id: "sentence:" + path.candidates.map(\.id).joined(separator: "+"),
            pinyin: input,
            sourceText: path.candidates.map(\.sourceText).joined(),
            // A word-by-word gloss is not a trustworthy sentence translation.
            translation: "",
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

    private func attachingExamples(to candidate: Candidate) -> Candidate {
        guard candidate.examples.isEmpty,
              let sentenceExamples = examples?.examples(for: candidate.sourceText, limit: 3),
              !sentenceExamples.isEmpty
        else { return candidate }
        return Candidate(
            id: candidate.id,
            pinyin: candidate.pinyin,
            sourceText: candidate.sourceText,
            translation: candidate.translation,
            frequency: candidate.frequency,
            targetLanguage: candidate.targetLanguage,
            partOfSpeech: candidate.partOfSpeech,
            domain: candidate.domain,
            style: candidate.style,
            translationSenses: candidate.translationSenses,
            isProperNoun: candidate.isProperNoun,
            examples: sentenceExamples
        )
    }

    private static let commonSyllables: Set<String> = Set("""
    a ai an ang ao ba bai ban bang bao bei ben beng bi bian biao bie bin bing bo bu
    ca cai can cang cao ce cen ceng cha chai chan chang chao che chen cheng chi chong chou chu chua chuai chuan chuang chui chun chuo ci cong cou cu cuan cui cun cuo
    da dai dan dang dao de dei den deng di dia dian diao die ding diu dong dou du duan dui dun duo
    e ei en eng er fa fan fang fei fen feng fo fou fu
    ga gai gan gang gao ge gei gen geng gong gou gu gua guai guan guang gui gun guo
    ha hai han hang hao he hei hen heng hong hou hu hua huai huan huang hui hun huo
    ji jia jian jiang jiao jie jin jing jiong jiu ju juan jue jun
    ka kai kan kang kao ke ken keng kong kou ku kua kuai kuan kuang kui kun kuo
    la lai lan lang lao le lei leng li lia lian liang liao lie lin ling liu lo long lou lu luan lun luo lv lve
    ma mai man mang mao me mei men meng mi mian miao mie min ming miu mo mou mu
    na nai nan nang nao ne nei nen neng ni nian niang niao nie nin ning niu nong nou nu nuan nuo nv nve
    o ou pa pai pan pang pao pei pen peng pi pian piao pie pin ping po pou pu
    qi qia qian qiang qiao qie qin qing qiong qiu qu quan que qun
    ran rang rao re ren reng ri rong rou ru rua ruan rui run ruo
    sa sai san sang sao se sen seng sha shai shan shang shao she shei shen sheng shi shou shu shua shuai shuan shuang shui shun shuo si song sou su suan sui sun suo
    ta tai tan tang tao te teng ti tian tiao tie ting tong tou tu tuan tui tun tuo
    wa wai wan wang wei wen weng wo wu
    xi xia xian xiang xiao xie xin xing xiong xiu xu xuan xue xun
    ya yan yang yao ye yi yin ying yo yong you yu yuan yue yun
    za zai zan zang zao ze zei zen zeng zha zhai zhan zhang zhao zhe zhei zhen zheng zhi zhong zhou zhu zhua zhuai zhuan zhuang zhui zhun zhuo zi zong zou zu zuan zui zun zuo
    """.split(whereSeparator: \.isWhitespace).map(String.init))

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
            style: style,
            translationSenses: translationSenses,
            isProperNoun: isProperNoun,
            examples: examples
        )
    }
}
