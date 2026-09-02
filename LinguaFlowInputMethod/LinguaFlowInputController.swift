import AppKit
import InputMethodKit
import LinguaFlowCore
import OSLog

@objc(LinguaFlowInputController)
@MainActor
final class LinguaFlowInputController: IMKInputController {
    private static let logger = Logger(
        subsystem: "com.tianxq.inputmethod.LinguaFlow",
        category: "InputController"
    )
    private var stateMachine: CompositionStateMachine
    private let lexicon: SQLiteLexicon?
    private var usesRime: Bool
    private lazy var selectionStore = SelectionStore()
    private var pendingCandidateTask: Task<Void, Never>?
    private var pendingTranslationTask: Task<Void, Never>?
    private lazy var sentenceTranslator = LocalSentenceTranslator()
    private var lastCaretRectangle = NSRect.zero
    private var compositionAnchor: NSRect?
    private lazy var candidatePanel: CandidatePanelController = {
        let controller = CandidatePanelController()
        controller.onSelect = { [weak self] candidateID in
            self?.selectCandidate(id: candidateID)
        }
        return controller
    }()

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        let loadedLexicon = Bundle.main.url(forResource: "linguaflow", withExtension: "sqlite")
            .flatMap { try? SQLiteLexicon(databaseURL: $0) }
        lexicon = loadedLexicon
        if let loadedLexicon {
            let configuration = Self.makeStateMachine(
                lexicon: loadedLexicon,
                direction: LanguageDirectionStore.shared.current()
            )
            stateMachine = configuration.stateMachine
            usesRime = configuration.usesRime
        } else {
            stateMachine = CompositionStateMachine()
            usesRime = false
        }
        super.init(server: server, delegate: delegate, client: inputClient)
        Self.logger.notice("Input controller initialized; librime=\(self.usesRime)")
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        Self.logger.debug("Recognized events requested")
        return Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        Self.logger.debug("Received event keyCode=\(event?.keyCode ?? 0)")
        guard
            let event,
            event.type == .keyDown,
            let inputClient = sender as? (any IMKTextInput)
        else {
            return false
        }

        let shortcutModifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard shortcutModifiers.isEmpty else { return false }
        let keyText = event.charactersIgnoringModifiers ?? ""
        if stateMachine.buffer.isEmpty,
           event.modifierFlags.contains(.capsLock) || event.modifierFlags.contains(.shift),
           keyText.count == 1,
           keyText.first?.isLetter == true {
            return false
        }

        if event.keyCode == 124,
           !stateMachine.buffer.isEmpty,
           stateMachine.cursor == stateMachine.buffer.count,
           !stateMachine.allCandidates.isEmpty,
           !candidatePanel.isExpanded {
            candidatePanel.setExpanded(true)
            return true
        }

        if keyText == "=", !stateMachine.buffer.isEmpty, !stateMachine.allCandidates.isEmpty {
            if candidatePanel.isExpanded {
                candidatePanel.moveExpandedRow(1)
            } else {
                candidatePanel.setExpanded(true)
            }
            return true
        }

        if keyText == "-", candidatePanel.isExpanded {
            candidatePanel.moveExpandedRow(-1)
            return true
        }

        if candidatePanel.isExpanded {
            if event.keyCode == 123 {
                candidatePanel.moveExpandedColumn(-1)
                return true
            }
            if event.keyCode == 124 {
                candidatePanel.moveExpandedColumn(1)
                return true
            }
            if event.keyCode == 125 {
                candidatePanel.moveExpandedRow(1)
                return true
            }
            if event.keyCode == 126 {
                candidatePanel.moveExpandedRow(-1)
                return true
            }
            if (event.keyCode == 36 || event.keyCode == 49),
               let candidateID = candidatePanel.highlightedCandidateID {
                selectCandidate(id: candidateID)
                return true
            }
            if let number = Int(keyText), (1...3).contains(number),
               let candidateID = candidatePanel.candidateID(inColumn: number - 1) {
                selectCandidate(id: candidateID)
                return true
            }
        }

        guard let action = action(for: event) else {
            if stateMachine.buffer.isEmpty { return false }
            return apply(stateMachine.handle(.punctuation(event.characters ?? "")), to: inputClient)
        }

        return apply(stateMachine.handle(action), to: inputClient)
    }

    override func inputText(
        _ string: String!,
        key keyCode: Int,
        modifiers flags: Int,
        client sender: Any!
    ) -> Bool {
        Self.logger.debug("Received unpacked text event keyCode=\(keyCode)")
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: string ?? "",
            charactersIgnoringModifiers: string ?? "",
            isARepeat: false,
            keyCode: UInt16(clamping: keyCode)
        ) else { return false }
        return handle(event, client: sender)
    }

    override func inputText(_ string: String!, client sender: Any!) -> Bool {
        Self.logger.debug("Received keybinding text")
        guard let string,
              let inputClient = sender as? (any IMKTextInput),
              !string.isEmpty
        else { return false }

        var handled = false
        for character in string {
            if character.isASCII, character.isLetter
                || character == "'" && !stateMachine.buffer.isEmpty {
                handled = apply(stateMachine.handle(.insertLetter(character)), to: inputClient)
            } else if stateMachine.direction == .chineseToEnglish,
                      let punctuation = PinyinNormalizer.chinesePunctuation(for: String(character)) {
                handled = apply(stateMachine.handle(.punctuation(punctuation)), to: inputClient)
            } else {
                return false
            }
        }
        return handled
    }

    override func composedString(_ sender: Any!) -> Any! {
        stateMachine.displayedBuffer
    }

    override func commitComposition(_ sender: Any!) {
        guard let inputClient = sender as? (any IMKTextInput) else {
            stateMachine.reset()
            compositionAnchor = nil
            candidatePanel.hide()
            return
        }
        _ = apply(stateMachine.handle(.deactivate), to: inputClient)
    }

    override func activateServer(_ sender: Any!) {
        selectionStore.refresh()
        refreshDirectionIfNeeded()
        stateMachine.updateSelectionCounts(selectionStore.counts)
        super.activateServer(sender)
    }

    override func deactivateServer(_ sender: Any!) {
        if let inputClient = sender as? (any IMKTextInput) {
            _ = apply(stateMachine.handle(.deactivate), to: inputClient)
        } else {
            stateMachine.reset()
            compositionAnchor = nil
            candidatePanel.hide()
        }
        super.deactivateServer(sender)
    }

    override func hidePalettes() {
        candidatePanel.hide()
        super.hidePalettes()
    }

    override func inputControllerWillClose() {
        candidatePanel.hide()
        candidatePanel.stopPronunciation()
        super.inputControllerWillClose()
    }

    private func action(for event: NSEvent) -> CompositionStateMachine.Action? {
        switch event.keyCode {
        case 36, 76:
            return .commit(.returnKey)
        case 49:
            return .commit(.space)
        case 51:
            return .backspace
        case 53:
            return .cancel
        case 123:
            return .moveCursor(-1)
        case 124:
            return .moveCursor(1)
        case 125:
            return .moveSelection(1)
        case 126:
            return .moveSelection(-1)
        case 116:
            return .movePage(-1)
        case 121:
            return .movePage(1)
        default:
            break
        }

        let unmodifiedText = event.charactersIgnoringModifiers ?? ""
        let producedText = event.characters ?? unmodifiedText
        if let number = Int(unmodifiedText),
           (1...5).contains(number),
           !stateMachine.candidates.isEmpty {
            return .selectCandidate(number - 1)
        }

        if unmodifiedText.count == 1,
           let character = unmodifiedText.first,
           character.isASCII,
           character.isLetter {
            return .insertLetter(character)
        }
        if producedText == "'", !stateMachine.buffer.isEmpty {
            if let character = producedText.first {
                return .insertLetter(character)
            }
        }

        if stateMachine.direction == .chineseToEnglish,
           let punctuation = PinyinNormalizer.chinesePunctuation(for: producedText) {
            return .punctuation(punctuation)
        }

        return nil
    }

    private func apply(
        _ transition: CompositionStateMachine.Transition,
        to inputClient: any IMKTextInput
    ) -> Bool {
        let updatesMarkedText = transition.effects.contains { effect in
            if case .updateMarkedText = effect { return true }
            return false
        }
        if updatesMarkedText, !stateMachine.buffer.isEmpty, compositionAnchor == nil {
            // Capture the insertion point before the first marked character is
            // written. Every candidate refresh in this composition reuses it,
            // so the panel does not chase the advancing marked-text cursor.
            compositionAnchor = caretRectangle(for: inputClient, compositionIndex: 0)
        }

        for effect in transition.effects {
            switch effect {
            case let .updateMarkedText(text, cursor):
                inputClient.setMarkedText(
                    text,
                    selectionRange: NSRange(location: cursor, length: 0),
                    replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
                )

            case let .updateCandidates(candidates, selectedIndex):
                candidatePanel.show(
                    compactCandidates: candidates,
                    expandedCandidates: stateMachine.allCandidates,
                    selectedCandidateID: candidates[safe: selectedIndex]?.id,
                    query: stateMachine.displayedBuffer,
                    counts: selectionStore.counts,
                    anchor: compositionAnchor ?? caretRectangle(for: inputClient)
                )
                scheduleSentenceTranslation(for: stateMachine.allCandidates)

            case .hideCandidates:
                pendingCandidateTask?.cancel()
                pendingCandidateTask = nil
                cancelSentenceTranslation()
                candidatePanel.hide()
                if stateMachine.buffer.isEmpty {
                    compositionAnchor = nil
                }

            case let .insertText(text):
                inputClient.insertText(
                    text,
                    replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
                )

            case .forwardEvent:
                break
            }
        }

        if let committedCandidate = transition.committedCandidate {
            _ = selectionStore.increment(committedCandidate)
            stateMachine.updateSelectionCounts(selectionStore.counts)
        }

        let alreadyHasCandidates = transition.effects.contains { effect in
            if case .updateCandidates = effect { return true }
            return false
        }
        if updatesMarkedText, !alreadyHasCandidates, !stateMachine.buffer.isEmpty {
            scheduleCandidateResolution()
        }

        return !transition.forwardsOriginalEvent
    }

    private func scheduleCandidateResolution() {
        pendingCandidateTask?.cancel()
        let query = stateMachine.buffer
        let snapshot = stateMachine
        pendingCandidateTask = Task { @MainActor [weak self] in
            // Coalesce very fast typing bursts before starting synchronous
            // librime/SQLite work on a background executor.
            try? await Task.sleep(nanoseconds: 10_000_000)
            guard !Task.isCancelled else { return }
            let resolved = await Task.detached(priority: .userInitiated) {
                snapshot.resolvedCandidates(for: query)
            }.value
            guard !Task.isCancelled,
                  let self,
                  let transition = self.stateMachine.acceptResolvedCandidates(
                      resolved,
                      for: query
                  ),
                  let inputClient = self.client()
            else { return }
            _ = self.apply(transition, to: inputClient)
        }
    }

    private func scheduleSentenceTranslation(for candidates: [Candidate]) {
        pendingTranslationTask?.cancel()
        guard stateMachine.direction == .chineseToEnglish else {
            pendingTranslationTask = nil
            return
        }
        let query = stateMachine.displayedBuffer
        let requests = sentenceTranslator.requests(from: candidates)
        guard !requests.isEmpty else {
            pendingTranslationTask = nil
            return
        }

        let cached = sentenceTranslator.cachedResults(for: requests)
        candidatePanel.updateTranslations(cached, forQuery: query)

        pendingTranslationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let results = await self.sentenceTranslator.translate(requests)
            guard !Task.isCancelled, self.stateMachine.displayedBuffer == query else { return }
            self.candidatePanel.updateTranslations(results, forQuery: query)
        }
    }

    private func cancelSentenceTranslation() {
        pendingTranslationTask?.cancel()
        pendingTranslationTask = nil
    }

    private func caretRectangle(
        for inputClient: any IMKTextInput,
        compositionIndex: Int? = nil
    ) -> NSRect {
        // IMK expects an index relative to the active marked-text session here,
        // not the document-relative selectedRange. Passing selectedRange.location
        // makes many web editors return an empty rectangle.
        let displayCursor = compositionIndex ?? (stateMachine.direction == .englishToChinese
            ? stateMachine.cursor
            : PinyinNormalizer.compositionDisplay(
                stateMachine.buffer,
                rawCursor: stateMachine.cursor
            ).cursor)
        var indexes = [displayCursor]
        if displayCursor > 0 { indexes.append(displayCursor - 1) }
        indexes.append(0)

        for index in indexes {
            var lineRectangle = NSRect.zero
            _ = inputClient.attributes(
                forCharacterIndex: index,
                lineHeightRectangle: &lineRectangle
            )
            if Self.isUsableCaretRectangle(lineRectangle) {
                lastCaretRectangle = lineRectangle
                return lineRectangle
            }
        }

        // Some clients expose NSTextInputClient geometry in addition to IMKTextInput.
        if let textClient = inputClient as? any NSTextInputClient {
            let selectedRange = inputClient.selectedRange()
            let range = selectedRange.location == NSNotFound
                ? NSRange(location: 0, length: 0)
                : NSRange(location: selectedRange.location, length: 0)
            var actualRange = NSRange(location: NSNotFound, length: 0)
            let rectangle = textClient.firstRect(
                forCharacterRange: range,
                actualRange: &actualRange
            )
            if Self.isUsableCaretRectangle(rectangle) {
                lastCaretRectangle = rectangle
                return rectangle
            }
        }

        // Never position from the mouse. Keeping the most recent text anchor is
        // less surprising for clients that temporarily fail to return geometry.
        if Self.isUsableCaretRectangle(lastCaretRectangle) {
            return lastCaretRectangle
        }
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        return NSRect(x: screenFrame.midX, y: screenFrame.midY, width: 1, height: 20)
    }

    private static func isUsableCaretRectangle(_ rectangle: NSRect) -> Bool {
        !rectangle.isEmpty
            && rectangle.origin.x.isFinite
            && rectangle.origin.y.isFinite
            && rectangle.width.isFinite
            && rectangle.height.isFinite
    }

    private func selectCandidate(id: String) {
        guard let inputClient = client() else { return }
        _ = apply(stateMachine.handle(.selectCandidateID(id)), to: inputClient)
    }

    private func refreshDirectionIfNeeded() {
        let direction = LanguageDirectionStore.shared.current()
        guard stateMachine.direction != direction, let lexicon else { return }
        let configuration = Self.makeStateMachine(lexicon: lexicon, direction: direction)
        stateMachine = configuration.stateMachine
        stateMachine.updateSelectionCounts(selectionStore.counts)
        usesRime = configuration.usesRime
    }

    private static func makeStateMachine(
        lexicon: SQLiteLexicon,
        direction: LanguageDirection
    ) -> (stateMachine: CompositionStateMachine, usesRime: Bool) {
        if direction == .englishToChinese {
            return (
                CompositionStateMachine(
                    decoder: EnglishCandidateDecoder(lexicon: lexicon),
                    direction: direction,
                    defersCandidateUpdates: true
                ),
                false
            )
        }

        let sharedDataURL = Bundle.main.resourceURL?
            .appendingPathComponent("Rime", isDirectory: true)
        let userDataURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
            .appendingPathComponent("LinguaFlow", isDirectory: true)
            .appendingPathComponent("Rime", isDirectory: true)
        if let sharedDataURL,
           let userDataURL,
           let rimeDecoder = RimeHybridDecoder(
               sharedDataURL: sharedDataURL,
               userDataURL: userDataURL,
               lexicon: lexicon
           ) {
            return (
                CompositionStateMachine(
                    decoder: rimeDecoder,
                    defersCandidateUpdates: true
                ),
                true
            )
        }
        return (
            CompositionStateMachine(
                lexicon: lexicon,
                defersCandidateUpdates: true
            ),
            false
        )
    }

}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
