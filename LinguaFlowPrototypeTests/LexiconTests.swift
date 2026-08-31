import LinguaFlowCore
import XCTest

final class LexiconTests: XCTestCase {
    func testPinyinNormalizerSupportsSpacesCaseAndNewlines() {
        XCTAssertEqual(PinyinNormalizer.normalize("  Hui Yi\n"), "huiyi")
        XCTAssertEqual(PinyinNormalizer.normalize("SHEN qing"), "shenqing")
    }

    func testSQLiteLexiconReturnsTranslatedCandidates() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let databaseURL = repositoryRoot
            .appendingPathComponent("LinguaFlowInputMethod/Resources/linguaflow.sqlite")
        let lexicon = try SQLiteLexicon(databaseURL: databaseURL)

        let candidates = lexicon.candidates(for: "HUI YI", limit: 10)

        XCTAssertEqual(candidates.first?.sourceText, "会议")
        XCTAssertTrue(candidates.contains { $0.sourceText == "回忆" })
        XCTAssertTrue(candidates.contains { $0.sourceText == "会意" })
        XCTAssertEqual(candidates.first?.translation, "meeting")
        XCTAssertEqual(candidates.first?.targetLanguage, "en")
    }

    func testSelectionFrequencyCanPromoteARegularCandidate() {
        let candidates = CandidateCatalog.candidates(for: "huiyi")
        let ranked = CandidateRanker.rank(
            candidates,
            for: "huiyi",
            selectionCounts: ["huiyi.memory": 1]
        )

        XCTAssertEqual(ranked.first?.id, "huiyi.memory")
    }

    func testSQLiteLexiconSupportsCommonCharactersAndPrefixLookup() throws {
        let lexicon = try SQLiteLexicon(databaseURL: databaseURL)

        XCTAssertEqual(lexicon.candidates(for: "wo", limit: 5).first?.sourceText, "我")
        XCTAssertTrue(lexicon.prefixCandidates(for: "niha", limit: 10).contains {
            $0.sourceText == "你好"
        })
    }

    func testDecoderBuildsContinuousPinyinSentence() throws {
        let decoder = PinyinDecoder(lexicon: try SQLiteLexicon(databaseURL: databaseURL))
        let results = decoder.candidates(for: "woxiangqubeijing", limit: 20)

        XCTAssertTrue(results.contains { $0.sourceText == "我想去北京" })
    }

    @MainActor
    func testSelectionCountsPersistSeparately() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("selection.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let candidate = try XCTUnwrap(CandidateCatalog.primaryCandidate(for: "huiyi"))
        XCTAssertTrue(SelectionStore(fileURL: fileURL).increment(candidate))
        XCTAssertEqual(SelectionStore(fileURL: fileURL).counts[candidate.id], 1)
    }

    private var databaseURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("LinguaFlowInputMethod/Resources/linguaflow.sqlite")
    }
}
