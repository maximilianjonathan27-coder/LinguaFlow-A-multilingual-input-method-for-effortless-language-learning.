import Foundation

public struct ExampleSentence: Identifiable, Hashable, Codable, Sendable {
    public let id: Int64
    public let chinese: String
    public let english: String
    public let source: String
    public let qualityScore: Int

    public init(id: Int64, chinese: String, english: String, source: String, qualityScore: Int) {
        self.id = id
        self.chinese = chinese
        self.english = english
        self.source = source
        self.qualityScore = qualityScore
    }
}
