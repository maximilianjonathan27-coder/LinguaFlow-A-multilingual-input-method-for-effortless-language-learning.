import LinguaFlowCore
import XCTest

@MainActor
final class PronunciationControllerTests: XCTestCase {
    func testPronouncesTrimmedTranslationWithCandidateLanguage() {
        let provider = SpeechProviderSpy()
        let controller = PronunciationController(speechProvider: provider)
        var playedCandidate: Candidate?
        controller.onPronunciationPlayed = { playedCandidate = $0 }
        let candidate = Candidate(
            id: "meeting",
            pinyin: "hui yi",
            sourceText: "会议",
            translation: "  meeting  ",
            targetLanguage: "en-GB"
        )

        XCTAssertTrue(controller.pronounce(candidate))
        XCTAssertEqual(provider.requests, [.init(text: "meeting", language: "en-GB")])
        XCTAssertEqual(playedCandidate?.id, candidate.id)
        XCTAssertEqual(controller.speakingCandidateID, candidate.id)
    }

    func testEmptyTranslationDoesNotSpeakOrEmitLearningEvent() {
        let provider = SpeechProviderSpy()
        let controller = PronunciationController(speechProvider: provider)
        var eventCount = 0
        controller.onPronunciationPlayed = { _ in eventCount += 1 }
        let candidate = Candidate(
            id: "empty",
            pinyin: "",
            sourceText: "",
            translation: " \n ",
            targetLanguage: "fr-FR"
        )

        XCTAssertFalse(controller.pronounce(candidate))
        XCTAssertTrue(provider.requests.isEmpty)
        XCTAssertEqual(eventCount, 0)
    }

    func testForwardsMultipleRequestsWithoutQueuingInController() {
        let provider = SpeechProviderSpy()
        let controller = PronunciationController(speechProvider: provider)

        controller.pronounce(Candidate(id: "one", pinyin: "", sourceText: "会议", translation: "meeting", targetLanguage: "en-US"))
        controller.pronounce(Candidate(id: "two", pinyin: "", sourceText: "会議", translation: "会議", targetLanguage: "ja-JP"))

        XCTAssertEqual(provider.requests, [
            .init(text: "meeting", language: "en-US"),
            .init(text: "会議", language: "ja-JP"),
        ])
    }

    func testLanguageResolverTriesSpecificLocaleThenBaseLanguage() {
        XCTAssertEqual(SpeechLanguageResolver.preferredLanguageCodes(for: "fr_CA"), ["fr-CA", "fr"])
        XCTAssertEqual(SpeechLanguageResolver.preferredLanguageCodes(for: "ja"), ["ja"])
        XCTAssertEqual(SpeechLanguageResolver.preferredLanguageCodes(for: "  "), [])
    }

    func testStopIsForwarded() {
        let provider = SpeechProviderSpy()
        let controller = PronunciationController(speechProvider: provider)

        controller.stop()

        XCTAssertEqual(provider.stopCount, 1)
    }

    func testPlaybackCompletionClearsSpeakingCandidate() {
        let provider = SpeechProviderSpy()
        let controller = PronunciationController(speechProvider: provider)
        var states: [String?] = []
        controller.onSpeakingCandidateChanged = { states.append($0) }
        let candidate = Candidate(id: "meeting", pinyin: "", sourceText: "会议", translation: "meeting")

        controller.pronounce(candidate)
        provider.finish()

        XCTAssertNil(controller.speakingCandidateID)
        XCTAssertEqual(states.count, 2)
        XCTAssertEqual(states[0], candidate.id)
        XCTAssertNil(states[1])
    }
}

@MainActor
private final class SpeechProviderSpy: SpeechProviding {
    struct Request: Equatable {
        let text: String
        let language: String?
    }

    var requests: [Request] = []
    var stopCount = 0
    var onSpeechFinished: (() -> Void)?

    @discardableResult
    func speak(_ text: String, language: String?) -> Bool {
        requests.append(.init(text: text, language: language))
        return true
    }

    func stop() {
        stopCount += 1
    }

    func finish() {
        onSpeechFinished?()
    }
}
