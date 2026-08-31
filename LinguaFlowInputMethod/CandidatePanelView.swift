import LinguaFlowCore
import SwiftUI

@MainActor
final class CandidatePanelModel: ObservableObject {
    @Published var candidates: [Candidate] = []
    @Published var selectedIndex = 0
    @Published var counts: [String: Int] = [:]
}

struct CandidatePanelView: View {
    @ObservedObject var model: CandidatePanelModel
    let onSelect: (Int) -> Void

    var body: some View {
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
        .padding(6)
        .frame(width: 430, height: 258)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.13), lineWidth: 1)
        }
        .padding(1)
    }

    private func candidateRow(_ candidate: Candidate, index: Int) -> some View {
        Button {
            onSelect(index)
        } label: {
            HStack(spacing: 12) {
                Text("\(index + 1)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(index == model.selectedIndex ? Color.white.opacity(0.82) : Color.secondary.opacity(0.65))
                    .frame(width: 24, height: 24)
                    .background(
                        index == model.selectedIndex
                            ? Color.white.opacity(0.16)
                            : Color.primary.opacity(0.055),
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.sourceText)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(index == model.selectedIndex ? Color.white : .primary)

                    Text(candidate.translation.isEmpty ? "Translation unavailable" : candidate.translation)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(index == model.selectedIndex ? Color.white.opacity(0.78) : .secondary)
                }

                Spacer(minLength: 12)

                Text("Seen \(model.counts[candidate.id, default: 0])×")
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(index == model.selectedIndex ? Color.white.opacity(0.58) : Color.secondary.opacity(0.45))
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(index == model.selectedIndex ? Color.accentColor : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "候选 \(index + 1)，\(candidate.sourceText)，\(candidate.translation.isEmpty ? "暂无翻译" : candidate.translation)，Seen \(model.counts[candidate.id, default: 0]) 次"
        )
    }
}
