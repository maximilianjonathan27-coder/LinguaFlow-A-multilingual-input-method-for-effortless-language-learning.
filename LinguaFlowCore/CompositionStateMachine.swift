import Foundation

public struct CompositionStateMachine: Sendable {
    public enum CommitKey: Equatable, Sendable {
        case space
        case returnKey
    }

    public enum Action: Equatable, Sendable {
        case insertLetter(Character)
        case backspace
        case moveSelection(Int)
        case selectCandidate(Int)
        case commit(CommitKey)
        case punctuation(String)
        case cancel
        case deactivate
    }

    public enum Effect: Equatable, Sendable {
        case updateMarkedText(String)
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
    public private(set) var selectedIndex = 0

    public init() {}

    public var candidates: [Candidate] {
        CandidateCatalog.candidates(for: buffer)
    }

    public mutating func handle(_ action: Action) -> Transition {
        switch action {
        case let .insertLetter(character):
            guard character.isASCII, character.isLetter else {
                return Transition(effects: [.forwardEvent])
            }
            buffer.append(contentsOf: String(character).lowercased())
            selectedIndex = 0
            return compositionUpdate()

        case .backspace:
            guard !buffer.isEmpty else {
                return Transition(effects: [.forwardEvent])
            }
            buffer.removeLast()
            selectedIndex = 0
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

        case let .selectCandidate(index):
            let currentCandidates = candidates
            guard currentCandidates.indices.contains(index) else {
                return Transition(effects: [.forwardEvent])
            }
            return finish(candidate: currentCandidates[index])

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

        case .punctuation:
            if let candidate = candidates[safe: selectedIndex] {
                let transition = finish(candidate: candidate)
                return Transition(
                    effects: transition.effects + [.forwardEvent],
                    committedCandidate: candidate
                )
            }
            return finishRawTextAndForwardIfNeeded()

        case .cancel:
            reset()
            return Transition(effects: [.updateMarkedText(""), .hideCandidates])

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
        selectedIndex = 0
    }

    private func compositionUpdate() -> Transition {
        let currentCandidates = candidates
        var effects: [Effect] = [.updateMarkedText(buffer)]
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
