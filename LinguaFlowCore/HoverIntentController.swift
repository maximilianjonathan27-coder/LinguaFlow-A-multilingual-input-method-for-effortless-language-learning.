import Foundation

@MainActor
public final class HoverIntentController {
    public enum State: Equatable { case idle, pending(String), visible(String) }

    public private(set) var state: State = .idle
    public var onIntent: ((String) -> Void)?
    public var onDismiss: (() -> Void)?

    private let hoverDelay: TimeInterval
    private let dismissDelay: TimeInterval
    private var hoverWorkItem: DispatchWorkItem?
    private var dismissWorkItem: DispatchWorkItem?
    private var pointerInTranslation = false
    private var pointerInCard = false

    public init(hoverDelay: TimeInterval = 0.5, dismissDelay: TimeInterval = 0.25) {
        self.hoverDelay = hoverDelay
        self.dismissDelay = dismissDelay
    }

    public func pointerEnteredTranslation(_ rawTerm: String) {
        let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        pointerInTranslation = true
        cancelDismissal()
        guard state != .visible(term), state != .pending(term) else { return }
        hoverWorkItem?.cancel()
        state = .pending(term)
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.pointerInTranslation, self.state == .pending(term) else { return }
            self.state = .visible(term)
            self.onIntent?(term)
        }
        hoverWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverDelay, execute: item)
    }

    public func pointerExitedTranslation() {
        pointerInTranslation = false
        if case .pending = state {
            hoverWorkItem?.cancel()
            state = .idle
        } else {
            scheduleDismissalIfNeeded()
        }
    }

    public func pointerEnteredCard() {
        pointerInCard = true
        cancelDismissal()
    }

    public func pointerExitedCard() {
        pointerInCard = false
        // Card and candidate windows can overlap during a fast pointer movement,
        // leaving the translation tracking flag briefly stale.  Leaving the card
        // is nevertheless an explicit dismissal intent unless the pointer comes
        // back to a translation and cancels this timer.
        scheduleCardExitDismissal()
    }

    public func reset() {
        hoverWorkItem?.cancel()
        dismissWorkItem?.cancel()
        pointerInTranslation = false
        pointerInCard = false
        let wasActive = state != .idle
        state = .idle
        if wasActive { onDismiss?() }
    }

    public func dismissImmediately() {
        hoverWorkItem?.cancel()
        dismissWorkItem?.cancel()
        hoverWorkItem = nil
        dismissWorkItem = nil
        pointerInTranslation = false
        pointerInCard = false
        state = .idle
        onDismiss?()
    }

    private func scheduleDismissalIfNeeded() {
        guard !pointerInTranslation, !pointerInCard, case .visible = state else { return }
        dismissWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.pointerInTranslation, !self.pointerInCard else { return }
            self.state = .idle
            self.onDismiss?()
        }
        dismissWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay, execute: item)
    }

    private func scheduleCardExitDismissal() {
        guard !pointerInCard, case .visible = state else { return }
        dismissWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.pointerInCard else { return }
            self.state = .idle
            self.onDismiss?()
        }
        dismissWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay, execute: item)
    }

    private func cancelDismissal() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
    }
}
