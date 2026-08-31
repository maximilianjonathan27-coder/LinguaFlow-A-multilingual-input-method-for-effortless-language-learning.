import XCTest
@testable import LinguaFlowPrototype

final class CandidateCatalogTests: XCTestCase {
    func testEverySupportedInputReturnsThreeCandidates() {
        for input in CandidateCatalog.supportedInputs {
            XCTAssertEqual(CandidateCatalog.candidates(for: input).count, 3, input)
        }
    }

    func testInputIsNormalized() {
        let candidates = CandidateCatalog.candidates(for: "  HUIYI\n")

        XCTAssertEqual(candidates.map(\.sourceText), ["会议", "回忆", "会意"])
    }

    func testUnknownAndEmptyInputReturnNoCandidates() {
        XCTAssertTrue(CandidateCatalog.candidates(for: "").isEmpty)
        XCTAssertTrue(CandidateCatalog.candidates(for: "   ").isEmpty)
        XCTAssertTrue(CandidateCatalog.candidates(for: "hello").isEmpty)
    }

    func testPrimaryCandidateMatchesReturnKeySelection() {
        XCTAssertEqual(
            CandidateCatalog.primaryCandidate(for: " HUIYI ")?.id,
            "huiyi.meeting"
        )
        XCTAssertEqual(
            CandidateCatalog.primaryCandidate(for: "anpai")?.sourceText,
            "安排"
        )
        XCTAssertNil(CandidateCatalog.primaryCandidate(for: "hello"))
    }
}
