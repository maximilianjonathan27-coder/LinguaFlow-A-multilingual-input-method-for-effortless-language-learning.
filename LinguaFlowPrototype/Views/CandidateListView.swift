import SwiftUI

struct CandidateListView: View {
    let candidates: [Candidate]
    let exposureStore: ExposureStore

    var body: some View {
        VStack(spacing: 0) {
            headerRow

            ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                CandidateRowView(
                    index: index + 1,
                    candidate: candidate,
                    seenCount: exposureStore.count(for: candidate),
                    onSelect: { exposureStore.increment(candidate) }
                )

                if index < candidates.count - 1 {
                    Divider()
                        .opacity(0.55)
                        .padding(.leading, 60)
                        .padding(.trailing, 20)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        }
    }

    private var headerRow: some View {
        HStack {
            Text("候选词")
                .font(.caption.weight(.semibold))

            Spacer()

            Text("Seen")
                .font(.caption2.weight(.medium))
                .textCase(.uppercase)
                .tracking(0.7)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.035))
    }
}
