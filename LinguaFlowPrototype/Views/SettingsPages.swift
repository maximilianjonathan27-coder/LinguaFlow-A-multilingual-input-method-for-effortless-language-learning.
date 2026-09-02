import AppKit
import LinguaFlowCore
import SwiftUI

struct OverviewPage: View {
    @ObservedObject var settings: LinguaFlowSettings
    @State private var systemStatus = LinguaFlowSystemStatus(isInstalled: false, isSelected: false)

    var body: some View {
        SettingsPageScrollView {
            SettingsPageHeader(
                title: "概览",
                subtitle: "输入、翻译与学习，在同一个安静的工作流中自然发生。"
            )
            .quietAppear(order: 0)

            statusSurface
                .quietAppear(order: 1)

            HStack(alignment: .top, spacing: 14) {
                summaryCard(
                    symbol: "character.cursor.ibeam",
                    title: "语言环境",
                    value: settings.languageDirection.title,
                    tint: .cyan
                )
                summaryCard(
                    symbol: "scope",
                    title: "学习偏好",
                    value: "\(settings.translationStyle.title) · \(settings.learningDomain.title)",
                    tint: .blue
                )
            }
            .quietAppear(order: 2)

            VStack(alignment: .leading, spacing: 10) {
                Text("候选词体验")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                CandidatePreview(settings: settings, compact: true)
            }
            .quietAppear(order: 3)
        }
        .onAppear { systemStatus = .current() }
    }

    private var statusSurface: some View {
        PremiumGlassSurface(
            cornerRadius: 22,
            ambient: systemStatus.isInstalled && settings.quietFlowEnabled,
            interactive: true,
            pointerLight: settings.pointerLightEnabled,
            ambientIntensity: settings.ambientIntensity
        ) {
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.13))
                        .frame(width: 54, height: 54)
                    Image(systemName: systemStatus.isSelected ? "waveform.path.ecg" : "keyboard.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(statusColor)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(statusTitle)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                    Text(statusDetail)
                        .font(.system(size: 13.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("键盘设置") {
                    guard let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") else { return }
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(23)
        }
    }

    private var statusTitle: String {
        if systemStatus.isSelected { return "LinguaFlow 正在使用" }
        if systemStatus.isInstalled { return "LinguaFlow 已就绪" }
        return "LinguaFlow 尚未安装"
    }

    private var statusDetail: String {
        if systemStatus.isSelected { return "输入法已激活，Quiet Flow 会随输入自然响应。" }
        if systemStatus.isInstalled { return "从菜单栏输入法菜单切换到 LinguaFlow 即可开始。" }
        return "请先安装输入法服务，再回到这里进行个性化设置。"
    }

    private var statusColor: Color {
        systemStatus.isInstalled ? .green : .orange
    }

    private func summaryCard(symbol: String, title: String, value: String, tint: Color) -> some View {
        PremiumGlassSurface(cornerRadius: 16, interactive: true) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 35, height: 35)
                    .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.system(size: 14.5, weight: .semibold))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(17)
        }
        .frame(maxWidth: .infinity)
    }
}

struct CandidateSettingsPage: View {
    @ObservedObject var settings: LinguaFlowSettings

    var body: some View {
        SettingsPageScrollView {
            SettingsPageHeader(
                title: "候选词",
                subtitle: "调整候选面板的阅读密度与信息布局，变化会立即出现在预览中。"
            )
            .quietAppear(order: 0)

            CandidatePreview(settings: settings)
                .quietAppear(order: 1)

            SettingsGroup(title: "布局") {
                SettingsRow(title: "候选词大小", detail: "只改变文字与行距，不改变信息层级。") {
                    HStack(spacing: 10) {
                        Image(systemName: "textformat.size.smaller").foregroundStyle(.secondary)
                        Slider(value: $settings.candidateScale, in: 0.88...1.18)
                            .frame(width: 150)
                        Image(systemName: "textformat.size.larger").foregroundStyle(.secondary)
                    }
                }
                HairlineDivider()
                SettingsRow(title: "候选词数量") {
                    Picker("候选词数量", selection: $settings.candidateCount) {
                        Text("3").tag(3)
                        Text("5").tag(5)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }
                HairlineDivider()
                SettingsRow(title: "英文释义位置", detail: "右侧并排更利于从左到右连续阅读。") {
                    Picker("英文释义位置", selection: $settings.translationPosition) {
                        ForEach(TranslationPosition.allCases) { position in
                            Text(position.title).tag(position)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
            }
            .quietAppear(order: 2)

            SettingsGroup(title: "交互") {
                SettingsRow(title: "光学悬停", detail: "仅让译文获得轻微视觉聚焦，候选行保持稳定。") {
                    Toggle("光学悬停", isOn: $settings.magnifyingHoverEnabled)
                }
                HairlineDivider()
                SettingsRow(title: "显示 Seen 次数", detail: "次数显示在中文候选词下方。") {
                    Toggle("显示 Seen 次数", isOn: $settings.exposureCountEnabled)
                }
            }
            .quietAppear(order: 3)
        }
    }
}

struct TranslationSettingsPage: View {
    @ObservedObject var settings: LinguaFlowSettings

    var body: some View {
        SettingsPageScrollView {
            SettingsPageHeader(
                title: "翻译",
                subtitle: "决定 LinguaFlow 在输入过程中为你呈现怎样的语言环境。"
            )
            .quietAppear(order: 0)

            SettingsGroup(title: "语言") {
                SettingsRow(title: "显示候选词翻译") {
                    Toggle("显示候选词翻译", isOn: $settings.translationEnabled)
                }
                HairlineDivider()
                SettingsRow(title: "翻译方向", detail: "设置会立即同步给 LinguaFlow 输入法；当前仅提供这两种稳定方向。") {
                    Picker("翻译方向", selection: $settings.languageDirection) {
                        ForEach(LanguageDirection.allCases) { direction in
                            Text(direction.title).tag(direction)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 290)
                }
            }
            .quietAppear(order: 1)

#if canImport(Translation)
            if #available(macOS 26.0, *) {
                AppleTranslationPreparationView()
                    .quietAppear(order: 2)
            } else {
                Label(
                    "Apple 本地句子翻译需要 macOS 26 或更高版本。候选词典翻译仍可正常使用。",
                    systemImage: "info.circle"
                )
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
                .quietAppear(order: 2)
            }
#endif

            SettingsGroup(title: "表达方式") {
                SettingsRow(title: "翻译风格", detail: "影响预览中的措辞密度与学习提示。") {
                    Picker("翻译风格", selection: $settings.translationStyle) {
                        ForEach(TranslationStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 235)
                }
                HairlineDivider()
                SettingsRow(title: "常用领域") {
                    Picker("常用领域", selection: $settings.learningDomain) {
                        ForEach(LearningDomain.allCases) { domain in
                            Text(domain.title).tag(domain)
                        }
                    }
                    .frame(width: 170)
                }
            }
            .quietAppear(order: 3)

            VStack(alignment: .leading, spacing: 10) {
                Text("语言变化预览")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                CandidatePreview(settings: settings, compact: true)
            }
            .quietAppear(order: 4)
        }
    }
}

struct LearningSettingsPage: View {
    @ObservedObject var settings: LinguaFlowSettings

    var body: some View {
        SettingsPageScrollView {
            SettingsPageHeader(
                title: "学习",
                subtitle: "让词汇难度与提示方式贴近你的阶段，不打断正常输入。"
            )
            .quietAppear(order: 0)

            PremiumGlassSurface(cornerRadius: 20, ambient: settings.quietFlowEnabled) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label("当前学习节奏", systemImage: "brain.head.profile.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                        Spacer()
                        Text(settings.learningLevel.title)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.10), in: Capsule())
                    }
                    Text(settings.learningLevel.detail)
                        .font(.system(size: 16, weight: .medium))
                        .contentTransition(.opacity)
                        .animation(.easeOut(duration: 0.2), value: settings.learningLevel)
                }
                .padding(21)
            }
            .quietAppear(order: 1)

            SettingsGroup(title: "学习级别") {
                SettingsRow(title: "词汇难度") {
                    Picker("词汇难度", selection: $settings.learningLevel) {
                        ForEach(LearningLevel.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 235)
                }
                HairlineDivider()
                SettingsRow(title: "语境提示", detail: "在有帮助时补充简短的用法说明。") {
                    Toggle("语境提示", isOn: $settings.contextHintsEnabled)
                }
                HairlineDivider()
                SettingsRow(title: "本机接触次数", detail: "只保存候选词标识与次数，不保存输入内容。") {
                    Toggle("本机接触次数", isOn: $settings.exposureCountEnabled)
                }
            }
            .quietAppear(order: 2)

            privacySurface
                .quietAppear(order: 3)
        }
    }

    private var privacySurface: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.green)
                .font(.system(size: 17))
            VStack(alignment: .leading, spacing: 2) {
                Text("学习记录保留在本机")
                    .font(.system(size: 13.5, weight: .semibold))
                Text("不保存完整输入历史，也不会上传学习行为。")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.green.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct VocabularySettingsPage: View {
    @ObservedObject var settings: LinguaFlowSettings

    var body: some View {
        SettingsPageScrollView {
            SettingsPageHeader(
                title: "词汇卡片",
                subtitle: "控制深入阅读时出现的内容；悬停下方预览中的英文即可体验。"
            )
            .quietAppear(order: 0)

            CandidatePreview(settings: settings)
                .quietAppear(order: 1)

            SettingsGroup(title: "触发") {
                SettingsRow(title: "启用词汇卡片") {
                    Toggle("启用词汇卡片", isOn: $settings.vocabularyCardEnabled)
                }
                HairlineDivider()
                SettingsRow(title: "悬停等待时间", detail: "避免鼠标经过时意外打开卡片。") {
                    HStack(spacing: 11) {
                        Slider(value: $settings.hoverDelay, in: 0.25...1.2, step: 0.05)
                            .frame(width: 150)
                        Text("\(settings.hoverDelay, specifier: "%.2f") 秒")
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .trailing)
                    }
                }
                HairlineDivider()
                SettingsRow(title: "双击播放发音") {
                    Toggle("双击播放发音", isOn: $settings.pronunciationEnabled)
                }
            }
            .quietAppear(order: 2)

            SettingsGroup(title: "卡片内容") {
                featureToggle("中文释义", binding: $settings.chineseDefinitionEnabled)
                HairlineDivider()
                featureToggle("英文释义", binding: $settings.englishDefinitionEnabled)
                HairlineDivider()
                featureToggle("例句", binding: $settings.examplesEnabled)
                HairlineDivider()
                featureToggle("相关短语与 Idioms", binding: $settings.phrasesEnabled)
            }
            .quietAppear(order: 3)
        }
    }

    private func featureToggle(_ title: String, binding: Binding<Bool>) -> some View {
        SettingsRow(title: title) {
            Toggle(title, isOn: binding)
        }
    }
}

struct MotionSettingsPage: View {
    @ObservedObject var settings: LinguaFlowSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SettingsPageScrollView {
            SettingsPageHeader(
                title: "动效与外观",
                subtitle: "Quiet Flow 只让材质轻微呼吸，文字与界面结构始终保持稳定。"
            )
            .quietAppear(order: 0)

            motionPreview
                .quietAppear(order: 1)

            SettingsGroup(title: "Quiet Flow") {
                SettingsRow(title: "材质呼吸", detail: "使用低幅度环境光变化表达状态与空间深度。") {
                    Toggle("材质呼吸", isOn: $settings.quietFlowEnabled)
                        .disabled(reduceMotion)
                }
                HairlineDivider()
                SettingsRow(title: "环境光强度") {
                    Slider(value: $settings.ambientIntensity, in: 0.25...1.0)
                        .frame(width: 180)
                        .disabled(!settings.quietFlowEnabled || reduceMotion)
                }
                HairlineDivider()
                SettingsRow(title: "指针感应光", detail: "只用于重要预览表面，不形成明显聚光灯。") {
                    Toggle("指针感应光", isOn: $settings.pointerLightEnabled)
                        .disabled(reduceMotion)
                }
            }
            .quietAppear(order: 2)

            SettingsGroup(title: "材质") {
                SettingsRow(title: "半透明玻璃表面", detail: "关闭后使用高对比度的不透明表面。") {
                    Toggle("半透明玻璃表面", isOn: $settings.glassEnabled)
                }
                HairlineDivider()
                SettingsRow(title: "候选词光学悬停") {
                    Toggle("候选词光学悬停", isOn: $settings.magnifyingHoverEnabled)
                        .disabled(reduceMotion)
                }
            }
            .quietAppear(order: 3)

            if reduceMotion {
                Label(
                    "系统已启用“减弱动态效果”。环境漂移和指针移动已自动停止，所有功能仍然可用。",
                    systemImage: "accessibility"
                )
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                .quietAppear(order: 4)
            }
        }
    }

    private var motionPreview: some View {
        PremiumGlassSurface(
            cornerRadius: 21,
            glassEnabled: settings.glassEnabled,
            ambient: settings.quietFlowEnabled,
            interactive: true,
            pointerLight: settings.pointerLightEnabled,
            ambientIntensity: settings.ambientIntensity
        ) {
            HStack(spacing: 18) {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.10)).frame(width: 48, height: 48)
                    Image(systemName: "waveform.path")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(settings.quietFlowEnabled && !reduceMotion ? "Quiet Flow 正在呼吸" : "Quiet Flow 已静止")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text("观察材质内部的缓慢光线变化；内容不会移动。")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(21)
        }
    }
}

struct VocabularyLibraryPage: View {
    @State private var entries: [VocabularyEntry] = []
    @State private var query = ""
    @State private var sort: VocabularySort = .recentlyViewed
    @State private var targetFilter: SupportedLanguage?
    @State private var selectedEntry: VocabularyEntry?
    @State private var isReviewing = false
    @State private var reviewIndex = 0
    @State private var showClearConfirmation = false

    private var filteredEntries: [VocabularyEntry] {
        entries.filter { entry in
            (targetFilter == nil || entry.targetLanguage == targetFilter)
                && (query.isEmpty || entry.sourceText.localizedCaseInsensitiveContains(query) || entry.translatedText.localizedCaseInsensitiveContains(query))
        }.sorted { lhs, rhs in
            switch sort {
            case .recentlyViewed: lhs.lastViewedAt > rhs.lastViewedAt
            case .mostViewed:
                lhs.viewCount == rhs.viewCount ? lhs.lastViewedAt > rhs.lastViewedAt : lhs.viewCount > rhs.viewCount
            case .alphabetical: lhs.translatedText.localizedCaseInsensitiveCompare(rhs.translatedText) == .orderedAscending
            }
        }
    }

    var body: some View {
        SettingsPageScrollView {
            SettingsPageHeader(title: "词汇库", subtitle: "你在输入时主动打开词汇卡片探索过的词，都会安静地保留在本机。")

            HStack(spacing: 12) {
                summary("已探索", value: "\(entries.count)", symbol: "books.vertical.fill")
                summary("今日复习", value: "\(entries.filter { Calendar.current.isDateInToday($0.lastViewedAt) }.count)", symbol: "checkmark.circle.fill")
                Spacer()
                Button("开始复习") { reviewIndex = 0; isReviewing = !filteredEntries.isEmpty }
                    .buttonStyle(.borderedProminent)
                    .disabled(filteredEntries.isEmpty)
            }

            PremiumGlassSurface(cornerRadius: 18, interactive: true) {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        TextField("搜索词汇…", text: $query)
                            .textFieldStyle(.roundedBorder)
                        Picker("排序", selection: $sort) {
                            Text("最近查看").tag(VocabularySort.recentlyViewed)
                            Text("查看最多").tag(VocabularySort.mostViewed)
                            Text("字母顺序").tag(VocabularySort.alphabetical)
                        }
                        .frame(width: 120)
                        Picker("语言", selection: $targetFilter) {
                            Text("全部").tag(SupportedLanguage?.none)
                            Text("English").tag(SupportedLanguage?.some(.english))
                            Text("简体中文").tag(SupportedLanguage?.some(.chineseSimplified))
                        }
                        .frame(width: 100)
                    }
                    .padding(15)

                    if filteredEntries.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "text.book.closed")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(Color.accentColor)
                            Text(entries.isEmpty ? "还没有词汇" : "没有匹配的词汇")
                                .font(.system(size: 16, weight: .semibold))
                            Text(entries.isEmpty ? "当你打开翻译词的词汇卡片时，它会自动出现在这里。" : "试试另一个搜索词或筛选条件。")
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 46)
                    } else {
                        Divider().opacity(0.55)
                        ForEach(filteredEntries) { entry in
                            Button { selectedEntry = entry } label: { row(entry) }
                                .buttonStyle(.plain)
                            if entry.id != filteredEntries.last?.id { Divider().opacity(0.45).padding(.leading, 20) }
                        }
                    }
                }
            }

            if !entries.isEmpty {
                HStack {
                    Spacer()
                    Button("清空词汇历史", role: .destructive) { showClearConfirmation = true }
                        .buttonStyle(.borderless)
                }
            }
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in reload() }
        .confirmationDialog("清空词汇历史？", isPresented: $showClearConfirmation, titleVisibility: .visible) {
            Button("清空", role: .destructive) { VocabularyStore.shared.clear(); reload() }
        } message: { Text("这会移除你此前查看过的所有词汇，不会影响语言方向或其他偏好。") }
        .sheet(item: $selectedEntry) { entry in VocabularyDetailView(entry: entry, onRemove: { VocabularyStore.shared.remove(id: entry.id); selectedEntry = nil; reload() }) }
        .sheet(isPresented: $isReviewing) { VocabularyReviewView(entries: filteredEntries, index: $reviewIndex) }
    }

    private func reload() { entries = VocabularyStore.shared.entries() }

    private func summary(_ title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.system(size: 18, weight: .bold, design: .rounded))
                Text(title).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func row(_ entry: VocabularyEntry) -> some View {
        HStack(spacing: 14) {
            Image(systemName: entry.targetLanguage == .english ? "character.book.closed.fill" : "text.book.closed.fill")
                .foregroundStyle(Color.accentColor).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.translatedText).font(.system(size: 16, weight: .semibold))
                Text(entry.sourceText).font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text("查看 \(entry.viewCount) 次 · \(entry.lastViewedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.system(size: 11.5)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 17).padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private struct VocabularyDetailView: View {
    let entry: VocabularyEntry
    let onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { VStack(alignment: .leading) { Text(entry.translatedText).font(.system(size: 28, weight: .bold, design: .rounded)); Text(entry.sourceText).foregroundStyle(.secondary) }; Spacer(); Button("完成") { dismiss() } }
            Divider()
            if let definition = entry.definition, !definition.isEmpty { Text("释义").font(.headline); Text(definition).foregroundStyle(.secondary).textSelection(.enabled) }
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                GridRow { Text("查看次数").foregroundStyle(.secondary); Text("\(entry.viewCount) 次") }
                GridRow { Text("首次查看").foregroundStyle(.secondary); Text(entry.firstViewedAt.formatted(date: .abbreviated, time: .shortened)) }
                GridRow { Text("最后查看").foregroundStyle(.secondary); Text(entry.lastViewedAt.formatted(date: .abbreviated, time: .shortened)) }
            }
            Spacer()
            Button("从词汇库移除", role: .destructive, action: onRemove)
        }
        .padding(28).frame(width: 440, height: 360)
    }
}

private struct VocabularyReviewView: View {
    let entries: [VocabularyEntry]
    @Binding var index: Int
    @State private var revealed = false
    @Environment(\.dismiss) private var dismiss
    private var entry: VocabularyEntry { entries[min(max(index, 0), max(0, entries.count - 1))] }
    var body: some View {
        VStack(spacing: 22) {
            HStack { Text("词汇复习").font(.headline); Spacer(); Button("完成") { dismiss() } }
            Spacer()
            Text(entry.translatedText).font(.system(size: 34, weight: .bold, design: .rounded))
            if revealed { Text(entry.sourceText).font(.system(size: 20, weight: .medium)).foregroundStyle(.secondary).transition(.opacity) }
            else { Button("显示释义") { withAnimation(.easeOut(duration: 0.2)) { revealed = true } }.buttonStyle(.borderedProminent) }
            Spacer()
            HStack { Button("上一个") { index = max(0, index - 1); revealed = false }.disabled(index == 0); Spacer(); Text("\(index + 1) / \(entries.count)").foregroundStyle(.secondary); Spacer(); Button("下一个") { index = min(entries.count - 1, index + 1); revealed = false }.disabled(index >= entries.count - 1) }
        }
        .padding(28).frame(width: 430, height: 320)
    }
}

struct MembershipSettingsPage: View {
    @ObservedObject var settings: LinguaFlowSettings

    var body: some View {
        SettingsPageScrollView {
            SettingsPageHeader(
                title: "LinguaFlow Plus",
                subtitle: "更深入的语言环境与个性化能力，保持克制，也保持专注。"
            )
            .quietAppear(order: 0)

            PremiumGlassSurface(
                cornerRadius: 24,
                ambient: settings.quietFlowEnabled,
                interactive: true,
                pointerLight: settings.pointerLightEnabled,
                ambientIntensity: min(1, settings.ambientIntensity + 0.12)
            ) {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 7) {
                            Label("LINGUAFLOW PLUS", systemImage: "sparkles")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.accentColor)
                            Text("为持续学习而设计")
                                .font(.system(size: 25, weight: .bold, design: .rounded))
                            Text("更多语境、更精细的个性化，以及跨设备延续的学习节奏。")
                                .font(.system(size: 13.5))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 28)
                        Text("即将推出")
                            .font(.system(size: 12.5, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.thinMaterial, in: Capsule())
                    }

                    Divider().opacity(0.55)

                    HStack(alignment: .top, spacing: 25) {
                        plusFeature("语境增强", detail: "更自然的例句与表达差异", symbol: "text.quote")
                        plusFeature("学习路径", detail: "随使用习惯逐步调整难度", symbol: "point.topleft.down.to.point.bottomright.curvepath")
                        plusFeature("跨设备", detail: "延续偏好与学习进度", symbol: "laptopcomputer.and.iphone")
                    }
                }
                .padding(26)
            }
            .quietAppear(order: 1)

            SettingsGroup(title: "当前版本") {
                SettingsRow(title: "LinguaFlow 本地版", detail: "核心输入、翻译、词汇卡片与本机学习记录。") {
                    Text("已启用")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }
            .quietAppear(order: 2)
        }
    }

    private func plusFeature(_ title: String, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsPageScrollView<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(.horizontal, 34)
            .padding(.top, 30)
            .padding(.bottom, 38)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollIndicators(.visible)
    }
}
