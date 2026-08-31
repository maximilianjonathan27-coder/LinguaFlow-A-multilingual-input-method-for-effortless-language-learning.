import SwiftUI

struct CandidateRowView: View {
    let index: Int
    let candidate: Candidate
    let seenCount: Int
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onSelect) {
                HStack(spacing: 10) {
                    Text("\(index)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 18, alignment: .trailing)

                    Text(candidate.sourceText)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 190, alignment: .leading)
            .accessibilityLabel("候选词 \(candidate.sourceText)")
            .accessibilityHint("点击后增加 Seen count")

            Text(candidate.translation)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(seenCount)×")
                .font(.body.monospacedDigit().weight(.medium))
                .foregroundStyle(seenCount > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .frame(width: 74, alignment: .trailing)
                .accessibilityLabel("Seen \(seenCount) times")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .contentShape(Rectangle())
    }
}
