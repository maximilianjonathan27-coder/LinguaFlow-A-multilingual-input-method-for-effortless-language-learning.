import Foundation

@MainActor
public protocol SpeechProviding: AnyObject {
    var onSpeechFinished: (() -> Void)? { get set }
    @discardableResult func speak(_ text: String, language: String?) -> Bool
    func stop()
}

public enum SpeechLanguageResolver {
    public static func preferredLanguageCodes(for rawLanguage: String?) -> [String] {
        guard let rawLanguage else { return [] }
        let normalized = rawLanguage
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        guard !normalized.isEmpty else { return [] }

        var codes = [normalized]
        if let baseLanguage = normalized.split(separator: "-").first.map(String.init),
           baseLanguage.caseInsensitiveCompare(normalized) != .orderedSame {
            codes.append(baseLanguage)
        }
        return codes
    }
}

@MainActor
public final class PronunciationController {
    public var onPronunciationPlayed: ((Candidate) -> Void)?
    public var onSpeakingCandidateChanged: ((String?) -> Void)?
    public private(set) var speakingCandidateID: String?
    private let speechProvider: any SpeechProviding

    public init(speechProvider: any SpeechProviding) {
        self.speechProvider = speechProvider
        speechProvider.onSpeechFinished = { [weak self] in
            self?.setSpeakingCandidate(nil)
        }
    }

    @discardableResult
    public func pronounce(_ candidate: Candidate) -> Bool {
        let text = (candidate.sourceLanguage == .english
            ? candidate.sourceText
            : candidate.translation).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }

        let language = (candidate.sourceLanguage == .english
            ? candidate.sourceLanguage.rawValue
            : candidate.targetLanguage).trimmingCharacters(in: .whitespacesAndNewlines)
        guard speechProvider.speak(text, language: language.isEmpty ? nil : language) else {
            setSpeakingCandidate(nil)
            return false
        }
        setSpeakingCandidate(candidate.id)
        onPronunciationPlayed?(candidate)
        return true
    }

    public func stop() {
        speechProvider.stop()
        setSpeakingCandidate(nil)
    }

    private func setSpeakingCandidate(_ candidateID: String?) {
        guard speakingCandidateID != candidateID else { return }
        speakingCandidateID = candidateID
        onSpeakingCandidateChanged?(candidateID)
    }
}
