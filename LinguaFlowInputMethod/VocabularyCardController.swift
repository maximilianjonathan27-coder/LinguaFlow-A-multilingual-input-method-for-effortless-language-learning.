import AppKit
import LinguaFlowCore
import SwiftUI

@MainActor
final class VocabularyCardController {
    var onHoverChanged: ((Bool) -> Void)?
    var onClose: (() -> Void)?
    var onPronounce: ((Candidate) -> Void)?
    var onPresented: ((Candidate, String?) -> Void)?
    private let provider: any DictionaryProviding
    private let cache: DictionaryCache
    private let panel: VocabularyPanel
    private var requestID = UUID()
    private var dismissalID = UUID()
    private var presentationModel: VocabularyCardPresentationModel?
    private var presentedCandidateID: String?
    private var hoverMonitor: Timer?
    private var pointerIsInsideCard = false

    init(provider: any DictionaryProviding = AppleDictionaryProvider(), cache: DictionaryCache = DictionaryCache()) {
        self.provider = provider
        self.cache = cache
        panel = VocabularyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // The card is a mouse-only adjunct to the active IME composition.  Allowing
        // it to become key can detach the text client and make subsequent keystrokes
        // bypass candidate generation.
        panel.becomesKeyOnlyIfNeeded = false
        panel.acceptsMouseMovedEvents = true
    }

    func show(candidate: Candidate, beside anchor: NSRect) {
        let id = UUID()
        requestID = id
        presentedCandidateID = candidate.id
        let provider = provider
        let cache = cache
        let lookupTerm = candidate.sourceLanguage == .english
            ? candidate.sourceText
            : candidate.translation
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let entry = cache.value(for: lookupTerm) { provider.lookup(lookupTerm) }
            DispatchQueue.main.async {
                guard let self, self.requestID == id else { return }
                self.present(entry: entry, candidate: candidate, beside: anchor)
            }
        }
    }

    func setSpeakingCandidateID(_ candidateID: String?) {
        presentationModel?.isSpeaking = candidateID == presentedCandidateID
    }

    func hide() {
        requestID = UUID()
        presentedCandidateID = nil
        stopHoverMonitoring()
        let id = UUID()
        dismissalID = id
        panel.ignoresMouseEvents = true
        guard let presentationModel else {
            panel.orderOut(nil)
            return
        }
        presentationModel.isPresented = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.dismissalID == id else { return }
            self.panel.orderOut(nil)
            self.presentationModel = nil
        }
    }

    private func present(entry: DictionaryEntry?, candidate: Candidate, beside anchor: NSRect) {
        let term = candidate.sourceLanguage == .english
            ? candidate.sourceText
            : candidate.translation
        let fallbackTerm = DictionaryLookupPlanner.lookupTerms(for: term).first ?? term
        let dictionaryContent = entry.map {
            DictionaryCardContentParser.parse($0.definition, fallbackTerm: fallbackTerm)
        } ?? DictionaryCardContent(
            headword: fallbackTerm,
            pronunciation: nil,
            partOfSpeech: nil,
            englishDefinition: "No English definition is available in the installed macOS dictionaries.",
            examples: [],
            phrasesAndIdioms: []
        )
        let offlineExamples = candidate.examples.map { example in
            "\(example.english)\n\(example.chinese)"
        }
        var seenExamples: Set<String> = []
        let mergedExamples = (dictionaryContent.examples + offlineExamples)
            .filter { seenExamples.insert($0).inserted }
        let structuredGlosses = candidate.translationSenses
            .flatMap(\.glosses)
            .filter { !$0.isEmpty }
        let fallbackDefinition = structuredGlosses.isEmpty
            ? dictionaryContent.englishDefinition
            : structuredGlosses.prefix(6).joined(separator: "; ")
        let content = DictionaryCardContent(
            headword: dictionaryContent.headword,
            pronunciation: dictionaryContent.pronunciation,
            partOfSpeech: dictionaryContent.partOfSpeech ?? candidate.partOfSpeech,
            englishDefinition: entry == nil ? fallbackDefinition : dictionaryContent.englishDefinition,
            examples: mergedExamples,
            phrasesAndIdioms: dictionaryContent.phrasesAndIdioms
        )
        let presentationModel = VocabularyCardPresentationModel()
        self.presentationModel = presentationModel
        dismissalID = UUID()
        panel.ignoresMouseEvents = false
        let view = VocabularyCardView(
            content: content,
            chineseMeaning: candidate.sourceLanguage == .english
                ? candidate.translation
                : candidate.sourceText,
            presentation: presentationModel,
            onPronounce: { [weak self] in self?.onPronounce?(candidate) },
            onClose: { [weak self] in self?.onClose?() }
        )
        let hosting = VocabularyHostingView(rootView: view)
        hosting.onHoverChanged = { [weak self] inside in
            self?.handleHoverChanged(inside)
        }
        let fitting = hosting.fittingSize
        let size = NSSize(width: min(max(fitting.width, 410), 480), height: min(max(fitting.height, 330), 560))
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        let screen = NSScreen.screens.max { $0.frame.intersection(anchor).area < $1.frame.intersection(anchor).area } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        var origin = NSPoint(x: anchor.maxX + 10, y: anchor.maxY - size.height)
        if origin.x + size.width > visible.maxX { origin.x = anchor.minX - size.width - 10 }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
        startHoverMonitoring()
        // This is the intentional-learning event: it fires only after a card is actually presented.
        onPresented?(candidate, entry?.definition)
        DispatchQueue.main.async { [weak presentationModel] in
            presentationModel?.isPresented = true
        }
    }

    private func startHoverMonitoring() {
        stopHoverMonitoring()
        // A SwiftUI button update (such as the pronunciation control changing to
        // its active state) can rebuild AppKit tracking areas without an exit
        // event. Polling the panel's actual screen frame while it is visible keeps
        // the hover intent truthful and preserves the 250 ms auto-dismiss rule.
        pointerIsInsideCard = false
        syncPointerLocation()
        hoverMonitor = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            self?.syncPointerLocation()
        }
    }

    private func stopHoverMonitoring() {
        hoverMonitor?.invalidate()
        hoverMonitor = nil
        pointerIsInsideCard = false
    }

    private func syncPointerLocation() {
        guard panel.isVisible else {
            stopHoverMonitoring()
            return
        }

        let isInside = panel.frame.contains(NSEvent.mouseLocation)
        handleHoverChanged(isInside)
    }

    private func handleHoverChanged(_ isInside: Bool) {
        guard isInside != pointerIsInsideCard else { return }
        pointerIsInsideCard = isInside
        onHoverChanged?(isInside)
    }
}

@MainActor
private final class VocabularyCardPresentationModel: ObservableObject {
    @Published var isPresented = false
    @Published var isSpeaking = false
}

private struct VocabularyCardView: View {
    let content: DictionaryCardContent
    let chineseMeaning: String
    @ObservedObject var presentation: VocabularyCardPresentationModel
    let onPronounce: () -> Void
    let onClose: () -> Void
    @State private var isHovered = false
    @State private var isFloating = false
    @State private var isBreathing = false
    @State private var selectedSection: VocabularySection = .definition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(content.headword)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .tracking(-0.7)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(.primary.opacity(0.065), in: Circle())
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help("Close vocabulary card")
                .accessibilityLabel("关闭词汇卡片")
            }

            HStack(spacing: 8) {
                Button(action: onPronounce) {
                    HStack(spacing: 6) {
                        Image(systemName: presentation.isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                            .symbolEffect(.variableColor.iterative, isActive: presentation.isSpeaking && !reduceMotion)
                        if let pronunciation = content.pronunciation {
                            Text("/\(pronunciation)/")
                        } else {
                            Text("播放发音")
                        }
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(presentation.isSpeaking ? 0.16 : 0.08), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Play pronunciation")
                .accessibilityLabel("播放 \(content.headword) 的发音")
                if let partOfSpeech = content.partOfSpeech {
                    Text(partOfSpeech.lowercased() + ".")
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12.5, design: .rounded))
            .padding(.top, 5)

            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    HStack(spacing: 20) {
                        SectionNavigationButton(
                            title: "释义",
                            icon: "text.quote",
                            count: nil,
                            isSelected: selectedSection == .definition,
                            isEnabled: true
                        ) { navigate(to: .definition, proxy: proxy) }
                        SectionNavigationButton(
                            title: "例句",
                            icon: "quote.bubble",
                            count: content.examples.count,
                            isSelected: selectedSection == .examples,
                            isEnabled: !content.examples.isEmpty
                        ) { navigate(to: .examples, proxy: proxy) }
                        SectionNavigationButton(
                            title: "短语 · Idioms",
                            icon: "sparkles",
                            count: content.phrasesAndIdioms.count,
                            isSelected: selectedSection == .phrases,
                            isEnabled: !content.phrasesAndIdioms.isEmpty
                        ) { navigate(to: .phrases, proxy: proxy) }
                    }
                    .padding(.top, 17)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(.primary.opacity(0.10)).frame(height: 0.5)
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            LearningSection(title: "释义  Definition", icon: "text.quote", tint: .blue) {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        if let partOfSpeech = content.partOfSpeech {
                                            Text(abbreviation(for: partOfSpeech))
                                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(chineseMeaning.isEmpty ? "暂无中文释义" : chineseMeaning)
                                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                                    }
                                    Rectangle().fill(.primary.opacity(0.08)).frame(height: 0.5)
                                    Text(content.englishDefinition)
                                        .foregroundStyle(.secondary)
                                        .lineSpacing(4)
                                }
                            }
                            .id(VocabularySection.definition)

                            if !content.examples.isEmpty {
                                LearningSection(title: "例句  Examples", icon: "quote.bubble.fill", tint: .blue) {
                                    VStack(alignment: .leading, spacing: 0) {
                                        ForEach(Array(content.examples.enumerated()), id: \.offset) { index, example in
                                            ExampleRow(index: index + 1, text: example, headword: content.headword)
                                            if index < content.examples.count - 1 {
                                                Rectangle()
                                                    .fill(.primary.opacity(0.08))
                                                    .frame(height: 0.5)
                                                    .padding(.vertical, 11)
                                            }
                                        }
                                    }
                                }
                                .id(VocabularySection.examples)
                            }

                            if !content.phrasesAndIdioms.isEmpty {
                                LearningSection(title: "相关短语与 Idioms", icon: "sparkles", tint: .purple) {
                                    VStack(alignment: .leading, spacing: 0) {
                                        ForEach(Array(content.phrasesAndIdioms.enumerated()), id: \.offset) { index, entry in
                                            PhraseEntryRow(entry: entry)
                                            if index < content.phrasesAndIdioms.count - 1 {
                                                Rectangle()
                                                    .fill(.primary.opacity(0.08))
                                                    .frame(height: 0.5)
                                                    .padding(.vertical, 12)
                                            }
                                        }
                                    }
                                }
                                .id(VocabularySection.phrases)
                            }

                            if content.examples.isEmpty, content.phrasesAndIdioms.isEmpty {
                                EmptyLearningState()
                            }
                        }
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .padding(.top, 12)
                        .padding(.trailing, 6)
                    }
                    .scrollIndicators(.visible)
                    .frame(maxHeight: 390)
                }
            }

            HStack(spacing: 5) {
                Image(systemName: "apple.logo").font(.system(size: 9, weight: .medium))
                Text("macOS Dictionary · LinguaFlow offline examples")
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary.opacity(0.82))
            .padding(.top, 10)
        }
        .padding(18)
        .frame(minWidth: 370, maxWidth: 440, minHeight: 290, maxHeight: 520)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [.white.opacity(0.28), .white.opacity(0.04), Color.accentColor.opacity(0.035)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(isBreathing && !reduceMotion ? 0.64 : 0.54),
                            .primary.opacity(isBreathing && !reduceMotion ? 0.12 : 0.08),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
        .shadow(
            color: .black.opacity(isBreathing && !reduceMotion ? 0.15 : 0.11),
            radius: isBreathing && !reduceMotion ? 18 : 15,
            y: 7
        )
        .scaleEffect(reduceMotion ? 1 : (presentation.isPresented ? (isHovered ? 1.004 : 1) : 0.99))
        .offset(y: reduceMotion ? 0 : (presentation.isPresented ? 0 : 4))
        .offset(y: reduceMotion ? 0 : (isFloating ? -1 : 1))
        .opacity(presentation.isPresented ? 1 : 0)
        .padding(2)
        .animation(.easeOut(duration: presentation.isPresented ? 0.19 : 0.15), value: presentation.isPresented)
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .onAppear { updateAmbientMotion(reduceMotion: reduceMotion) }
        .onChange(of: reduceMotion) { _, reduced in
            updateAmbientMotion(reduceMotion: reduced)
        }
        .onHover { inside in
            isHovered = inside
        }
    }

    private func abbreviation(for partOfSpeech: String) -> String {
        switch partOfSpeech.lowercased() {
        case "noun": return "n."
        case "verb": return "v."
        case "adjective": return "adj."
        case "adverb": return "adv."
        case "preposition": return "prep."
        case "pronoun": return "pron."
        case "conjunction": return "conj."
        default: return partOfSpeech + "."
        }
    }

    private func navigate(to section: VocabularySection, proxy: ScrollViewProxy) {
        guard section == .definition
                || section == .examples && !content.examples.isEmpty
                || section == .phrases && !content.phrasesAndIdioms.isEmpty else { return }
        selectedSection = section
        if reduceMotion {
            proxy.scrollTo(section, anchor: .top)
        } else {
            withAnimation(.easeInOut(duration: 0.22)) {
                proxy.scrollTo(section, anchor: .top)
            }
        }
    }

    private func updateAmbientMotion(reduceMotion: Bool) {
        if reduceMotion {
            isFloating = false
            isBreathing = false
            return
        }
        withAnimation(.easeInOut(duration: 5.8).repeatForever(autoreverses: true)) {
            isFloating = true
        }
        withAnimation(.easeInOut(duration: 7.2).repeatForever(autoreverses: true)) {
            isBreathing = true
        }
    }
}

private enum VocabularySection: Hashable {
    case definition
    case examples
    case phrases
}

private struct SectionNavigationButton: View {
    let title: String
    let icon: String
    let count: Int?
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(title)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.primary.opacity(0.07), in: Capsule())
                }
            }
            .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium, design: .rounded))
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .padding(.bottom, 9)
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .opacity(isSelected ? 1 : 0)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.38)
    }
}

private struct PhraseEntryRow: View {
    let entry: DictionaryPhraseEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(entry.category)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Color.purple)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.purple.opacity(0.10), in: Capsule())
            Text(entry.expression)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            if let explanation = entry.explanation, !explanation.isEmpty {
                Text(explanation)
                    .font(.system(size: 12.5, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ExampleRow: View {
    let index: Int
    let text: String
    let headword: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(index)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .frame(width: 19, height: 19)
                .background(Color.accentColor.opacity(0.10), in: Circle())
            highlightedText
                .font(.system(size: 13.5, weight: .regular, design: .rounded))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var highlightedText: Text {
        guard let range = text.range(of: headword, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return Text(text)
        }
        return Text(String(text[..<range.lowerBound]))
            + Text(String(text[range])).foregroundColor(.accentColor).bold()
            + Text(String(text[range.upperBound...]))
    }
}

private struct EmptyLearningState: View {
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "books.vertical")
                .foregroundStyle(Color.accentColor)
            Text("当前本地词典暂未提供例句或短语。")
                .foregroundStyle(.secondary)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct LearningSection<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    let content: Content

    init(title: String, icon: String, tint: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(tint.opacity(0.15), lineWidth: 0.7)
        }
    }
}

private final class VocabularyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { false }
}

private final class VocabularyHostingView<Content: View>: NSHostingView<Content> {
    var onHoverChanged: ((Bool) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChanged?(false)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override var acceptsFirstResponder: Bool { false }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
