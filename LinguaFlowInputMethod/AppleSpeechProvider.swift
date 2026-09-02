import AVFoundation
import LinguaFlowCore

@MainActor
final class AppleSpeechProvider: NSObject, SpeechProviding, @preconcurrency AVSpeechSynthesizerDelegate {
    var onSpeechFinished: (() -> Void)?
    private let synthesizer = AVSpeechSynthesizer()
    private var activeUtterance: AVSpeechUtterance?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    @discardableResult
    func speak(_ text: String, language: String?) -> Bool {
        synthesizer.stopSpeaking(at: .immediate)
        activeUtterance = nil

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        if let language {
            guard let voice = voice(for: language) else { return false }
            utterance.voice = voice
        }
        activeUtterance = utterance
        synthesizer.speak(utterance)
        return true
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        activeUtterance = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finishIfActive(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finishIfActive(utterance)
    }

    private func finishIfActive(_ utterance: AVSpeechUtterance) {
        guard utterance === activeUtterance else { return }
        activeUtterance = nil
        onSpeechFinished?()
    }

    private func voice(for language: String) -> AVSpeechSynthesisVoice? {
        let requestedCodes = SpeechLanguageResolver.preferredLanguageCodes(for: language)
        for code in requestedCodes {
            if let voice = AVSpeechSynthesisVoice(language: code) {
                return voice
            }
        }

        let installedVoices = AVSpeechSynthesisVoice.speechVoices()
        return requestedCodes.lazy.compactMap { code in
            let prefix = code.lowercased() + "-"
            return installedVoices.first {
                $0.language.caseInsensitiveCompare(code) == .orderedSame
                    || $0.language.lowercased().hasPrefix(prefix)
            }
        }.first
    }
}
