import Foundation

public enum CandidateRanker {
    private static let preferredSingleInitialCandidates: [String: String] = [
        "b": "吧",
        "m": "吗",
        "l": "了",
    ]

    public static func rank(
        _ candidates: [Candidate],
        for input: String,
        selectionCounts: [String: Int]
    ) -> [Candidate] {
        let rimeCandidates = candidates.enumerated().filter {
            $0.element.id.hasPrefix("rime:")
        }
        if !rimeCandidates.isEmpty {
            // Rime's returned sequence is the system's initial ranking. Only a
            // real user commit may change order within that sequence; Seen/
            // exposure counts are deliberately unavailable to this function.
            let learnedRimeCandidates = rimeCandidates.sorted { lhs, rhs in
                let lhsScore = adaptiveRimeScore(
                    originalIndex: lhs.offset,
                    usageCount: selectionCounts[lhs.element.id, default: 0],
                    defaultLift: singleInitialDefaultLift(
                        candidate: lhs.element,
                        input: input
                    )
                )
                let rhsScore = adaptiveRimeScore(
                    originalIndex: rhs.offset,
                    usageCount: selectionCounts[rhs.element.id, default: 0],
                    defaultLift: singleInitialDefaultLift(
                        candidate: rhs.element,
                        input: input
                    )
                )
                if lhsScore != rhsScore { return lhsScore > rhsScore }
                return lhs.offset < rhs.offset
            }.map(\.element)
            let supplementalCandidates = candidates.filter {
                !$0.id.hasPrefix("rime:")
            }
            return learnedRimeCandidates + rankLegacy(
                supplementalCandidates,
                for: input,
                selectionCounts: selectionCounts
            )
        }

        return rankLegacy(candidates, for: input, selectionCounts: selectionCounts)
    }

    private static func adaptiveRimeScore(
        originalIndex: Int,
        usageCount: Int,
        defaultLift: Int = 0
    ) -> Int {
        // Keep the dictionary rank dominant. The square-root curve gives early
        // choices a small useful lift while preventing old/high counts from
        // overwhelming a much more common Rime candidate indefinitely.
        let usageLift = Int(sqrt(Double(max(0, usageCount))) * 2)
        return defaultLift + usageLift - originalIndex
    }

    private static func singleInitialDefaultLift(
        candidate: Candidate,
        input: String
    ) -> Int {
        let normalizedInput = PinyinNormalizer.normalize(input)
        guard normalizedInput.count == 1,
              preferredSingleInitialCandidates[normalizedInput] == candidate.sourceText else {
            return 0
        }

        // Single-letter abbreviation input is unusually ambiguous. Give the
        // most useful conversational particles a modest cold-start lift while
        // still allowing repeated committed choices to personalize the order.
        return 8
    }

    private static func rankLegacy(
        _ candidates: [Candidate],
        for input: String,
        selectionCounts: [String: Int]
    ) -> [Candidate] {
        let normalizedInput = PinyinNormalizer.normalize(input)
        let explicitSegments = input.lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0 == "'" })
            .map(String.init)
        let hasExplicitBoundary = explicitSegments.count > 1
        let hasExactChinese = candidates.contains {
            $0.domain != "english"
                && PinyinNormalizer.normalize($0.pinyin) == normalizedInput
        }
        return candidates.enumerated().sorted { lhs, rhs in
            let lhsPriority = languagePriority(
                lhs.element,
                hasExactChinese: hasExactChinese
            )
            let rhsPriority = languagePriority(
                rhs.element,
                hasExactChinese: hasExactChinese
            )
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }

            let lhsScore = score(
                lhs.element,
                normalizedInput,
                selectionCounts,
                explicitSegments: hasExplicitBoundary ? explicitSegments : []
            )
            let rhsScore = score(
                rhs.element,
                normalizedInput,
                selectionCounts,
                explicitSegments: hasExplicitBoundary ? explicitSegments : []
            )
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private static func languagePriority(
        _ candidate: Candidate,
        hasExactChinese: Bool
    ) -> Int {
        let isEnglish = candidate.domain == "english"

        if isEnglish, !hasExactChinese { return 0 }
        if !isEnglish { return hasExactChinese ? 0 : 1 }
        return 2
    }

    private static func score(
        _ candidate: Candidate,
        _ normalizedInput: String,
        _ selectionCounts: [String: Int],
        explicitSegments: [String]
    ) -> Int64 {
        let isRimeCandidate = candidate.id.hasPrefix("rime:")
        let isExact = PinyinNormalizer.normalize(candidate.pinyin) == normalizedInput
        // librime has already decoded spelling errors, syllable boundaries and
        // sentence probability. Do not run its candidates through the legacy
        // exact/prefix/frequency heuristics again: doing so promoted `这/着/者`
        // ahead of librime's complete `zheggai` suggestions.
        let exactBonus: Int64 = !isRimeCandidate && isExact ? 5_000_000 : 0
        let frequencyScore = isRimeCandidate
            ? 100_000_000
            : Int64(log1p(Double(max(0, candidate.frequency))) * 100_000)
        let selectionBonus = Int64(selectionCounts[candidate.id, default: 0]) * 75_000
        let coverageBonus = isRimeCandidate
            ? 0
            : Int64(matchedPrefixLength(candidate, normalizedInput)) * 1_500_000

        // Long entries are often titles, organization names, or imported proper nouns.
        // Keep them searchable, but do not let a noisy source frequency place them ahead
        // of everyday words while the user has only typed a short prefix.
        let longEntryPenalty: Int64 = isRimeCandidate || isExact || candidate.domain == "english"
            ? 0
            : Int64(max(0, candidate.sourceText.count - 2)) * 150_000
        let missingTranslationPenalty: Int64 = !isRimeCandidate && candidate.translation.isEmpty
            ? 75_000
            : 0
        let candidateSegments = candidate.pinyin.lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0 == "'" })
            .map(String.init)
        let explicitBoundaryBonus: Int64 = !explicitSegments.isEmpty
            && candidateSegments == explicitSegments ? 50_000_000 : 0

        return exactBonus
            + explicitBoundaryBonus
            + coverageBonus
            + frequencyScore
            + selectionBonus
            - longEntryPenalty
            - missingTranslationPenalty
    }

    private static func matchedPrefixLength(_ candidate: Candidate, _ input: String) -> Int {
        let typed = PinyinNormalizer.segments(for: input)
        let syllables = candidate.pinyin.lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0 == "'" })
            .map(String.init)
        // `xian` may represent either one syllable or `xi an`. Both consume the
        // complete composition, so neither should be penalized merely because
        // the normalizer selected the other valid boundary.
        if PinyinNormalizer.normalize(candidate.pinyin) == input {
            return max(1, typed.count)
        }
        guard !typed.isEmpty, syllables.count <= typed.count else { return 0 }

        let initials: Set<String> = [
            "b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h",
            "j", "q", "x", "zh", "ch", "sh", "r", "z", "c", "s", "y", "w",
        ]
        let matches = zip(typed.prefix(syllables.count), syllables).allSatisfy { part, syllable in
            initials.contains(part) ? syllable.hasPrefix(part) : syllable == part
        }
        return matches ? syllables.count : 0
    }
}
