import SwiftUI

struct ContentView: View {
    let exposureStore: ExposureStore

    @State private var query = ""
    @State private var isShowingResetConfirmation = false

    private var normalizedQuery: String {
        CandidateCatalog.normalizedInput(query)
    }

    private var candidates: [Candidate] {
        CandidateCatalog.candidates(for: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            InputSection(query: $query)

            Group {
                if normalizedQuery.isEmpty {
                    CandidateStateView(
                        symbol: "keyboard",
                        title: "开始输入拼音",
                        message: "翻译会显示在模拟候选词旁，但不会写入输入框。"
                    )
                } else if candidates.isEmpty {
                    CandidateStateView(
                        symbol: "questionmark.circle",
                        title: "暂未收录，请尝试支持的五个拼音",
                        message: "请尝试 huiyi、anpai、yanqi、shenqing 或 fangfa。"
                    )
                } else {
                    CandidateListView(candidates: candidates, exposureStore: exposureStore)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .padding(32)
        .confirmationDialog(
            "确定要清空全部学习记录吗？",
            isPresented: $isShowingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空学习记录", role: .destructive) {
                exposureStore.reset()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所有 Seen count 都会归零，这个操作无法撤销。")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LinguaFlow")
                .font(.system(size: 34, weight: .bold, design: .rounded))

            Text("Type naturally. Learn effortlessly.")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)

            Text("输入拼音，在候选词旁顺便看到英文。")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Label("仅在本机运行 · 不使用网络或 AI", systemImage: "lock.shield")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()

            Button("清空学习记录", role: .destructive) {
                isShowingResetConfirmation = true
            }
            .disabled(!exposureStore.hasExposures)
        }
    }
}
