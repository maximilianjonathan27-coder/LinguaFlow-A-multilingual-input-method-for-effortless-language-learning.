import Foundation

struct Candidate: Identifiable, Hashable, Sendable {
    let id: String
    let pinyin: String
    let sourceText: String
    let translation: String
}
