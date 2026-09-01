import Foundation

public struct CompositionStateMachine: Sendable {
    public enum CommitKey: Equatable, Sendable {
        case space
        case returnKey
    }

    public enum Action: Equatable, Sendable {
        case insertLetter(Character)
        case backspace
        case moveCursor(Int)
        case moveSelection(Int)
        case movePage(Int)
        case selectCandidate(Int)
        case selectCandidateID(String)
        case commit(CommitKey)
        case punctuation(String)
        case cancel
        case deactivate
    }

    public enum Effect: Equatable, Sendable {
        case updateMarkedText(String, cursor: Int)
        case updateCandidates([Candidate], selectedIndex: Int)
        case hideCandidates
        case insertText(String)
        case forwardEvent
    }

    public struct Transition: Equatable, Sendable {
        public let effects: [Effect]
        public let committedCandidate: Candidate?

        public var forwardsOriginalEvent: Bool {
            effects.contains(.forwardEvent)
        }

        public init(effects: [Effect], committedCandidate: Candidate? = nil) {
            self.effects = effects
            self.committedCandidate = committedCandidate
        }
    }

    public private(set) var buffer = ""
    public private(set) var cursor = 0
    public private(set) var selectedIndex = 0
    public private(set) var pageIndex = 0
    public let pageSize = 5
    private let decoder: PinyinDecoder
    private var selectionCounts: [String: Int]

    public init(
        lexicon: any LexiconRepository = CandidateCatalog.repository,
        examples: (any ExampleRepository)? = nil,
        targetLanguage: String = "en",
        selectionCounts: [String: Int] = [:]
    ) {
        decoder = PinyinDecoder(lexicon: lexicon, examples: examples, targetLanguage: targetLanguage)
        self.selectionCounts = selectionCounts
    }

    public var allCandidates: [Candidate] {
        CandidateRanker.rank(
            decoder.candidates(for: buffer, limit: 50),
            for: buffer,
            selectionCounts: selectionCounts
        )
    }

    public var candidates: [Candidate] {
        let start = pageIndex * pageSize
        guard start < allCandidates.count else { return [] }
        return Array(allCandidates.dropFirst(start).prefix(pageSize))
    }

    public var pageCount: Int {
        max(1, Int(ceil(Double(allCandidates.count) / Double(pageSize))))
    }

    public mutating func updateSelectionCounts(_ counts: [String: Int]) {
        selectionCounts = counts
    }

    public mutating func handle(_ action: Action) -> Transition {
        switch action {
        case let .insertLetter(character):
            guard character.isASCII, character.isLetter || character == "'" else {
                return Transition(effects: [.forwardEvent])
            }
            let insertionIndex = buffer.index(buffer.startIndex, offsetBy: cursor)
            buffer.insert(contentsOf: String(character).lowercased(), at: insertionIndex)
            cursor += 1
            selectedIndex = 0
            pageIndex = 0
            return compositionUpdate()

        case .backspace:
            guard !buffer.isEmpty else {
                return Transition(effects: [.forwardEvent])
            }
            guard cursor > 0 else { return Transition(effects: [.forwardEvent]) }
            let removalIndex = buffer.index(buffer.startIndex, offsetBy: cursor - 1)
            buffer.remove(at: removalIndex)
            cursor -= 1
            selectedIndex = 0
            pageIndex = 0
            return compositionUpdate()

        case let .moveCursor(delta):
            guard !buffer.isEmpty else { return Transition(effects: [.forwardEvent]) }
            cursor = min(max(0, cursor + delta), buffer.count)
            return compositionUpdate()

        case let .moveSelection(delta):
            let currentCandidates = candidates
            guard !currentCandidates.isEmpty else {
                return finishRawTextAndForwardIfNeeded()
            }
            selectedIndex = (selectedIndex + delta + currentCandidates.count) % currentCandidates.count
            return Transition(effects: [
                .updateCandidates(currentCandidates, selectedIndex: selectedIndex),
            ])

        case let .movePage(delta):
            guard !allCandidates.isEmpty else { return Transition(effects: [.forwardEvent]) }
            pageIndex = (pageIndex + delta + pageCount) % pageCount
            selectedIndex = 0
            return Transition(effects: [
                .updateCandidates(candidates, selectedIndex: selectedIndex),
            ])

        case let .selectCandidate(index):
            let currentCandidates = candidates
            guard currentCandidates.indices.contains(index) else {
                return Transition(effects: [.forwardEvent])
            }
            return finish(candidate: currentCandidates[index])

        case let .selectCandidateID(id):
            guard let candidate = allCandidates.first(where: { $0.id == id }) else {
                return Transition(effects: [.forwardEvent])
            }
            return finish(candidate: candidate)

        case let .commit(key):
            if let candidate = candidates[safe: selectedIndex] {
                return finish(candidate: candidate)
            }
            guard !buffer.isEmpty else {
                return Transition(effects: [.forwardEvent])
            }

            let rawText = buffer
            reset()
            switch key {
            case .space:
                return Transition(effects: [.insertText(rawText + " "), .hideCandidates])
            case .returnKey:
                return Transition(effects: [.insertText(rawText), .hideCandidates, .forwardEvent])
            }

        case let .punctuation(punctuation):
            if let candidate = candidates[safe: selectedIndex] {
                let transition = finish(candidate: candidate)
                return Transition(
                    effects: transition.effects + [.insertText(punctuation)],
                    committedCandidate: candidate
                )
            }
            guard !buffer.isEmpty else {
                return Transition(effects: [.insertText(punctuation)])
            }
            let rawText = buffer
            reset()
            return Transition(effects: [.insertText(rawText + punctuation), .hideCandidates])

        case .cancel:
            reset()
            return Transition(effects: [.updateMarkedText("", cursor: 0), .hideCandidates])

        case .deactivate:
            guard !buffer.isEmpty else {
                return Transition(effects: [.hideCandidates])
            }
            let rawText = buffer
            reset()
            return Transition(effects: [.insertText(rawText), .hideCandidates])
        }
    }

    public mutating func reset() {
        buffer = ""
        cursor = 0
        selectedIndex = 0
        pageIndex = 0
    }

    private func compositionUpdate() -> Transition {
        let currentCandidates = candidates
        var effects: [Effect] = [.updateMarkedText(buffer, cursor: cursor)]
        if currentCandidates.isEmpty {
            effects.append(.hideCandidates)
        } else {
            effects.append(.updateCandidates(currentCandidates, selectedIndex: selectedIndex))
        }
        return Transition(effects: effects)
    }

    private mutating func finish(candidate: Candidate) -> Transition {
        reset()
        return Transition(
            effects: [.insertText(candidate.sourceText), .hideCandidates],
            committedCandidate: candidate
        )
    }

    private mutating func finishRawTextAndForwardIfNeeded() -> Transition {
        guard !buffer.isEmpty else {
            return Transition(effects: [.forwardEvent])
        }
        let rawText = buffer
        reset()
        return Transition(effects: [.insertText(rawText), .hideCandidates, .forwardEvent])
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
