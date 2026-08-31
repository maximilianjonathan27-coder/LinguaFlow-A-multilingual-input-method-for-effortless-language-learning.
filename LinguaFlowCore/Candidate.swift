import Foundation

public struct Candidate: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let pinyin: String
    public let sourceText: String
    public let translation: String

    public init(id: String, pinyin: String, sourceText: String, translation: String) {
        self.id = id
        self.pinyin = pinyin
        self.sourceText = sourceText
        self.translation = translation
    }
}
