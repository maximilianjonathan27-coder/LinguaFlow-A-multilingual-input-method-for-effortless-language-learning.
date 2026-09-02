import LinguaFlowCore
import SwiftUI

@MainActor
final class CandidatePanelModel: ObservableObject {
    @Published var candidates: [Candidate] = []
    @Published var selectedIndex = 0
    @Published var counts: [String: Int] = [:]
    @Published var isExpanded = false
    @Published var query = ""
    @Published var candidateNumberOffset = 0
    @Published var pageIndex = 0
    @Published var pageCount = 1
    @Published var translationInteractionCandidateID: String?
    @Published var speakingCandidateID: String?
    @Published var isPresented = false

    var panelHeight: CGFloat {
        if isExpanded {
            let rows = max(1, Int(ceil(Double(candidates.count) / 3.0)))
            return CGFloat(72 + rows * 54 + max(0, rows - 1) * 8)
        }
        return CandidatePanelLayout.height(for: candidates)
    }
}

enum CandidatePanelLayout {
    static let compactWidth: CGFloat = 560
    static let minimumHeight: CGFloat = 258

    static func height(for candidates: [Candidate]) -> CGFloat {
        let rows = candidates.reduce(CGFloat.zero) { partial, candidate in
            let estimatedLines = max(1, Int(ceil(Double(candidate.sourceText.count) / 38.0)))
            return partial + max(52, CGFloat(estimatedLines) * 23 + 27)
        }
        return max(minimumHeight, rows + CGFloat(max(0, candidates.count - 1)) + 12)
    }
}

struct CandidatePanelView: View {
    @ObservedObject var model: CandidatePanelModel
    let onSelect: (String) -> Void
    let onToggleExpanded: () -> Void
    let onTranslationHover: (Candidate, Bool) -> Void
    let onTranslationDoubleClick: (Candidate) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 8),
        count: 3
    )

    var body: some View {
        Group {
            if model.isExpanded {
                expandedCandidates
            } else {
                compactCandidates
            }
        }
        .padding(model.isExpanded ? 7 : 5)
        .frame(
            width: model.isExpanded ? 620 : CandidatePanelLayout.compactWidth,
            height: model.panelHeight
        )
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [.white.opacity(0.28), .white.opacity(0.04), Color.accentColor.opacity(0.035)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.58), .primary.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
        .overlay(alignment: .bottomTrailing) {
            Button(action: onToggleExpanded) {
                Image(systemName: model.isExpanded ? "arrow.left" : "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(7)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(10)
            .accessibilityLabel(model.isExpanded ? "收起候选" : "展开候选")
        }
        .scaleEffect(reduceMotion ? 1 : (model.isPresented ? 1 : 0.985))
        .offset(y: reduceMotion ? 0 : (model.isPresented ? 0 : 4))
        .opacity(model.isPresented ? 1 : 0)
        .shadow(color: .black.opacity(0.12), radius: 16, y: 7)
        .animation(.easeOut(duration: 0.19), value: model.isPresented)
    }

    private var compactCandidates: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.candidates.enumerated()), id: \.element.id) { index, candidate in
                candidateRow(candidate, index: index)

                if index < model.candidates.count - 1 {
                    Divider()
                        .opacity(0.5)
                        .padding(.leading, 50)
                }
            }
        }
    }

    private var expandedCandidates: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(model.query)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("\(model.pageIndex + 1)/\(model.pageCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.38))
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(Array(model.candidates.enumerated()), id: \.element.id) { index, candidate in
                    candidateCard(candidate, index: index)
                }
            }

            HStack {
                Text("− 上一行   = 下一行")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 4)
            .frame(height: 18)
        }
    }

    private func candidateRow(_ candidate: Candidate, index: Int) -> some View {
        Button {
            guard model.translationInteractionCandidateID != candidate.id else { return }
            onSelect(candidate.id)
        } label: {
            HStack(spacing: 12) {
                numberBadge(index, isSelected: index == model.selectedIndex)

                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(candidate.sourceText)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(index == model.selectedIndex ? Color.white : .primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(2)

                        usedCount(candidate, isSelected: index == model.selectedIndex)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    TranslationHoverText(
                        text: candidate.translation,
                        isSelected: index == model.selectedIndex,
                        isSpeaking: model.speakingCandidateID == candidate.id,
                        onHoverChanged: { inside in
                            if inside {
                                model.translationInteractionCandidateID = candidate.id
                            } else if model.translationInteractionCandidateID == candidate.id {
                                model.translationInteractionCandidateID = nil
                            }
                            onTranslationHover(candidate, inside)
                        },
                        onDoubleClick: { onTranslationDoubleClick(candidate) }
                    )
                    .frame(width: 120, alignment: .trailing)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
            .background(selectionBackground(index == model.selectedIndex))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(candidate, index: index))
    }

    private func candidateCard(_ candidate: Candidate, index: Int) -> some View {
        let isSelected = index == model.selectedIndex
        let isInSelectedRow = index / 3 == model.selectedIndex / 3
        return Button {
            onSelect(candidate.id)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                numberBadge(index, isSelected: isSelected)
                    .opacity(isInSelectedRow ? 1 : 0)
                    .accessibilityHidden(!isInSelectedRow)
                candidateText(candidate, isSelected: isSelected)
                Spacer(minLength: 0)
            }
            .padding(7)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor
                            : Color(nsColor: .controlBackgroundColor).opacity(0.34)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.18 : 0.12), lineWidth: 0.6)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(candidate, index: index))
    }

    private func numberBadge(_ index: Int, isSelected: Bool) -> some View {
        Text("\(model.isExpanded ? index % 3 + 1 : index + 1)")
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(isSelected ? Color.white.opacity(0.86) : Color.secondary.opacity(0.72))
            .frame(width: 22, height: 22)
            .background(
                isSelected
                    ? Color.white.opacity(0.16)
                    : Color.primary.opacity(0.07),
                in: Circle()
            )
    }

    private func candidateText(_ candidate: Candidate, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(candidate.sourceText)
                .font(.system(size: model.isExpanded ? 16 : 17, weight: .bold))
                .foregroundStyle(isSelected ? Color.white : .primary)
                .lineLimit(1)

            HStack(spacing: 4) {
                Text(candidate.translation.isEmpty ? "Translation unavailable" : candidate.translation)
                    .font(.system(
                        size: model.isExpanded ? 10.5 : 11,
                        weight: model.speakingCandidateID == candidate.id ? .bold : .medium
                    ))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : .secondary)
                    .lineLimit(1)

                if model.speakingCandidateID == candidate.id {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.accentColor)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                guard !candidate.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                onTranslationDoubleClick(candidate)
            }
            .onHover { inside in
                guard !candidate.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                onTranslationHover(candidate, inside)
            }
        }
    }

    private func usedCount(_ candidate: Candidate, isSelected: Bool) -> some View {
        Text("Used \(model.counts[candidate.id, default: 0])×")
            .font(.caption2.monospacedDigit().weight(.medium))
            .foregroundStyle(isSelected ? Color.white.opacity(0.6) : Color.secondary.opacity(0.48))
    }

    private func selectionBackground(_ isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isSelected ? Color.accentColor : Color.clear)
    }

    private func accessibilityLabel(_ candidate: Candidate, index: Int) -> String {
        let number = model.isExpanded ? index % 3 + 1 : index + 1
        return "候选 \(number)，\(candidate.sourceText)，\(candidate.translation.isEmpty ? "暂无翻译" : candidate.translation)，使用 \(model.counts[candidate.id, default: 0]) 次"
    }
}

private struct TranslationHoverText: View {
    let text: String
    let isSelected: Bool
    let isSpeaking: Bool
    let onHoverChanged: (Bool) -> Void
    let onDoubleClick: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            Text(text.isEmpty ? "Translation unavailable" : text)
                .font(.system(size: 13, weight: isSpeaking || isHovered ? .bold : .semibold))
                .foregroundStyle(translationColor)
                .lineLimit(3)
                .truncationMode(.tail)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)

            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.accentColor)
                .frame(width: 14)
                .opacity(isSpeaking ? 1 : 0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background {
            Capsule().fill(Color.white.opacity(isHovered || isSpeaking ? (isSelected ? 0.14 : 0.36) : 0))
        }
        .scaleEffect(reduceMotion ? 1 : (isHovered ? 1.008 : 1), anchor: .leading)
        .shadow(color: .black.opacity(isHovered ? 0.07 : 0), radius: 4, y: 2)
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, alignment: .trailing)
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .animation(.easeOut(duration: 0.15), value: isSpeaking)
        .onTapGesture(count: 2) {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            onDoubleClick()
        }
        .onHover { inside in
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            isHovered = inside
            onHoverChanged(inside)
        }
    }

    private var translationColor: Color {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return isSelected ? .white.opacity(0.58) : .secondary.opacity(0.62)
        }
        if isSelected { return .white.opacity(isSpeaking ? 1 : 0.92) }
        if isSpeaking { return .accentColor }
        return isHovered ? .primary : .primary.opacity(0.82)
    }
}
