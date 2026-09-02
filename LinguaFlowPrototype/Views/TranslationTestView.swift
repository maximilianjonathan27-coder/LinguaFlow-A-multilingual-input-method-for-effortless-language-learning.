import SwiftUI

#if canImport(Translation)
// TranslationSession's Swift 6 concurrency annotations are currently
// incomplete in the macOS SDK. Apple recommends importing the framework with
// pre-concurrency compatibility until those annotations are audited.
@preconcurrency import Translation
#endif

struct TranslationTestContainerView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if #available(macOS 15.0, *) {
                    AppleTranslationTestView()
                } else {
                    ContentUnavailableView(
                        "系统版本不支持",
                        systemImage: "translate",
                        description: Text("Apple 本地翻译实验需要 macOS 15 或更高版本。")
                    )
                }
            }
            .navigationTitle("本地句子翻译实验")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .frame(minWidth: 680, minHeight: 570)
    }
}

#if canImport(Translation)
@available(macOS 15.0, *)
private struct AppleTranslationTestView: View {
    private static let samples = [
        "我在想这个问题应该怎么解决。",
        "我想喝水，但是这里没有水喝。",
        "没有什么问题，你可以继续。",
        "这个地方需要改一下。",
        "云手机用户越来越多了。",
    ]

    @State private var sourceText = samples[0]
    @State private var pendingSourceText = ""
    @State private var translatedText = ""
    @State private var elapsedMilliseconds: Double?
    @State private var errorMessage: String?
    @State private var isTranslating = false
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                intro
                samplePicker
                sourceEditor
                translateAction
                resultCard
                privacyNote
            }
            .padding(28)
        }
        .translationTask(configuration) { session in
            Task { @MainActor in
                let text = pendingSourceText
                guard !text.isEmpty else {
                    isTranslating = false
                    return
                }

                let clock = ContinuousClock()
                let start = clock.now
                do {
                    try await session.prepareTranslation()
                    let response = try await session.translate(text)
                    guard text == pendingSourceText else { return }

                    translatedText = response.targetText
                    elapsedMilliseconds = milliseconds(from: start.duration(to: clock.now))
                    errorMessage = nil
                } catch is CancellationError {
                    return
                } catch {
                    guard text == pendingSourceText else { return }
                    translatedText = ""
                    elapsedMilliseconds = milliseconds(from: start.duration(to: clock.now))
                    errorMessage = readableMessage(for: error)
                }
                isTranslating = false
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("先验证真实效果，再接入输入法")
                .font(.title2.weight(.semibold))
            Text("第一次使用时，macOS 可能会询问是否下载中英文语言包。下载完成后，翻译会在本机进行。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var samplePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("测试句子")
                .font(.headline)

            Picker("测试句子", selection: $sourceText) {
                ForEach(Self.samples, id: \.self) { sample in
                    Text(sample).tag(sample)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sourceEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("中文原文")
                .font(.headline)
            TextEditor(text: $sourceText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 90)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                }
        }
    }

    private var translateAction: some View {
        HStack(spacing: 12) {
            Button(isTranslating ? "正在翻译…" : "开始本地翻译") {
                requestTranslation()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isTranslating || sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if isTranslating {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            if let elapsedMilliseconds {
                Text(String(format: "耗时 %.0f 毫秒", elapsedMilliseconds))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("英文结果")
                .font(.headline)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if translatedText.isEmpty {
                Text("翻译结果会显示在这里。")
                    .foregroundStyle(.tertiary)
            } else {
                Text(translatedText)
                    .font(.title3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        }
    }

    private var privacyNote: some View {
        Label(
            "翻译内容由 Apple 模型在设备端处理；LinguaFlow 不会保存这次测试的原文或译文。",
            systemImage: "lock.shield"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private func requestTranslation() {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        pendingSourceText = text
        translatedText = ""
        elapsedMilliseconds = nil
        errorMessage = nil
        isTranslating = true

        if configuration == nil {
            configuration = TranslationSession.Configuration(
                source: Locale.Language(identifier: "zh-Hans"),
                target: Locale.Language(identifier: "en")
            )
        } else {
            configuration?.invalidate()
        }
    }

    private func milliseconds(from duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    private func readableMessage(for error: any Error) -> String {
        let description = error.localizedDescription
        if description.isEmpty {
            return "暂时无法使用本地翻译，请确认中英文语言包已经安装。"
        }
        return "本地翻译未完成：\(description)"
    }
}
#endif
