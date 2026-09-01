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
    private let usesRime: Bool
    private lazy var exposureStore = ExposureStore()
    private lazy var selectionStore = SelectionStore()
    private var lastExposedCandidateIDs: [String] = []
    private var lastCaretRectangle = NSRect.zero
    private lazy var candidatePanel: CandidatePanelController = {
        let controller = CandidatePanelController()
        controller.onSelect = { [weak self] candidateID in
            self?.selectCandidate(id: candidateID)
        }
        return controller
    }()

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        if let databaseURL = Bundle.main.url(forResource: "linguaflow", withExtension: "sqlite"),
           let sqliteLexicon = try? SQLiteLexicon(databaseURL: databaseURL) {
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
                   lexicon: sqliteLexicon
               ) {
                stateMachine = CompositionStateMachine(decoder: rimeDecoder)
                usesRime = true
            } else {
                stateMachine = CompositionStateMachine(lexicon: sqliteLexicon)
                usesRime = false
            }
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
            } else if let punctuation = PinyinNormalizer.chinesePunctuation(
                for: String(character)
            ) {
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
            candidatePanel.hide()
            return
        }
        _ = apply(stateMachine.handle(.deactivate), to: inputClient)
    }

    override func activateServer(_ sender: Any!) {
        exposureStore.refresh()
        selectionStore.refresh()
        stateMachine.updateSelectionCounts(selectionStore.counts)
        super.activateServer(sender)
    }

    override func deactivateServer(_ sender: Any!) {
        if let inputClient = sender as? (any IMKTextInput) {
            _ = apply(stateMachine.handle(.deactivate), to: inputClient)
        } else {
            stateMachine.reset()
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

        if let punctuation = PinyinNormalizer.chinesePunctuation(for: producedText) {
            return .punctuation(punctuation)
        }

        return nil
    }

    private func apply(
        _ transition: CompositionStateMachine.Transition,
        to inputClient: any IMKTextInput
    ) -> Bool {
        for effect in transition.effects {
            switch effect {
            case let .updateMarkedText(text, cursor):
                inputClient.setMarkedText(
                    text,
                    selectionRange: NSRange(location: cursor, length: 0),
                    replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
                )

            case let .updateCandidates(candidates, selectedIndex):
                exposureStore.refresh()
                let candidateIDs = candidates.map(\.id)
                if candidateIDs != lastExposedCandidateIDs {
                    _ = exposureStore.increment(candidates)
                    lastExposedCandidateIDs = candidateIDs
                }
                candidatePanel.show(
                    compactCandidates: candidates,
                    expandedCandidates: stateMachine.allCandidates,
                    selectedCandidateID: candidates[safe: selectedIndex]?.id,
                    query: stateMachine.displayedBuffer,
                    counts: exposureStore.counts,
                    anchor: caretRectangle(for: inputClient)
                )

            case .hideCandidates:
                candidatePanel.hide()
                lastExposedCandidateIDs = []

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

        return !transition.forwardsOriginalEvent
    }

    private func caretRectangle(for inputClient: any IMKTextInput) -> NSRect {
        // IMK expects an index relative to the active marked-text session here,
        // not the document-relative selectedRange. Passing selectedRange.location
        // makes many web editors return an empty rectangle.
        let displayCursor = PinyinNormalizer.compositionDisplay(
            stateMachine.buffer,
            rawCursor: stateMachine.cursor
        ).cursor
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

}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
