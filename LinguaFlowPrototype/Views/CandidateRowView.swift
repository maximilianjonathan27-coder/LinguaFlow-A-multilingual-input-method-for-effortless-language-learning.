import SwiftUI

struct CandidateRowView: View {
    let index: Int
    let candidate: Candidate
    let seenCount: Int
    let onSelect: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text("\(index)")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 26, height: 26)
                .background(Color.primary.opacity(0.055), in: Circle())

            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(candidate.sourceText)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)

                    Text(candidate.translation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($isFocused)
            .accessibilityLabel("候选词 \(candidate.sourceText)，英文 \(candidate.translation)")
            .accessibilityHint("点击后增加 Seen count")

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(seenCount)×")
                    .font(.caption.monospacedDigit().weight(.medium))

                Text("Seen")
                    .font(.caption2)
            }
            .foregroundStyle(.tertiary)
            .frame(width: 52, alignment: .trailing)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Seen \(seenCount) times")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isFocused ? Color.accentColor.opacity(0.10) : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isFocused ? Color.accentColor.opacity(0.72) : Color.clear,
                    lineWidth: 1.5
                )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }
}
