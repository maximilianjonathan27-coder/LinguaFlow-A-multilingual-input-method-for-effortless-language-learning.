import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var settings = LinguaFlowSettings()
    @State private var selection: SettingsSection = .overview
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showsTranslationLab = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var sidebarSelection

    private let sidebarGroups: [(title: String, sections: [SettingsSection])] = [
        ("输入体验", [.overview, .candidates, .translation]),
        ("语言学习", [.learning, .vocabulary, .vocabularyLibrary]),
        ("个性化", [.motion]),
        ("账户", [.membership])
    ]

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 232, max: 260)
        } detail: {
            ZStack {
                LinguaFlowWindowBackground()

                selectedPage
                    .id(selection)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .offset(y: 6))
                    )
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: selection)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 6) {
                    Button {
                        showsTranslationLab = true
                    } label: {
                        Label("本地翻译实验", systemImage: "character.book.closed")
                    }

                    Divider().frame(height: 14)

                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                    Text("本机运行")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("LinguaFlow 本机运行")
            }
        }
        .sheet(isPresented: $showsTranslationLab) {
            TranslationTestContainerView()
        }
    }

    private var sidebar: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()

            LinearGradient(
                colors: [Color.cyan.opacity(0.035), .clear],
                startPoint: .topLeading,
                endPoint: .center
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                brandHeader

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(sidebarGroups.enumerated()), id: \.offset) { _, group in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(group.title)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .textCase(.uppercase)
                                    .tracking(0.35)
                                    .padding(.leading, 12)

                                ForEach(group.sections) { section in
                                    SidebarNavigationButton(
                                        section: section,
                                        selection: $selection,
                                        selectionNamespace: sidebarSelection
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 11)
                    .padding(.top, 4)
                    .padding(.bottom, 14)
                }

                sidebarFooter
            }
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 11) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 38, height: 38)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("LinguaFlow")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text("Settings")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 17)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().opacity(0.6)
            Button {
                if reduceMotion {
                    selection = .overview
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { selection = .overview }
                }
            } label: {
                SidebarStatusCard()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 11)
            .padding(.bottom, 11)
        }
    }

    @ViewBuilder
    private var selectedPage: some View {
        switch selection {
        case .overview:
            OverviewPage(settings: settings)
        case .candidates:
            CandidateSettingsPage(settings: settings)
        case .translation:
            TranslationSettingsPage(settings: settings)
        case .learning:
            LearningSettingsPage(settings: settings)
        case .vocabulary:
            VocabularySettingsPage(settings: settings)
        case .vocabularyLibrary:
            VocabularyLibraryPage()
        case .motion:
            MotionSettingsPage(settings: settings)
        case .membership:
            MembershipSettingsPage(settings: settings)
        }
    }
}

private struct SidebarNavigationButton: View {
    let section: SettingsSection
    @Binding var selection: SettingsSection
    let selectionNamespace: Namespace.ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var isSelected: Bool { selection == section }

    var body: some View {
        Button {
            if reduceMotion {
                selection = section
            } else {
                withAnimation(.easeOut(duration: 0.20)) { selection = section }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 22)

                Text(section.title)
                    .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))

                Spacer()

                if isHovering, !isSelected {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 35)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.thinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.accentColor.opacity(0.07))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.18), Color.accentColor.opacity(0.10)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.75
                                )
                        }
                        .matchedGeometryEffect(id: "sidebar-selection", in: selectionNamespace)
                } else if isHovering {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                }
            }
            .offset(x: isHovering && !isSelected && !reduceMotion ? 1 : 0)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.16), value: isHovering)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SidebarStatusCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 33, height: 33)
                Image(systemName: "waveform.path")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("LinguaFlow 0.2")
                    .font(.system(size: 11.5, weight: .semibold))
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 5, height: 5)
                    Text("输入法已就绪")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .opacity(isHovering ? 1 : 0.55)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(
                    isHovering ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.08),
                    lineWidth: 0.8
                )
        }
        .brightness(isHovering ? 0.025 : 0)
        .offset(y: isHovering && !reduceMotion ? -1 : 0)
        .shadow(color: .black.opacity(isHovering ? 0.12 : 0.06), radius: isHovering ? 10 : 6, y: 4)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.18), value: isHovering)
    }
}
