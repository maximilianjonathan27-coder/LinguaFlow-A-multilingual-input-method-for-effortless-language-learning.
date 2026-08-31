import SwiftUI

struct CandidateListView: View {
    let candidates: [Candidate]
    let exposureStore: ExposureStore

    var body: some View {
        VStack(spacing: 0) {
            headerRow

            Divider()

            ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                CandidateRowView(
                    index: index + 1,
                    candidate: candidate,
                    seenCount: exposureStore.count(for: candidate),
                    onSelect: { exposureStore.increment(candidate) }
                )

                if index < candidates.count - 1 {
                    Divider()
                        .padding(.leading, 18)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.separator.opacity(0.7), lineWidth: 1)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 16) {
            Text("候选词")
                .frame(width: 190, alignment: .leading)

            Text("Translation")
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Seen")
                .frame(width: 74, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}
