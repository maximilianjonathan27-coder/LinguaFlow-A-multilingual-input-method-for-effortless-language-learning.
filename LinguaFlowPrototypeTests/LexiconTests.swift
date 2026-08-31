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

        XCTAssertEqual(candidates.map(\.sourceText), ["会议", "回忆", "会意"])
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
}
