import SwiftUI

struct InputSection: View {
    @Binding var query: String
    let submittedCandidate: Candidate?
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("输入拼音")
                .font(.headline)

            TextField("例如：huiyi", text: $query)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .onSubmit(onSubmit)
                .accessibilityIdentifier("pinyinInput")
                .accessibilityHint("按回车输出第一候选，并增加 Seen count")

            Text("huiyi · anpai · yanqi · shenqing · fangfa")
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Label("按 Return 输出第一候选，并计入 Seen", systemImage: "return")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let submittedCandidate {
                    Spacer()

                    Text("已输出：\(submittedCandidate.sourceText)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tint)
                        .accessibilityLabel("已输出 \(submittedCandidate.sourceText)")
                }
            }
        }
    }
}
