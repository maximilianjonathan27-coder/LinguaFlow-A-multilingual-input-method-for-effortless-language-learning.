import SwiftUI

struct LinguaFlowWindowBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.055, green: 0.065, blue: 0.085), Color(red: 0.075, green: 0.085, blue: 0.105)]
                    : [Color(red: 0.955, green: 0.965, blue: 0.975), Color(red: 0.91, green: 0.93, blue: 0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color.cyan.opacity(colorScheme == .dark ? 0.055 : 0.075), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}

struct PremiumGlassSurface<Content: View>: View {
    let cornerRadius: CGFloat
    let glassEnabled: Bool
    let ambient: Bool
    let interactive: Bool
    let pointerLight: Bool
    let ambientIntensity: Double
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    @State private var pointerLocation = CGPoint(x: 0.5, y: 0.5)
    @State private var ambientPhase = false

    init(
        cornerRadius: CGFloat = 18,
        glassEnabled: Bool = true,
        ambient: Bool = false,
        interactive: Bool = false,
        pointerLight: Bool = false,
        ambientIntensity: Double = 0.65,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.glassEnabled = glassEnabled
        self.ambient = ambient
        self.interactive = interactive
        self.pointerLight = pointerLight
        self.ambientIntensity = ambientIntensity
        self.content = content()
    }

    var body: some View {
        ZStack {
            surface

            if ambient {
                ambientLayers
                    .allowsHitTesting(false)
                    .clipShape(shape)
            }

            if interactive, pointerLight, isHovering, !reduceMotion {
                pointerHighlight
                    .allowsHitTesting(false)
                    .clipShape(shape)
                    .transition(.opacity)
            }

            content
        }
        .clipShape(shape)
        .overlay {
            shape
                .strokeBorder(borderGradient, lineWidth: 1)
        }
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.22 : 0.10),
            radius: isHovering && interactive ? 18 : 14,
            y: isHovering && interactive ? 8 : 6
        )
        .brightness(isHovering && interactive ? 0.025 : 0)
        .animation(.easeOut(duration: 0.18), value: isHovering)
        .onContinuousHover { phase in
            guard interactive else { return }
            switch phase {
            case let .active(location):
                isHovering = true
                pointerLocation = location
            case .ended:
                isHovering = false
            }
        }
        .onAppear { updateAmbientAnimation() }
        .onChange(of: ambient) { _, _ in updateAmbientAnimation() }
        .onChange(of: reduceMotion) { _, _ in updateAmbientAnimation() }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    @ViewBuilder
    private var surface: some View {
        if glassEnabled {
            shape
                .fill(.regularMaterial)
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.035 : 0.15),
                                Color.white.opacity(0.01),
                                Color.cyan.opacity(colorScheme == .dark ? 0.025 : 0.018)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
        } else {
            shape.fill(Color(nsColor: .controlBackgroundColor).opacity(0.96))
        }
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(isHovering && interactive ? 0.30 : 0.20),
                Color.primary.opacity(0.075),
                Color.cyan.opacity(isHovering && interactive ? 0.15 : 0.07)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var ambientLayers: some View {
        GeometryReader { proxy in
            ZStack {
                Ellipse()
                    .fill(Color.cyan.opacity(0.07 * ambientIntensity))
                    .frame(width: proxy.size.width * 0.78, height: proxy.size.height * 0.82)
                    .blur(radius: 58)
                    .offset(
                        x: ambientPhase ? proxy.size.width * 0.16 : -proxy.size.width * 0.12,
                        y: ambientPhase ? -4 : 4
                    )
                    .scaleEffect(ambientPhase ? 1.015 : 1.0)

                Ellipse()
                    .fill(Color.blue.opacity(0.045 * ambientIntensity))
                    .frame(width: proxy.size.width * 0.58, height: proxy.size.height * 0.68)
                    .blur(radius: 44)
                    .offset(
                        x: ambientPhase ? -proxy.size.width * 0.14 : proxy.size.width * 0.12,
                        y: ambientPhase ? 3 : -3
                    )
                    .opacity(ambientPhase ? 0.82 : 1.0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var pointerHighlight: some View {
        GeometryReader { proxy in
            let x = max(0, min(1, pointerLocation.x / max(proxy.size.width, 1)))
            let y = max(0, min(1, pointerLocation.y / max(proxy.size.height, 1)))
            RadialGradient(
                colors: [Color.white.opacity(0.10), Color.cyan.opacity(0.025), .clear],
                center: UnitPoint(x: x, y: y),
                startRadius: 0,
                endRadius: max(proxy.size.width, proxy.size.height) * 0.48
            )
        }
    }

    private func updateAmbientAnimation() {
        guard ambient, !reduceMotion else {
            withAnimation(.easeOut(duration: 0.45)) {
                ambientPhase = false
            }
            return
        }

        ambientPhase = false
        withAnimation(.easeInOut(duration: 15).repeatForever(autoreverses: true)) {
            ambientPhase = true
        }
    }
}

struct SettingsPageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 14.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }

            PremiumGlassSurface(cornerRadius: 16) {
                VStack(spacing: 0) {
                    content
                }
                .padding(.horizontal, 18)
            }
        }
    }
}

struct SettingsRow<Control: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let control: Control

    init(title: String, detail: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(alignment: detail == nil ? .center : .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14.5, weight: .medium))
                if let detail {
                    Text(detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            control
                .labelsHidden()
        }
        .padding(.vertical, 13)
    }
}

struct HairlineDivider: View {
    var body: some View {
        Divider().padding(.leading, 2)
    }
}

private struct QuietAppearModifier: ViewModifier {
    let order: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 4)
            .onAppear {
                if reduceMotion {
                    visible = true
                } else {
                    withAnimation(.easeOut(duration: 0.22).delay(Double(order) * 0.028)) {
                        visible = true
                    }
                }
            }
    }
}

extension View {
    func quietAppear(order: Int) -> some View {
        modifier(QuietAppearModifier(order: order))
    }
}
