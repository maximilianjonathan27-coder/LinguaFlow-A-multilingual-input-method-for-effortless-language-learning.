import SwiftUI
import LinguaFlowCore

private struct PreviewCandidate: Identifiable, Equatable {
    let id: Int
    let source: String
    let translated: String
    let count: Int
}

struct CandidatePreview: View {
    @ObservedObject var settings: LinguaFlowSettings
    var compact = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focusedCandidate: Int?
    @State private var cardCandidate: PreviewCandidate?
    @State private var pendingCardTask: Task<Void, Never>?

    private var candidates: [PreviewCandidate] {
        let pairs: [(String, String)] = settings.languageDirection == .chineseToEnglish
            ? [("会议", "meeting"), ("会见", "meet with"), ("回家", "go home"), ("讨论", "discussion"), ("预约", "appointment")]
            : [("meeting", "会议"), ("meet", "会见"), ("go home", "回家"), ("discussion", "讨论"), ("appointment", "预约")]
        return pairs.enumerated().map { index, pair in
            PreviewCandidate(id: index, source: pair.0, translated: pair.1, count: max(1, 7 - index))
        }
    }

    private var visibleCandidates: [PreviewCandidate] {
        Array(candidates.prefix(compact ? min(3, settings.candidateCount) : settings.candidateCount))
    }

    var body: some View {
        PremiumGlassSurface(
            cornerRadius: 20,
            glassEnabled: settings.glassEnabled,
            ambient: settings.quietFlowEnabled,
            interactive: true,
            pointerLight: settings.pointerLightEnabled,
            ambientIntensity: settings.ambientIntensity
        ) {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    previewHeader

                    ForEach(Array(visibleCandidates.enumerated()), id: \.element.id) { index, candidate in
                        candidateRow(candidate, index: index)
                        if index < visibleCandidates.count - 1 {
                            Divider().opacity(0.55).padding(.leading, 47)
                        }
                    }
                }

                if let cardCandidate, settings.vocabularyCardEnabled, !compact {
                    demoVocabularyCard(cardCandidate)
                        .padding(15)
                        .transition(.opacity.combined(with: .offset(y: 5)))
                        .zIndex(4)
                }
            }
        }
        .frame(minHeight: compact ? 228 : 344)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: cardCandidate)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: settings.translationPosition)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: settings.languageDirection)
        .onDisappear { pendingCardTask?.cancel() }
    }

    private var previewHeader: some View {
        HStack(spacing: 9) {
            HStack(spacing: 5) {
                Circle().fill(Color.red.opacity(0.75)).frame(width: 8, height: 8)
                Circle().fill(Color.yellow.opacity(0.75)).frame(width: 8, height: 8)
                Circle().fill(Color.green.opacity(0.75)).frame(width: 8, height: 8)
            }

            Text(settings.languageDirection == .chineseToEnglish ? "huiyi" : "meeting")
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer()

            Label("实时预览", systemImage: "sparkle")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 13)
        .background(Color.primary.opacity(0.025))
        .overlay(alignment: .bottom) { Divider().opacity(0.55) }
    }

    private func candidateRow(_ candidate: PreviewCandidate, index: Int) -> some View {
        let isFocused = focusedCandidate == candidate.id
        let fontSize = (compact ? 19.0 : 22.0) * settings.candidateScale

        return HStack(alignment: .center, spacing: 12) {
            Text("\(index + 1)")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(index == 0 ? Color.white : Color.secondary)
                .frame(width: 27, height: 27)
                .background(index == 0 ? Color.accentColor : Color.primary.opacity(0.065), in: Circle())

            if settings.translationPosition == .right {
                sourceColumn(candidate, fontSize: fontSize)

                Spacer(minLength: 20)

                if settings.translationEnabled {
                    translationText(candidate, fontSize: fontSize, isFocused: isFocused)
                        .frame(maxWidth: compact ? 190 : 300, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    sourceColumn(candidate, fontSize: fontSize)
                    if settings.translationEnabled {
                        translationText(candidate, fontSize: fontSize, isFocused: isFocused)
                    }
                }
                Spacer()
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, compact ? 10 : 12)
        .background(index == 0 ? Color.accentColor.opacity(0.075) : Color.clear)
    }

    private func sourceColumn(_ candidate: PreviewCandidate, fontSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(candidate.source)
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            if settings.exposureCountEnabled {
                Text("Seen \(candidate.count)×")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func translationText(
        _ candidate: PreviewCandidate,
        fontSize: CGFloat,
        isFocused: Bool
    ) -> some View {
        Text(candidate.translated)
            .font(.system(size: fontSize * 0.70, weight: isFocused ? .semibold : .medium, design: .rounded))
            .foregroundStyle(isFocused ? Color.accentColor : Color.primary.opacity(0.78))
            .lineLimit(2)
            .minimumScaleFactor(0.84)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                Color.accentColor.opacity(isFocused && settings.magnifyingHoverEnabled ? 0.085 : 0),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .scaleEffect(
                isFocused && settings.magnifyingHoverEnabled && !reduceMotion ? 1.035 : 1,
                anchor: .leading
            )
            .animation(.easeOut(duration: 0.16), value: isFocused)
            .contentShape(Rectangle())
            .onHover { hovering in handleHover(hovering, candidate: candidate) }
            .help("悬停查看词汇卡片")
    }

    private func handleHover(_ hovering: Bool, candidate: PreviewCandidate) {
        pendingCardTask?.cancel()
        if hovering {
            focusedCandidate = candidate.id
            guard settings.vocabularyCardEnabled, !compact else { return }
            let delay = UInt64(max(0.15, settings.hoverDelay) * 1_000_000_000)
            pendingCardTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled, focusedCandidate == candidate.id else { return }
                cardCandidate = candidate
            }
        } else {
            focusedCandidate = nil
            cardCandidate = nil
        }
    }

    private func demoVocabularyCard(_ candidate: PreviewCandidate) -> some View {
        PremiumGlassSurface(cornerRadius: 15, interactive: false) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(candidate.translated)
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                        Text("/ˈmiːtɪŋ/ · noun")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    Spacer()
                    Image(systemName: settings.pronunciationEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .foregroundStyle(Color.accentColor)
                }

                Divider()

                if settings.chineseDefinitionEnabled {
                    Text("会议 · 会面 · 集会")
                        .font(.system(size: 13.5, weight: .semibold))
                }
                if settings.englishDefinitionEnabled {
                    Text("an occasion when people come together to discuss something")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if settings.examplesEnabled {
                    Text("We have a meeting this afternoon.")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(15)
            .frame(width: 292, alignment: .leading)
        }
        .shadow(color: .black.opacity(0.22), radius: 22, y: 10)
    }
}
