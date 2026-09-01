import Foundation

public enum CandidateRanker {
    public static func rank(
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
        let isExact = PinyinNormalizer.normalize(candidate.pinyin) == normalizedInput
        let exactBonus: Int64 = isExact ? 5_000_000 : 0
        let frequencyScore = Int64(log1p(Double(max(0, candidate.frequency))) * 100_000)
        let selectionBonus = Int64(selectionCounts[candidate.id, default: 0]) * 75_000
        let coverageBonus = Int64(matchedPrefixLength(candidate, normalizedInput)) * 1_500_000

        // Long entries are often titles, organization names, or imported proper nouns.
        // Keep them searchable, but do not let a noisy source frequency place them ahead
        // of everyday words while the user has only typed a short prefix.
        let longEntryPenalty: Int64 = isExact || candidate.domain == "english"
            ? 0
            : Int64(max(0, candidate.sourceText.count - 2)) * 150_000
        let missingTranslationPenalty: Int64 = candidate.translation.isEmpty ? 75_000 : 0
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
