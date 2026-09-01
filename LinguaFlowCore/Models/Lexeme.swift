import Foundation

public struct Lexeme: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let pinyin: String
    public let normalizedPinyin: String
    public let chinese: String
    public let frequency: Int

    public init(id: String, pinyin: String, chinese: String, frequency: Int) {
        self.id = id
        self.pinyin = pinyin
        normalizedPinyin = PinyinNormalizer.normalize(pinyin)
        self.chinese = chinese
        self.frequency = frequency
    }
}
