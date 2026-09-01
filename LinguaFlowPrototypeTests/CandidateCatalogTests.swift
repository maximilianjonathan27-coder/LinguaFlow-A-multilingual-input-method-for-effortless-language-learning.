import LinguaFlowCore
import XCTest

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

    func testStableCandidateIdentifiersArePreserved() {
        XCTAssertEqual(CandidateCatalog.primaryCandidate(for: "huiyi")?.id, "huiyi.meeting")
        XCTAssertEqual(CandidateCatalog.primaryCandidate(for: "anpai")?.id, "anpai.arrange")
        XCTAssertEqual(CandidateCatalog.primaryCandidate(for: "yanqi")?.id, "yanqi.postpone")
        XCTAssertEqual(CandidateCatalog.primaryCandidate(for: "shenqing")?.id, "shenqing.apply")
        XCTAssertEqual(CandidateCatalog.primaryCandidate(for: "fangfa")?.id, "fangfa.method")
    }
}
