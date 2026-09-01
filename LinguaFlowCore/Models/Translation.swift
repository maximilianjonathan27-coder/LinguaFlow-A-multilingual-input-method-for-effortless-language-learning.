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

public struct TranslationSense: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let lexemeID: String
    public let targetLanguage: String
    public let order: Int
    public let commonnessRank: Int
    public let glosses: [String]
    public let usageLabel: String?
    public let domain: String
    public let style: String

    public init(
        id: String,
        lexemeID: String,
        targetLanguage: String,
        order: Int,
        commonnessRank: Int,
        glosses: [String],
        usageLabel: String? = nil,
        domain: String = "general",
        style: String = "neutral"
    ) {
        self.id = id
        self.lexemeID = lexemeID
        self.targetLanguage = targetLanguage
        self.order = order
        self.commonnessRank = commonnessRank
        self.glosses = glosses
        self.usageLabel = usageLabel
        self.domain = domain
        self.style = style
    }
}
