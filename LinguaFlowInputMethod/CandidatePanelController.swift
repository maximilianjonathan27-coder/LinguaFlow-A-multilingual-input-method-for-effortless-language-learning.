import AppKit
import LinguaFlowCore
import SwiftUI

@MainActor
final class CandidatePanelController {
    var onSelect: ((String) -> Void)?
    var onPronunciationPlayed: ((Candidate) -> Void)?
    var isExpanded: Bool { model.isExpanded }

    private let model = CandidatePanelModel()
    private let panel: CandidatePanel
    private let compactSize = NSSize(
        width: CandidatePanelLayout.compactWidth,
        height: CandidatePanelLayout.minimumHeight
    )
    private let expandedPageSize = 12
    private var compactCandidates: [Candidate] = []
    private var expandedCandidates: [Candidate] = []
    private var selectedCandidateID: String?
    private var lastAnchor = NSRect.zero
    private var currentQuery = ""
    private var expandedPageIndex = 0
    private let hoverIntent = HoverIntentController()
    private let vocabularyCard = VocabularyCardController()
    private let pronunciationController: PronunciationController
    private var candidateByID: [String: Candidate] = [:]

    init(speechProvider: (any SpeechProviding)? = nil) {
        pronunciationController = PronunciationController(
            speechProvider: speechProvider ?? AppleSpeechProvider()
        )
        panel = CandidatePanel(
            contentRect: NSRect(origin: .zero, size: compactSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false

        let rootView = CandidatePanelView(
            model: model,
            onSelect: { [weak self] candidateID in
                self?.onSelect?(candidateID)
            },
            onToggleExpanded: { [weak self] in
                guard let self else { return }
                self.setExpanded(!self.isExpanded)
            },
            onTranslationHover: { [weak self] candidate, inside in
                guard let self else { return }
                if inside { self.hoverIntent.pointerEnteredTranslation(candidate.id) }
                else { self.hoverIntent.pointerExitedTranslation() }
            },
            onTranslationDoubleClick: { [weak self] candidate in
                self?.pronunciationController.pronounce(candidate)
            }
        )
        panel.contentView = NSHostingView(rootView: rootView)

        hoverIntent.onIntent = { [weak self] candidateID in
            guard let self, let candidate = self.candidateByID[candidateID] else { return }
            let mouse = NSEvent.mouseLocation
            self.vocabularyCard.show(
                candidate: candidate,
                beside: NSRect(x: mouse.x, y: mouse.y, width: 1, height: 1)
            )
        }
        hoverIntent.onDismiss = { [weak self] in self?.vocabularyCard.hide() }
        vocabularyCard.onHoverChanged = { [weak self] inside in
            if inside { self?.hoverIntent.pointerEnteredCard() }
            else { self?.hoverIntent.pointerExitedCard() }
        }
        vocabularyCard.onClose = { [weak self] in self?.hoverIntent.dismissImmediately() }
        vocabularyCard.onPresented = { candidate, definition in
            VocabularyHistoryService.recordOpenedCard(for: candidate, definition: definition)
        }
        vocabularyCard.onPronounce = { [weak self] candidate in
            self?.pronunciationController.pronounce(candidate)
        }
        pronunciationController.onPronunciationPlayed = { [weak self] candidate in
            self?.onPronunciationPlayed?(candidate)
        }
        pronunciationController.onSpeakingCandidateChanged = { [weak self, weak model] candidateID in
            model?.speakingCandidateID = candidateID
            self?.vocabularyCard.setSpeakingCandidateID(candidateID)
        }
    }

    func show(
        compactCandidates: [Candidate],
        expandedCandidates: [Candidate],
        selectedCandidateID: String?,
        query: String,
        counts: [String: Int],
        anchor: NSRect
    ) {
        let shouldAnimateAppearance = !panel.isVisible
        if shouldAnimateAppearance { model.isPresented = false }
        if currentQuery != query {
            expandedPageIndex = 0
        }
        let newCandidateIDs = expandedCandidates.map(\.id)
        if Set(newCandidateIDs) != Set(candidateByID.keys) {
            hoverIntent.reset()
        }
        self.compactCandidates = compactCandidates
        self.expandedCandidates = expandedCandidates
        candidateByID = Dictionary(expandedCandidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.selectedCandidateID = selectedCandidateID
        currentQuery = query
        lastAnchor = anchor
        model.counts = counts
        model.query = query
        updateVisibleCandidates()
        positionPanel()
        panel.orderFrontRegardless()
        if shouldAnimateAppearance {
            DispatchQueue.main.async { [weak model] in model?.isPresented = true }
        } else {
            model.isPresented = true
        }
    }

    func updateCounts(_ counts: [String: Int]) {
        model.counts = counts
    }

    func updateTranslations(_ translations: [String: String], forQuery query: String) {
        guard currentQuery == query, !translations.isEmpty else { return }
        compactCandidates = compactCandidates.map { replacingTranslation(in: $0, using: translations) }
        expandedCandidates = expandedCandidates.map { replacingTranslation(in: $0, using: translations) }
        candidateByID = Dictionary(expandedCandidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        updateVisibleCandidates()
    }

    func setExpanded(_ expanded: Bool) {
        guard model.isExpanded != expanded else { return }
        model.isExpanded = expanded
        updateVisibleCandidates()
        positionPanel()
    }

    func moveExpandedPage(_ delta: Int) {
        guard model.isExpanded, !expandedCandidates.isEmpty else { return }
        let pageCount = max(1, Int(ceil(Double(expandedCandidates.count) / Double(expandedPageSize))))
        expandedPageIndex = (expandedPageIndex + delta + pageCount) % pageCount
        model.selectedIndex = 0
        updateVisibleCandidates()
    }

    func moveExpandedRow(_ delta: Int) {
        guard model.isExpanded, !model.candidates.isEmpty else { return }
        let rowCount = Int(ceil(Double(model.candidates.count) / 3.0))
        let currentColumn = model.selectedIndex % 3
        let currentRow = model.selectedIndex / 3
        let targetRow = currentRow + delta
        if targetRow >= rowCount {
            moveExpandedPage(1)
            model.selectedIndex = min(currentColumn, model.candidates.count - 1)
        } else if targetRow < 0 {
            moveExpandedPage(-1)
            let previousRowCount = max(1, Int(ceil(Double(model.candidates.count) / 3.0)))
            let rowStart = (previousRowCount - 1) * 3
            model.selectedIndex = min(rowStart + currentColumn, model.candidates.count - 1)
        } else {
            model.selectedIndex = min(targetRow * 3 + currentColumn, model.candidates.count - 1)
        }
    }

    func moveExpandedColumn(_ delta: Int) {
        guard model.isExpanded, model.candidates.indices.contains(model.selectedIndex) else { return }
        let targetIndex = model.selectedIndex + delta
        if targetIndex >= model.candidates.count {
            moveExpandedPage(1)
            model.selectedIndex = 0
        } else if targetIndex < 0 {
            moveExpandedPage(-1)
            model.selectedIndex = max(0, model.candidates.count - 1)
        } else {
            model.selectedIndex = targetIndex
        }
    }

    func candidateID(inColumn column: Int) -> String? {
        guard model.isExpanded, (0..<3).contains(column) else { return nil }
        let index = (model.selectedIndex / 3) * 3 + column
        guard model.candidates.indices.contains(index) else { return nil }
        return model.candidates[index].id
    }

    var highlightedCandidateID: String? {
        guard model.isExpanded, model.candidates.indices.contains(model.selectedIndex) else { return nil }
        return model.candidates[model.selectedIndex].id
    }

    func hide() {
        hoverIntent.reset()
        vocabularyCard.hide()
        model.isPresented = false
        panel.orderOut(nil)
        model.isExpanded = false
        compactCandidates = []
        expandedCandidates = []
        selectedCandidateID = nil
        expandedPageIndex = 0
        model.selectedIndex = 0
        candidateByID = [:]
    }

    func stopPronunciation() {
        pronunciationController.stop()
    }

    private func updateVisibleCandidates() {
        if model.isExpanded {
            let pageCount = max(1, Int(ceil(Double(expandedCandidates.count) / Double(expandedPageSize))))
            expandedPageIndex = min(expandedPageIndex, pageCount - 1)
            let start = expandedPageIndex * expandedPageSize
            model.candidates = Array(expandedCandidates.dropFirst(start).prefix(expandedPageSize))
            model.candidateNumberOffset = start
            model.pageIndex = expandedPageIndex
            model.pageCount = pageCount
        } else {
            model.candidates = compactCandidates
            model.candidateNumberOffset = 0
            model.pageIndex = 0
            model.pageCount = 1
        }
        model.selectedIndex = selectedCandidateID.flatMap { selectedID in
            model.candidates.firstIndex { $0.id == selectedID }
        } ?? 0
    }

    private func replacingTranslation(
        in candidate: Candidate,
        using translations: [String: String]
    ) -> Candidate {
        guard let translation = translations[candidate.id],
              translation != candidate.translation
        else { return candidate }
        return Candidate(
            id: candidate.id,
            pinyin: candidate.pinyin,
            sourceText: candidate.sourceText,
            translation: translation,
            frequency: candidate.frequency,
            sourceLanguage: candidate.sourceLanguage,
            targetLanguage: candidate.targetLanguage,
            partOfSpeech: candidate.partOfSpeech,
            domain: candidate.domain,
            style: candidate.style,
            translationSenses: candidate.translationSenses,
            isProperNoun: candidate.isProperNoun,
            examples: candidate.examples
        )
    }

    private func positionPanel() {
        let size = NSSize(
            width: model.isExpanded ? 620 : compactSize.width,
            height: model.panelHeight
        )
        let screen = screen(containing: lastAnchor) ?? NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }
        let frame = PanelPositioner.frame(
            anchor: lastAnchor,
            panelSize: size,
            visibleFrame: visibleFrame
        )
        panel.setFrame(frame, display: true, animate: panel.isVisible)
    }

    private func screen(containing rectangle: NSRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            lhs.frame.intersection(rectangle).area < rhs.frame.intersection(rectangle).area
        }
    }
}

private final class CandidatePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull else { return 0 }
        return width * height
    }
}
