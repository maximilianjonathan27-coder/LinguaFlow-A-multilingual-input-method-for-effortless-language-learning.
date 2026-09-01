import AppKit
import LinguaFlowCore
import SwiftUI

@MainActor
final class CandidatePanelController {
    var onSelect: ((String) -> Void)?
    var isExpanded: Bool { model.isExpanded }

    private let model = CandidatePanelModel()
    private let panel: CandidatePanel
    private let compactSize = NSSize(width: 360, height: 218)
    private let expandedPageSize = 12
    private var compactCandidates: [Candidate] = []
    private var expandedCandidates: [Candidate] = []
    private var selectedCandidateID: String?
    private var lastAnchor = NSRect.zero
    private var currentQuery = ""
    private var expandedPageIndex = 0

    init() {
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
        panel.becomesKeyOnlyIfNeeded = true

        let rootView = CandidatePanelView(
            model: model,
            onSelect: { [weak self] candidateID in
                self?.onSelect?(candidateID)
            },
            onToggleExpanded: { [weak self] in
                guard let self else { return }
                self.setExpanded(!self.isExpanded)
            }
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let glassView = NSVisualEffectView(frame: NSRect(origin: .zero, size: compactSize))
        glassView.material = .popover
        glassView.blendingMode = .behindWindow
        glassView.state = .active
        glassView.wantsLayer = true
        glassView.layer?.cornerRadius = 14
        glassView.layer?.cornerCurve = .continuous
        glassView.layer?.masksToBounds = true
        glassView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: glassView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: glassView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: glassView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: glassView.bottomAnchor),
        ])
        panel.contentView = glassView
    }

    func show(
        compactCandidates: [Candidate],
        expandedCandidates: [Candidate],
        selectedCandidateID: String?,
        query: String,
        counts: [String: Int],
        anchor: NSRect
    ) {
        if currentQuery != query {
            expandedPageIndex = 0
        }
        self.compactCandidates = compactCandidates
        self.expandedCandidates = expandedCandidates
        self.selectedCandidateID = selectedCandidateID
        currentQuery = query
        lastAnchor = anchor
        model.counts = counts
        model.query = query
        updateVisibleCandidates()
        positionPanel()
        panel.orderFrontRegardless()
    }

    func updateCounts(_ counts: [String: Int]) {
        model.counts = counts
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
        panel.orderOut(nil)
        model.isExpanded = false
        compactCandidates = []
        expandedCandidates = []
        selectedCandidateID = nil
        expandedPageIndex = 0
        model.selectedIndex = 0
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
