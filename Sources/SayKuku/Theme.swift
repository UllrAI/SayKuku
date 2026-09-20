import AppKit
import SwiftUI

enum KukuColor {
    static let canvas = Color(red: 0.973, green: 0.968, blue: 0.955)
    static let sidebar = Color(red: 0.955, green: 0.949, blue: 0.936)
    static let surface = Color.white.opacity(0.62)
    static let surfaceStrong = Color.white.opacity(0.84)
    static let ink = Color(red: 0.10, green: 0.095, blue: 0.09)
    static let graphite = Color(red: 0.145, green: 0.14, blue: 0.13)
    static let stone = Color(red: 0.43, green: 0.415, blue: 0.39)
    static let line = Color.black.opacity(0.085)
    static let coral = Color(red: 0.93, green: 0.255, blue: 0.18)
    static let coralSoft = Color(red: 0.985, green: 0.895, blue: 0.855)
    static let mint = Color(red: 0.23, green: 0.63, blue: 0.46)
    static let amber = Color(red: 0.91, green: 0.61, blue: 0.20)
}

enum KukuLayout {
    static let pageGutter: CGFloat = 28
    static let pageTop: CGFloat = 24
    static let headerBottom: CGFloat = 16
    static let pageMaxWidth: CGFloat = 760
    static let controlHeight: CGFloat = 32
    static let rowHeight: CGFloat = 56
    static let radiusSmall: CGFloat = 8
    static let radiusMedium: CGFloat = 12
    static let radiusLarge: CGFloat = 16
}

enum Motion {
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.76, blendDuration: 0.15)
    static let panel = Animation.spring(response: 0.5, dampingFraction: 0.82, blendDuration: 0.2)
    static let pill = Animation.spring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.12)
    static let snappy = Animation.easeInOut(duration: 0.22)
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .brightness(configuration.isPressed ? -0.025 : 0)
            .animation(.spring(response: 0.24, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

struct HoverFillButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        HoverButtonBody(configuration: configuration, prominent: prominent)
    }

    private struct HoverButtonBody: View {
        let configuration: ButtonStyle.Configuration
        let prominent: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(prominent ? Color.white : KukuColor.ink)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 13)
                .frame(minHeight: KukuLayout.controlHeight)
                .background {
                    RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous)
                        .fill(prominent ? KukuColor.coral.opacity(configuration.isPressed ? 0.86 : 1) : Color.black.opacity(hovering ? 0.075 : 0.045))
                }
                .overlay {
                    if !prominent {
                        RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous)
                            .stroke(KukuColor.line, lineWidth: 1)
                    }
                }
                .scaleEffect(configuration.isPressed ? 0.975 : 1)
                .animation(Motion.snappy, value: hovering)
                .animation(Motion.snappy, value: configuration.isPressed)
                .onHover { hovering = $0 }
        }
    }
}

struct TintButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(KukuColor.coral)
            .padding(.horizontal, 12)
            .frame(minHeight: KukuLayout.controlHeight)
            .background(
                KukuColor.coral.opacity(configuration.isPressed ? 0.14 : 0.075),
                in: RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous)
                    .stroke(KukuColor.coral.opacity(0.16), lineWidth: 1)
            }
    }
}

struct BrandMark: View {
    var size: CGFloat = 27
    var color: Color = KukuColor.coral

    var body: some View {
        Group {
            if let url = Bundle.module.url(forResource: "SayKuku", withExtension: "svg"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
            } else {
                Image(systemName: "bird")
                    .resizable()
            }
        }
        .scaledToFit()
        .foregroundStyle(color)
        .frame(width: size, height: size)
        .accessibilityLabel("SayKuku bird")
    }
}

struct Waveform: View {
    var color: Color = KukuColor.coral
    var isActive = true
    var barCount = 18
    var height: CGFloat = 26

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !isActive)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<barCount, id: \.self) { index in
                    let phase = Double(index) * 0.68
                    let wave = isActive ? (sin(t * 6.2 + phase) + sin(t * 3.3 - phase * 0.5)) * 0.22 + 0.52 : 0.14
                    Capsule()
                        .fill(index < barCount * 2 / 3 ? color : KukuColor.stone.opacity(0.22))
                        .frame(width: 2.5, height: max(3, height * wave))
                }
            }
            .frame(height: height)
        }
    }
}

struct SectionEyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .bold, design: .rounded))
            .tracking(1.05)
            .foregroundStyle(KukuColor.stone)
    }
}

struct ScreenHeader<Accessory: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String?
    @ViewBuilder let accessory: Accessory

    init(
        eyebrow: String,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                SectionEyebrow(text: eyebrow)
                Text(title).kukuSectionTitle()
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(KukuColor.stone)
                } else {
                    Text(" ")
                        .font(.system(size: 10))
                        .hidden()
                        .accessibilityHidden(true)
                }
            }
            Spacer(minLength: 20)
            accessory
        }
        .frame(maxWidth: KukuLayout.pageMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, KukuLayout.pageGutter)
        .padding(.top, KukuLayout.pageTop)
        .padding(.bottom, KukuLayout.headerBottom)
    }
}

struct KukuPageContent<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: KukuLayout.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, KukuLayout.pageGutter)
    }
}

struct KukuTabBar<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(items, id: \.self) { item in
                Button {
                    withAnimation(Motion.snappy) { selection = item }
                } label: {
                    Text(title(item))
                        .font(.system(size: 11.5, weight: selection == item ? .semibold : .medium))
                        .foregroundStyle(selection == item ? KukuColor.ink : KukuColor.stone)
                        .padding(.horizontal, 13)
                        .frame(minWidth: 68, minHeight: 29)
                        .background {
                            if selection == item {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(KukuColor.surfaceStrong)
                                    .shadow(color: Color.black.opacity(0.06), radius: 2, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(KukuColor.line, lineWidth: 1)
        }
    }
}

struct KukuPageTabs<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String

    var body: some View {
        KukuPageContent {
            KukuTabBar(items: items, selection: $selection, title: title)
        }
        .padding(.bottom, 14)
    }
}

extension ScreenHeader where Accessory == EmptyView {
    init(eyebrow: String, title: String, subtitle: String? = nil) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle) { EmptyView() }
    }
}

extension View {
    func kukuSectionTitle() -> some View {
        self.font(.system(size: 23, weight: .semibold, design: .rounded))
            .foregroundStyle(KukuColor.ink)
    }

    func kukuSurface(
        radius: CGFloat = KukuLayout.radiusMedium,
        elevated: Bool = false
    ) -> some View {
        self
            .background(KukuColor.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(KukuColor.line, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(elevated ? 0.05 : 0), radius: 12, y: 5)
    }
}
