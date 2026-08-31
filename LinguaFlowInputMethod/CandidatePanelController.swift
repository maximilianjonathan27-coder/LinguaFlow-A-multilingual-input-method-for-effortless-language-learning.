import AppKit
import LinguaFlowCore
import SwiftUI

@MainActor
final class CandidatePanelController {
    var onSelect: ((Int) -> Void)?

    private let model = CandidatePanelModel()
    private let panel: CandidatePanel
    private let panelSize = NSSize(width: 430, height: 258)

    init() {
        panel = CandidatePanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
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

        let rootView = CandidatePanelView(model: model) { [weak self] index in
            self?.onSelect?(index)
        }
        panel.contentView = NSHostingView(rootView: rootView)
    }

    func show(
        candidates: [Candidate],
        selectedIndex: Int,
        counts: [String: Int],
        anchor: NSRect
    ) {
        model.candidates = candidates
        model.selectedIndex = selectedIndex
        model.counts = counts

        let screen = screen(containing: anchor) ?? NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }
        let frame = PanelPositioner.frame(
            anchor: anchor,
            panelSize: panelSize,
            visibleFrame: visibleFrame
        )
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
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
