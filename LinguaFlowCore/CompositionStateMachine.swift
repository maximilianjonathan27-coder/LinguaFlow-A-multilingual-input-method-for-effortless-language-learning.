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
    private let decoder: any CandidateDecoding
    public let direction: LanguageDirection
    private var selectionCounts: [String: Int]
    private let defersCandidateUpdates: Bool
    private var candidateSnapshot: [Candidate] = []

    public init(
        lexicon: any LexiconRepository = CandidateCatalog.repository,
        targetLanguage: String = "en",
        direction: LanguageDirection = .chineseToEnglish,
        selectionCounts: [String: Int] = [:],
        defersCandidateUpdates: Bool = false
    ) {
        decoder = PinyinDecoder(lexicon: lexicon, targetLanguage: targetLanguage)
        self.direction = direction
        self.selectionCounts = selectionCounts
        self.defersCandidateUpdates = defersCandidateUpdates
    }

    public init(
        decoder: any CandidateDecoding,
        direction: LanguageDirection = .chineseToEnglish,
        selectionCounts: [String: Int] = [:],
        defersCandidateUpdates: Bool = false
    ) {
        self.decoder = decoder
        self.direction = direction
        self.selectionCounts = selectionCounts
        self.defersCandidateUpdates = defersCandidateUpdates
    }

    public var allCandidates: [Candidate] {
        candidateSnapshot
    }

    public var displayedBuffer: String {
        direction == .englishToChinese
            ? buffer
            : PinyinNormalizer.formattedComposition(buffer)
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
        if direction == .chineseToEnglish, !candidateSnapshot.isEmpty {
            candidateSnapshot = CandidateRanker.rank(
                candidateSnapshot,
                for: buffer,
                selectionCounts: selectionCounts
            )
        }
    }

    /// Resolves a candidate snapshot without mutating composition state. The
    /// input method uses this from a background task so marked text can be
    /// displayed before SQLite/librime and translation metadata work finishes.
    public func resolvedCandidates(for input: String) -> [Candidate] {
        let decoded = decoder.candidates(for: input, limit: 50)
        guard direction == .chineseToEnglish else { return decoded }
        return CandidateRanker.rank(
            decoded,
            for: input,
            selectionCounts: selectionCounts
        )
    }

    /// Installs a background result only if it still belongs to the current
    /// composition. Stale results from earlier keystrokes are discarded.
    public mutating func acceptResolvedCandidates(
        _ resolved: [Candidate],
        for input: String
    ) -> Transition? {
        guard buffer == input else { return nil }
        candidateSnapshot = resolved
        pageIndex = min(pageIndex, max(0, pageCount - 1))
        selectedIndex = min(selectedIndex, max(0, candidates.count - 1))
        if candidates.isEmpty {
            return Transition(effects: [.hideCandidates])
        }
        return Transition(effects: [
            .updateCandidates(candidates, selectedIndex: selectedIndex),
        ])
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
            refreshCandidateSnapshot()
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
            refreshCandidateSnapshot()
            return compositionUpdate()

        case let .moveCursor(delta):
            guard !buffer.isEmpty else { return Transition(effects: [.forwardEvent]) }
            cursor = min(max(0, cursor + delta), buffer.count)
            return compositionUpdate()

        case let .moveSelection(delta):
            ensureCandidateSnapshot()
            let currentCandidates = candidates
            guard !currentCandidates.isEmpty else {
                return finishRawTextAndForwardIfNeeded()
            }
            let targetIndex = selectedIndex + delta
            if targetIndex >= currentCandidates.count, pageIndex + 1 < pageCount {
                pageIndex += 1
                selectedIndex = 0
            } else if targetIndex < 0, pageIndex > 0 {
                pageIndex -= 1
                selectedIndex = max(0, candidates.count - 1)
            } else if pageCount == 1 {
                selectedIndex = (targetIndex + currentCandidates.count) % currentCandidates.count
            } else {
                selectedIndex = min(max(0, targetIndex), currentCandidates.count - 1)
            }
            return Transition(effects: [
                .updateCandidates(candidates, selectedIndex: selectedIndex),
            ])

        case let .movePage(delta):
            ensureCandidateSnapshot()
            guard !allCandidates.isEmpty else { return Transition(effects: [.forwardEvent]) }
            pageIndex = (pageIndex + delta + pageCount) % pageCount
            selectedIndex = 0
            return Transition(effects: [
                .updateCandidates(candidates, selectedIndex: selectedIndex),
            ])

        case let .selectCandidate(index):
            ensureCandidateSnapshot()
            let currentCandidates = candidates
            guard currentCandidates.indices.contains(index) else {
                return Transition(effects: [.forwardEvent])
            }
            return finish(candidate: currentCandidates[index])

        case let .selectCandidateID(id):
            ensureCandidateSnapshot()
            guard let candidate = allCandidates.first(where: { $0.id == id }) else {
                return Transition(effects: [.forwardEvent])
            }
            return finish(candidate: candidate)

        case let .commit(key):
            guard !buffer.isEmpty else {
                return Transition(effects: [.forwardEvent])
            }

            if key == .returnKey {
                let rawLetters = PinyinNormalizer.normalize(buffer)
                reset()
                return Transition(effects: [.insertText(rawLetters), .hideCandidates])
            }

            ensureCandidateSnapshot()
            if let candidate = candidates[safe: selectedIndex] {
                return finish(candidate: candidate)
            }

            let rawText = buffer
            reset()
            switch key {
            case .space:
                return Transition(effects: [.insertText(rawText + " "), .hideCandidates])
            case .returnKey:
                return Transition(effects: [.insertText(PinyinNormalizer.normalize(rawText)), .hideCandidates])
            }

        case let .punctuation(punctuation):
            ensureCandidateSnapshot()
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
        candidateSnapshot = []
    }

    private func compositionUpdate() -> Transition {
        let currentCandidates = candidates
        let display = direction == .englishToChinese
            ? (text: buffer, cursor: cursor)
            : PinyinNormalizer.compositionDisplay(buffer, rawCursor: cursor)
        var effects: [Effect] = [.updateMarkedText(display.text, cursor: display.cursor)]
        if currentCandidates.isEmpty {
            if !defersCandidateUpdates || buffer.isEmpty {
                effects.append(.hideCandidates)
            }
        } else {
            effects.append(.updateCandidates(currentCandidates, selectedIndex: selectedIndex))
        }
        return Transition(effects: effects)
    }

    private mutating func finish(candidate: Candidate) -> Transition {
        if direction == .chineseToEnglish, consumePartialCandidateIfPossible(candidate) {
            let update = compositionUpdate()
            return Transition(
                effects: [.insertText(candidate.commitText)] + update.effects,
                committedCandidate: candidate
            )
        }
        reset()
        return Transition(
            effects: [.insertText(candidate.commitText), .hideCandidates],
            committedCandidate: candidate
        )
    }

    private mutating func consumePartialCandidateIfPossible(_ candidate: Candidate) -> Bool {
        let typedComponents = PinyinNormalizer.segments(for: buffer)
        let candidateSyllables = candidate.pinyin.lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0 == "'" })
            .map(String.init)
        guard !candidateSyllables.isEmpty,
              candidateSyllables.count < typedComponents.count,
              Self.matchesPrefix(candidateSyllables, of: typedComponents)
        else { return false }

        let lettersToConsume = typedComponents
            .prefix(candidateSyllables.count)
            .reduce(0) { $0 + $1.count }
        let rawCharacters = Array(buffer)
        var rawOffset = 0
        var consumedLetters = 0
        while rawOffset < rawCharacters.count, consumedLetters < lettersToConsume {
            if rawCharacters[rawOffset].isLetter { consumedLetters += 1 }
            rawOffset += 1
        }
        while rawOffset < rawCharacters.count, rawCharacters[rawOffset] == "'" {
            rawOffset += 1
        }

        buffer = String(rawCharacters.dropFirst(rawOffset))
        cursor = buffer.count
        selectedIndex = 0
        pageIndex = 0
        refreshCandidateSnapshot()
        return !buffer.isEmpty
    }

    private mutating func refreshCandidateSnapshot() {
        candidateSnapshot = []
        guard !defersCandidateUpdates, !buffer.isEmpty else { return }
        candidateSnapshot = resolvedCandidates(for: buffer)
    }

    private mutating func ensureCandidateSnapshot() {
        guard candidateSnapshot.isEmpty, !buffer.isEmpty else { return }
        candidateSnapshot = resolvedCandidates(for: buffer)
    }

    private static func matchesPrefix(_ candidate: [String], of typed: [String]) -> Bool {
        let initials: Set<String> = [
            "b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h",
            "j", "q", "x", "zh", "ch", "sh", "r", "z", "c", "s", "y", "w",
        ]
        return zip(typed.prefix(candidate.count), candidate).allSatisfy { part, syllable in
            initials.contains(part) ? syllable.hasPrefix(part) : syllable == part
        }
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
