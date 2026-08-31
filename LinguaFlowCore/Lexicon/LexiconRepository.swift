import Foundation

public protocol LexiconRepository: Sendable {
    func candidates(for input: String, targetLanguage: String, limit: Int) -> [Candidate]
}

public extension LexiconRepository {
    func candidates(for input: String, limit: Int) -> [Candidate] {
        candidates(for: input, targetLanguage: "en", limit: limit)
    }
}

public struct InMemoryLexicon: LexiconRepository {
    private let candidatesByInput: [String: [Candidate]]

    public init(candidates: [Candidate]) {
        candidatesByInput = Dictionary(grouping: candidates) {
            PinyinNormalizer.normalize($0.pinyin)
        }
    }

    public func candidates(
        for input: String,
        targetLanguage: String,
        limit: Int
    ) -> [Candidate] {
        guard limit > 0 else { return [] }
        return candidatesByInput[PinyinNormalizer.normalize(input), default: []]
            .filter { $0.targetLanguage == targetLanguage }
            .prefix(limit)
            .map { $0 }
    }
}
