import LinguaFlowCore
import SwiftUI

struct ContentView: View {
    let exposureStore: ExposureStore

    @Environment(\.scenePhase) private var scenePhase
    @State private var installer = InputMethodInstaller()
    @State private var isShowingResetConfirmation = false
    @State private var isShowingTranslationTest = false

    private var totalSeenCount: Int {
        exposureStore.counts.values.reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            installationCard
            learningCard
            translationTestCard
            privacyNote
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            installer.refreshStatus()
            exposureStore.refresh()
        }
        .confirmationDialog(
            "确定要清空全部学习记录吗？",
            isPresented: $isShowingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空学习记录", role: .destructive) {
                _ = exposureStore.reset()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所有候选词的 Seen count 都会归零，这个操作无法撤销。")
        }
        .sheet(isPresented: $isShowingTranslationTest) {
            TranslationTestContainerView()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LinguaFlow")
                .font(.system(size: 34, weight: .bold, design: .rounded))

            Text("Type naturally. Learn effortlessly.")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)

            Text("安装 LinguaFlow 输入法，让双语候选跟随你在任何 App 中的光标。")
                .foregroundStyle(.secondary)
        }
    }

    private var installationCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: statusSymbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 5) {
                    Text(statusTitle)
                        .font(.title3.weight(.semibold))
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 12) {
                Button(installButtonTitle) {
                    installer.installOrUpdate()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(installer.status == .installing || installer.status == .embeddedInputMethodMissing)

                Button(installer.isInputMethodEnabled ? "已经启用" : "启用 LinguaFlow") {
                    installer.enableInputMethod()
                }
                .controlSize(.large)
                .disabled(
                    installer.isInputMethodEnabled
                        || installer.status != .installed
                )

                Button("打开键盘设置") {
                    installer.openKeyboardSettings()
                }
                .controlSize(.large)

                Spacer()

                Text("当前用户安装")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("启用步骤")
                    .font(.headline)
                Text("先点击“启用 LinguaFlow”，然后从菜单栏输入法图标切换到 LinguaFlow。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if let enableErrorMessage = installer.enableErrorMessage {
                    Text(enableErrorMessage)
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        }
    }

    private var learningCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text("本机学习记录")
                    .font(.headline)
                Text("累计 Seen \(totalSeenCount) 次 · 只记录候选 ID 和次数")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("清空学习记录", role: .destructive) {
                isShowingResetConfirmation = true
            }
            .disabled(!exposureStore.hasExposures)
        }
        .padding(18)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }

    private var translationTestCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "translate")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text("本地句子翻译实验")
                    .font(.headline)
                Text("使用 Apple 设备端模型比较翻译质量和响应时间")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("打开测试") {
                isShowingTranslationTest = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }

    private var privacyNote: some View {
        Label(
            "输入法完全离线 · 翻译实验在设备端运行 · 不保存输入历史 · 不申请输入监控权限",
            systemImage: "lock.shield"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private var statusTitle: String {
        switch installer.status {
        case .notInstalled: "输入法尚未安装"
        case .installed: "输入法已安装"
        case .updateAvailable: "发现可安装的更新"
        case .embeddedInputMethodMissing: "安装组件缺失"
        case .installing: "正在安装…"
        case .failed: "安装未完成"
        }
    }

    private var statusMessage: String {
        switch installer.status {
        case .notInstalled:
            "点击安装后，再到系统键盘设置中手动添加 LinguaFlow。"
        case .installed:
            installer.isInputMethodEnabled
                ? "LinguaFlow 已安装并启用，可以从菜单栏输入法图标切换使用。"
                : "LinguaFlow 已安装。点击“启用 LinguaFlow”完成系统集成测试；不会自动替换当前输入法。"
        case .updateAvailable:
            "点击更新会替换当前用户目录中的旧版本，不需要管理员密码。"
        case .embeddedInputMethodMissing:
            "当前 App 没有包含 LinguaFlow 输入法，请通过工程脚本重新构建。"
        case .installing:
            "正在复制并向 macOS 注册输入源。"
        case let .failed(message):
            message
        }
    }

    private var statusSymbol: String {
        switch installer.status {
        case .installed: "checkmark.circle.fill"
        case .installing: "arrow.triangle.2.circlepath"
        case .failed, .embeddedInputMethodMissing: "exclamationmark.triangle.fill"
        case .notInstalled, .updateAvailable: "keyboard.badge.ellipsis"
        }
    }

    private var statusColor: Color {
        switch installer.status {
        case .installed: .green
        case .failed, .embeddedInputMethodMissing: .orange
        default: .accentColor
        }
    }

    private var installButtonTitle: String {
        switch installer.status {
        case .installed: "重新安装"
        case .updateAvailable: "更新输入法"
        case .installing: "正在安装…"
        default: "安装输入法"
        }
    }
}
