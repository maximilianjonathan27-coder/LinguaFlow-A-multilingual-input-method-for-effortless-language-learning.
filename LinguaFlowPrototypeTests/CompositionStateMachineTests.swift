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
        XCTAssertTrue(transition.effects.contains(.updateMarkedText("hui yi", cursor: 6)))
        XCTAssertTrue(transition.effects.contains { effect in
            if case let .updateCandidates(candidates, selectedIndex) = effect {
                return candidates.count == 3 && selectedIndex == 0
            }
            return false
        })
    }

    func testDeferredCandidateUpdatesReturnMarkedTextBeforeInstallingCandidates() {
        let candidates = [
            Candidate(
                id: "ni",
                pinyin: "ni",
                sourceText: "你",
                translation: "you",
                frequency: 100
            ),
        ]
        var machine = CompositionStateMachine(
            lexicon: InMemoryLexicon(candidates: candidates),
            defersCandidateUpdates: true
        )

        let transition = machine.handle(.insertLetter("n"))

        XCTAssertEqual(transition.effects, [.updateMarkedText("n", cursor: 1)])
        XCTAssertTrue(machine.allCandidates.isEmpty)

        let stale = machine.resolvedCandidates(for: "n")
        _ = machine.handle(.insertLetter("i"))
        XCTAssertNil(machine.acceptResolvedCandidates(stale, for: "n"))

        let current = machine.resolvedCandidates(for: "ni")
        let update = machine.acceptResolvedCandidates(current, for: "ni")
        XCTAssertEqual(machine.allCandidates.first?.sourceText, "你")
        XCTAssertTrue(update?.effects.contains { effect in
            if case .updateCandidates = effect { return true }
            return false
        } == true)
    }

    func testArrowKeysWrapCandidateSelection() {
        var machine = makeMachine(with: "huiyi")

        _ = machine.handle(.moveSelection(-1))
        XCTAssertEqual(machine.selectedIndex, 2)

        _ = machine.handle(.moveSelection(1))
        XCTAssertEqual(machine.selectedIndex, 0)
    }

    func testDownArrowMovesToNextCompactCandidatePage() {
        let candidates = (1...7).map { index in
            Candidate(
                id: "page.\(index)",
                pinyin: "shi",
                sourceText: "候选\(index)",
                translation: "candidate \(index)",
                frequency: 100 - index
            )
        }
        var machine = CompositionStateMachine(lexicon: InMemoryLexicon(candidates: candidates))
        for character in "shi" { _ = machine.handle(.insertLetter(character)) }

        for _ in 0..<4 { _ = machine.handle(.moveSelection(1)) }
        XCTAssertEqual(machine.pageIndex, 0)
        XCTAssertEqual(machine.selectedIndex, 4)

        let transition = machine.handle(.moveSelection(1))
        XCTAssertEqual(machine.pageIndex, 1)
        XCTAssertEqual(machine.selectedIndex, 0)
        XCTAssertTrue(transition.effects.contains { effect in
            guard case let .updateCandidates(candidates, selectedIndex) = effect else {
                return false
            }
            return candidates.count == 2 && selectedIndex == 0
        })
    }

    func testSpaceCommitsSelectedCandidate() throws {
        var machine = makeMachine(with: "huiyi")
        _ = machine.handle(.moveSelection(1))

        let transition = machine.handle(.commit(.space))

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

    func testExpandedPanelCanSelectCandidateByStableID() {
        var machine = makeMachine(with: "anpai")
        let transition = machine.handle(.selectCandidateID("anpai.time"))

        XCTAssertEqual(transition.committedCandidate?.sourceText, "安排时间")
        XCTAssertEqual(transition.effects, [.insertText("安排时间"), .hideCandidates])
    }

    func testUnknownInputSpaceOutputsRawTextAndSpace() {
        var machine = makeMachine(with: "zzzz")
        let transition = machine.handle(.commit(.space))

        XCTAssertEqual(transition.effects, [.insertText("zzzz "), .hideCandidates])
        XCTAssertNil(transition.committedCandidate)
        XCTAssertFalse(transition.forwardsOriginalEvent)
    }

    func testUnknownInputReturnOutputsRawTextWithoutNewline() {
        var machine = makeMachine(with: "hello")
        let transition = machine.handle(.commit(.returnKey))

        XCTAssertEqual(transition.effects, [.insertText("hello"), .hideCandidates])
        XCTAssertFalse(transition.forwardsOriginalEvent)
    }

    func testReturnCommitsRawLettersInsteadOfSelectedChineseCandidate() {
        var machine = makeMachine(with: "huiyi")

        let transition = machine.handle(.commit(.returnKey))

        XCTAssertEqual(transition.effects, [.insertText("huiyi"), .hideCandidates])
        XCTAssertNil(transition.committedCandidate)
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

    func testDisplayedCompositionUsesPinyinSyllableSpacing() {
        var machine = makeMachine(with: "nihao")
        XCTAssertEqual(machine.displayedBuffer, "ni hao")

        let transition = machine.handle(.moveCursor(-2))
        XCTAssertTrue(transition.effects.contains(.updateMarkedText("ni hao", cursor: 4)))
        XCTAssertEqual(machine.cursor, 3)
    }

    func testDisplayedCompositionSeparatesConsecutiveInitials() {
        let machine = makeMachine(with: "hhhh")
        XCTAssertEqual(machine.displayedBuffer, "h h h h")
    }

    func testDeactivateCommitsRawCompositionWithoutExposure() {
        var machine = makeMachine(with: "hui")
        let transition = machine.handle(.deactivate)

        XCTAssertEqual(transition.effects, [.insertText("hui"), .hideCandidates])
        XCTAssertNil(transition.committedCandidate)
    }

    func testSelectingShortPrefixKeepsUnconsumedInitials() {
        let lexicon = InMemoryLexicon(candidates: [
            Candidate(id: "full", pinyin: "ni ke yi", sourceText: "你可以", translation: "you can", frequency: 100),
            Candidate(id: "two", pinyin: "ni kan", sourceText: "你看", translation: "look", frequency: 90),
            Candidate(id: "one", pinyin: "ni", sourceText: "你", translation: "you", frequency: 80),
            Candidate(id: "remaining", pinyin: "yi", sourceText: "一", translation: "one", frequency: 70),
        ])
        var machine = CompositionStateMachine(lexicon: lexicon)
        for character in "nky" { _ = machine.handle(.insertLetter(character)) }

        let transition = machine.handle(.selectCandidateID("two"))

        XCTAssertEqual(machine.buffer, "y")
        XCTAssertEqual(transition.committedCandidate?.sourceText, "你看")
        XCTAssertTrue(transition.effects.contains(.insertText("你看")))
        XCTAssertTrue(transition.effects.contains(.updateMarkedText("y", cursor: 1)))
    }

    private func makeMachine(with text: String) -> CompositionStateMachine {
        var machine = CompositionStateMachine()
        for character in text {
            _ = machine.handle(.insertLetter(character))
        }
        return machine
    }
}
