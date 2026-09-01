import Foundation

public protocol ExampleRepository: Sendable {
    func phraseCandidates(for input: String, targetLanguage: String, limit: Int) -> [Candidate]
    func examples(for term: String, limit: Int) -> [ExampleSentence]
}

public extension ExampleRepository {
    func phraseCandidates(for input: String, limit: Int) -> [Candidate] {
        phraseCandidates(for: input, targetLanguage: "en", limit: limit)
    }
}
