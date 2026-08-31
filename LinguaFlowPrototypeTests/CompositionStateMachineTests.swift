import LinguaFlowCore
import XCTest

final class CompositionStateMachineTests: XCTestCase {
    func testTypingSupportedPinyinShowsThreeCandidates() {
        var machine = CompositionStateMachine()
        var transition = CompositionStateMachine.Transition(effects: [])

        for character in "huiyi" {
            transition = machine.handle(.insertLetter(character))
        }

        XCTAssertEqual(machine.buffer, "huiyi")
        XCTAssertTrue(transition.effects.contains(.updateMarkedText("huiyi", cursor: 5)))
        XCTAssertTrue(transition.effects.contains { effect in
            if case let .updateCandidates(candidates, selectedIndex) = effect {
                return candidates.count == 3 && selectedIndex == 0
            }
            return false
        })
    }

    func testArrowKeysWrapCandidateSelection() {
        var machine = makeMachine(with: "huiyi")

        _ = machine.handle(.moveSelection(-1))
        XCTAssertEqual(machine.selectedIndex, 2)

        _ = machine.handle(.moveSelection(1))
        XCTAssertEqual(machine.selectedIndex, 0)
    }

    func testReturnCommitsSelectedCandidate() throws {
        var machine = makeMachine(with: "huiyi")
        _ = machine.handle(.moveSelection(1))

        let transition = machine.handle(.commit(.returnKey))

        XCTAssertEqual(transition.committedCandidate?.sourceText, "回忆")
        XCTAssertEqual(transition.effects, [.insertText("回忆"), .hideCandidates])
        XCTAssertFalse(transition.forwardsOriginalEvent)
        XCTAssertTrue(machine.buffer.isEmpty)
    }

    func testNumberSelectsExactCandidate() {
        var machine = makeMachine(with: "anpai")
        let transition = machine.handle(.selectCandidate(2))

        XCTAssertEqual(transition.committedCandidate?.sourceText, "安排时间")
        XCTAssertEqual(transition.effects, [.insertText("安排时间"), .hideCandidates])
    }

    func testUnknownInputSpaceOutputsRawTextAndSpace() {
        var machine = makeMachine(with: "hello")
        let transition = machine.handle(.commit(.space))

        XCTAssertEqual(transition.effects, [.insertText("hello "), .hideCandidates])
        XCTAssertNil(transition.committedCandidate)
        XCTAssertFalse(transition.forwardsOriginalEvent)
    }

    func testUnknownInputReturnOutputsRawTextAndForwardsNewline() {
        var machine = makeMachine(with: "hello")
        let transition = machine.handle(.commit(.returnKey))

        XCTAssertEqual(
            transition.effects,
            [.insertText("hello"), .hideCandidates, .forwardEvent]
        )
        XCTAssertTrue(transition.forwardsOriginalEvent)
    }

    func testPunctuationCommitsCandidateThenForwardsPunctuation() {
        var machine = makeMachine(with: "yanqi")
        let transition = machine.handle(.punctuation("。"))

        XCTAssertEqual(transition.committedCandidate?.sourceText, "延期")
        XCTAssertEqual(
            transition.effects,
            [.insertText("延期"), .hideCandidates, .insertText("。")]
        )
    }

    func testBackspaceAndEscapeUpdateComposition() {
        var machine = makeMachine(with: "hui")
        let backspace = machine.handle(.backspace)
        XCTAssertEqual(machine.buffer, "hu")
        XCTAssertTrue(backspace.effects.contains(.updateMarkedText("hu", cursor: 2)))

        let cancel = machine.handle(.cancel)
        XCTAssertEqual(cancel.effects, [.updateMarkedText("", cursor: 0), .hideCandidates])
        XCTAssertTrue(machine.buffer.isEmpty)
    }

    func testCursorCanEditInsideComposition() {
        var machine = makeMachine(with: "nihao")
        _ = machine.handle(.moveCursor(-2))
        _ = machine.handle(.insertLetter("m"))

        XCTAssertEqual(machine.buffer, "nihmao")
        XCTAssertEqual(machine.cursor, 4)
    }

    func testDeactivateCommitsRawCompositionWithoutExposure() {
        var machine = makeMachine(with: "hui")
        let transition = machine.handle(.deactivate)

        XCTAssertEqual(transition.effects, [.insertText("hui"), .hideCandidates])
        XCTAssertNil(transition.committedCandidate)
    }

    private func makeMachine(with text: String) -> CompositionStateMachine {
        var machine = CompositionStateMachine()
        for character in text {
            _ = machine.handle(.insertLetter(character))
        }
        return machine
    }
}
