import Foundation

public protocol LexiconRepository: Sendable {
    func candidates(for input: String, targetLanguage: String, limit: Int) -> [Candidate]
    func prefixCandidates(for input: String, targetLanguage: String, limit: Int) -> [Candidate]
}

public extension LexiconRepository {
    func candidates(for input: String, limit: Int) -> [Candidate] {
        candidates(for: input, targetLanguage: "en", limit: limit)
    }

    func prefixCandidates(for input: String, limit: Int) -> [Candidate] {
        prefixCandidates(for: input, targetLanguage: "en", limit: limit)
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

    public func prefixCandidates(
        for input: String,
        targetLanguage: String,
        limit: Int
    ) -> [Candidate] {
        let normalized = PinyinNormalizer.normalize(input)
        guard !normalized.isEmpty, limit > 0 else { return [] }
        return candidatesByInput
            .filter { $0.key.hasPrefix(normalized) }
            .flatMap(\.value)
            .filter { $0.targetLanguage == targetLanguage }
            .sorted { $0.frequency > $1.frequency }
            .prefix(limit)
            .map { $0 }
    }
}
