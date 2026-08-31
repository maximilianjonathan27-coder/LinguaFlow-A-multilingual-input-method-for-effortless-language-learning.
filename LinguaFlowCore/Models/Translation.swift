import Foundation

public struct Translation: Hashable, Codable, Sendable {
    public let lexemeID: String
    public let targetLanguage: String
    public let text: String
    public let partOfSpeech: String?
    public let domain: String
    public let style: String

    public init(
        lexemeID: String,
        targetLanguage: String,
        text: String,
        partOfSpeech: String? = nil,
        domain: String = "general",
        style: String = "neutral"
    ) {
        self.lexemeID = lexemeID
        self.targetLanguage = targetLanguage
        self.text = text
        self.partOfSpeech = partOfSpeech
        self.domain = domain
        self.style = style
    }
}
