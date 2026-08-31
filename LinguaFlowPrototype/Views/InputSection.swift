import SwiftUI

struct InputSection: View {
    @Binding var query: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("输入拼音")
                .font(.headline)

            TextField("例如：huiyi", text: $query)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .accessibilityIdentifier("pinyinInput")

            Text("huiyi · anpai · yanqi · shenqing · fangfa")
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
        }
    }
}
