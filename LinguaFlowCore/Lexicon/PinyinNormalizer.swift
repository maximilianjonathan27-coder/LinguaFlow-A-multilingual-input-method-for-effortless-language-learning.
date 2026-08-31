import Foundation

public enum PinyinNormalizer {
    public static func normalize(_ input: String) -> String {
        input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isASCII && $0.isLetter }
    }
}
