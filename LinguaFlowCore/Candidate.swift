import Foundation

public struct Candidate: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let pinyin: String
    public let sourceText: String
    public let translation: String
    public let frequency: Int
    public let targetLanguage: String
    public let partOfSpeech: String?
    public let domain: String
    public let style: String
    public let translationSenses: [TranslationSense]
    public let isProperNoun: Bool
    public let examples: [ExampleSentence]

    public init(
        id: String,
        pinyin: String,
        sourceText: String,
        translation: String,
        frequency: Int = 0,
        targetLanguage: String = "en",
        partOfSpeech: String? = nil,
        domain: String = "general",
        style: String = "neutral",
        translationSenses: [TranslationSense] = [],
        isProperNoun: Bool = false,
        examples: [ExampleSentence] = []
    ) {
        self.id = id
        self.pinyin = pinyin
        self.sourceText = sourceText
        self.translation = translation
        self.frequency = frequency
        self.targetLanguage = targetLanguage
        self.partOfSpeech = partOfSpeech
        self.domain = domain
        self.style = style
        self.translationSenses = translationSenses
        self.isProperNoun = isProperNoun
        self.examples = examples
    }
}
