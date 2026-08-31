import AppKit
import InputMethodKit
import LinguaFlowCore

@objc(LinguaFlowInputController)
@MainActor
final class LinguaFlowInputController: IMKInputController {
    private var stateMachine: CompositionStateMachine
    private lazy var exposureStore = ExposureStore()
    private lazy var selectionStore = SelectionStore()
    private var lastExposedCandidateIDs: [String] = []
    private lazy var candidatePanel: CandidatePanelController = {
        let controller = CandidatePanelController()
        controller.onSelect = { [weak self] index in
            self?.selectCandidate(at: index)
        }
        return controller
    }()

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        if let databaseURL = Bundle.main.url(forResource: "linguaflow", withExtension: "sqlite"),
           let sqliteLexicon = try? SQLiteLexicon(databaseURL: databaseURL) {
            stateMachine = CompositionStateMachine(lexicon: sqliteLexicon)
        } else {
            stateMachine = CompositionStateMachine()
        }
        super.init(server: server, delegate: delegate, client: inputClient)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard
            let event,
            event.type == .keyDown,
            let inputClient = sender as? (any IMKTextInput)
        else {
            return false
        }

        let shortcutModifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard shortcutModifiers.isEmpty else { return false }
        if stateMachine.buffer.isEmpty,
           event.modifierFlags.contains(.capsLock) || event.modifierFlags.contains(.shift) {
            return false
        }

        guard let action = action(for: event) else {
            if stateMachine.buffer.isEmpty { return false }
            return apply(stateMachine.handle(.punctuation(event.characters ?? "")), to: inputClient)
        }

        return apply(stateMachine.handle(action), to: inputClient)
    }

    override func composedString(_ sender: Any!) -> Any! {
        stateMachine.buffer
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

        let text = event.charactersIgnoringModifiers ?? ""
        if let number = Int(text), (1...5).contains(number), !stateMachine.candidates.isEmpty {
            return .selectCandidate(number - 1)
        }

        if text.count == 1, let character = text.first,
           character.isASCII, character.isLetter || character == "'" {
            return .insertLetter(character)
        }

        if let punctuation = Self.chinesePunctuation[text] {
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
                    candidates: candidates,
                    selectedIndex: selectedIndex,
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
        let selectedRange = inputClient.selectedRange()
        var lineRectangle = NSRect.zero
        let index = selectedRange.location == NSNotFound ? 0 : selectedRange.location
        _ = inputClient.attributes(
            forCharacterIndex: index,
            lineHeightRectangle: &lineRectangle
        )

        if lineRectangle.isEmpty {
            let mouse = NSEvent.mouseLocation
            return NSRect(x: mouse.x, y: mouse.y, width: 1, height: 20)
        }
        return lineRectangle
    }

    private func selectCandidate(at index: Int) {
        guard let inputClient = client() else { return }
        _ = apply(stateMachine.handle(.selectCandidate(index)), to: inputClient)
    }

    private static let chinesePunctuation: [String: String] = [
        ",": "，", ".": "。", "?": "？", "!": "！",
        ";": "；", ":": "：", "(": "（", ")": "）",
        "[": "【", "]": "】", "<": "《", ">": "》",
    ]
}
