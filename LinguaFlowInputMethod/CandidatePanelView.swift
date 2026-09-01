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
}

struct CandidatePanelView: View {
    @ObservedObject var model: CandidatePanelModel
    let onSelect: (String) -> Void
    let onToggleExpanded: () -> Void

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
            width: model.isExpanded ? 620 : 360,
            height: model.isExpanded ? 480 : 218
        )
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.14))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
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
    }

    private var compactCandidates: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.candidates.enumerated()), id: \.element.id) { index, candidate in
                candidateRow(candidate, index: index)

                if index < model.candidates.count - 1 {
                    Divider()
                        .opacity(0.42)
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

            vocabularyCard

            HStack {
                Text("− 上一行   = 下一行")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Image(systemName: "arrow.left")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .frame(height: 18)
        }
    }

    private var vocabularyCard: some View {
        let candidate = model.candidates[safe: model.selectedIndex]
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("Vocabulary Card", systemImage: "text.book.closed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let candidate {
                    Text(candidate.sourceText)
                        .font(.caption.weight(.bold))
                }
            }
            if let candidate, !candidate.examples.isEmpty {
                ForEach(candidate.examples.prefix(2)) { example in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(example.chinese)
                            .font(.caption)
                            .lineLimit(1)
                        Text(example.english)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                Text("暂无离线例句")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.34))
        }
    }

    private func candidateRow(_ candidate: Candidate, index: Int) -> some View {
        Button {
            onSelect(candidate.id)
        } label: {
            HStack(spacing: 12) {
                numberBadge(index, isSelected: index == model.selectedIndex)
                candidateText(candidate, isSelected: index == model.selectedIndex)
                Spacer(minLength: 12)
                seenCount(candidate, isSelected: index == model.selectedIndex)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 40)
            .contentShape(Rectangle())
            .background(selectionBackground(index == model.selectedIndex))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(candidate, index: index))
    }

    private func candidateCard(_ candidate: Candidate, index: Int) -> some View {
        let isSelected = index == model.selectedIndex
        return Button {
            onSelect(candidate.id)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                numberBadge(index, isSelected: isSelected)
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

            Text(candidate.translation.isEmpty ? "Translation unavailable" : candidate.translation)
                .font(.system(size: model.isExpanded ? 10.5 : 11, weight: .medium))
                .foregroundStyle(isSelected ? Color.white.opacity(0.8) : .secondary)
                .lineLimit(1)
        }
    }

    private func seenCount(_ candidate: Candidate, isSelected: Bool) -> some View {
        Text("Seen \(model.counts[candidate.id, default: 0])×")
            .font(.caption2.monospacedDigit().weight(.medium))
            .foregroundStyle(isSelected ? Color.white.opacity(0.6) : Color.secondary.opacity(0.48))
    }

    private func selectionBackground(_ isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isSelected ? Color.accentColor : Color.clear)
    }

    private func accessibilityLabel(_ candidate: Candidate, index: Int) -> String {
        let number = model.isExpanded ? index % 3 + 1 : index + 1
        return "候选 \(number)，\(candidate.sourceText)，\(candidate.translation.isEmpty ? "暂无翻译" : candidate.translation)，Seen \(model.counts[candidate.id, default: 0]) 次"
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
