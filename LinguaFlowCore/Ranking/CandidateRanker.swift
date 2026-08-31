import Foundation

public enum CandidateRanker {
    public static func rank(
        _ candidates: [Candidate],
        for input: String,
        selectionCounts: [String: Int]
    ) -> [Candidate] {
        let normalizedInput = PinyinNormalizer.normalize(input)
        return candidates.enumerated().sorted { lhs, rhs in
            let lhsScore = score(lhs.element, normalizedInput, selectionCounts)
            let rhsScore = score(rhs.element, normalizedInput, selectionCounts)
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private static func score(
        _ candidate: Candidate,
        _ normalizedInput: String,
        _ selectionCounts: [String: Int]
    ) -> Int64 {
        let exactBonus: Int64 = PinyinNormalizer.normalize(candidate.pinyin) == normalizedInput
            ? 1_000_000_000
            : 0
        let selectionBonus = Int64(selectionCounts[candidate.id, default: 0]) * 50_000
        let phraseBonus = Int64(max(0, candidate.sourceText.count - 1)) * 100
        return exactBonus + Int64(candidate.frequency) + selectionBonus + phraseBonus
    }
}
