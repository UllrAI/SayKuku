import AppKit
import SwiftUI

enum KukuColor {
    static let canvas = adaptive(light: KukuTone(0.973, 0.968, 0.955), dark: KukuTone(0.110, 0.106, 0.102))
    static let sidebar = adaptive(light: KukuTone(0.955, 0.949, 0.936), dark: KukuTone(0.086, 0.083, 0.080))
    /// Pure white in light mode, a faint white in dark mode. Pair with `.opacity` for raised or hovered fills.
    static let highlight = adaptive(light: KukuTone(white: 1), dark: KukuTone(white: 1, alpha: 0.12))
    /// Black in light mode, white in dark mode. Pair with a low `.opacity` for chips, wells and hairlines.
    static let shade = adaptive(light: KukuTone(white: 0), dark: KukuTone(white: 1))
    static let surface = highlight.opacity(0.62)
    static let surfaceStrong = highlight.opacity(0.84)
    /// Card background for the floating panel, which has no window backdrop behind it.
    static let overlaySurface = adaptive(light: KukuTone(white: 1, alpha: 0.62), dark: KukuTone(0.16, 0.155, 0.15, alpha: 0.96))
    static let ink = adaptive(light: KukuTone(0.10, 0.095, 0.09), dark: KukuTone(0.925, 0.918, 0.905))
    static let graphite = adaptive(light: KukuTone(0.145, 0.14, 0.13), dark: KukuTone(0.25, 0.243, 0.235))
    static let stone = adaptive(light: KukuTone(0.43, 0.415, 0.39), dark: KukuTone(0.64, 0.625, 0.60))
    static let line = shade.opacity(0.085)
    static let coral = adaptive(light: KukuTone(0.93, 0.255, 0.18), dark: KukuTone(0.97, 0.36, 0.29))
    /// Fill behind white labels; deeper than `coral` so the text keeps about 4.5:1 contrast.
    static let coralFill = adaptive(light: KukuTone(0.85, 0.22, 0.15), dark: KukuTone(0.80, 0.25, 0.19))
    static let coralSoft = adaptive(light: KukuTone(0.985, 0.895, 0.855), dark: KukuTone(0.32, 0.15, 0.12))
    /// `mint` and `amber` are for icons and fills. Use the `…Text` variants for text.
    static let mint = adaptive(light: KukuTone(0.23, 0.63, 0.46), dark: KukuTone(0.34, 0.75, 0.56))
    static let amber = adaptive(light: KukuTone(0.91, 0.61, 0.20), dark: KukuTone(0.96, 0.69, 0.30))
    static let mintText = adaptive(light: KukuTone(0.14, 0.47, 0.33), dark: KukuTone(0.34, 0.75, 0.56))
    static let amberText = adaptive(light: KukuTone(0.62, 0.38, 0.05), dark: KukuTone(0.96, 0.69, 0.30))

    private static func adaptive(light: KukuTone, dark: KukuTone) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark.nsColor : light.nsColor
        })
    }
}

/// sRGB components, kept as plain values so the dynamic provider only captures Sendable data.
private struct KukuTone: Sendable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    init(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(white: CGFloat, alpha: CGFloat = 1) {
        self.init(white, white, white, alpha: alpha)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
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

private struct KukuGlassPillModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background(.thinMaterial, in: Capsule())
        }
    }
}

extension View {
    func kukuGlassPill() -> some View {
        modifier(KukuGlassPillModifier())
    }
}

enum KukuPillLayout {
    static func width(
        for text: String,
        minimum: CGFloat,
        fixedContentWidth: CGFloat,
        maximum: CGFloat = 350,
        fontSize: CGFloat = 11.5,
        fontWeight: NSFont.Weight = .semibold
    ) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: fontWeight)
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        return min(max(ceil(textWidth + fixedContentWidth), minimum), maximum)
    }

    /// Error feedback wraps to a second line once it reaches the maximum width.
    static func errorWidth(for text: String) -> CGFloat {
        width(for: text, minimum: 120, fixedContentWidth: 46, maximum: 340, fontSize: 11, fontWeight: .medium)
    }
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
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            let pressed = isEnabled && configuration.isPressed
            configuration.label
                .foregroundStyle(prominent ? Color.white : KukuColor.ink)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 13)
                .frame(minHeight: KukuLayout.controlHeight)
                .background {
                    RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous)
                        .fill(prominent
                              ? KukuColor.coralFill.opacity(pressed ? 0.86 : 1)
                              : KukuColor.shade.opacity(isEnabled && hovering ? 0.075 : 0.045))
                }
                .overlay {
                    if !prominent {
                        RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous)
                            .stroke(KukuColor.line, lineWidth: 1)
                    }
                }
                .scaleEffect(pressed ? 0.975 : 1)
                .opacity(isEnabled ? 1 : 0.45)
                .animation(Motion.snappy, value: hovering)
                .animation(Motion.snappy, value: pressed)
                .onHover { hovering = $0 }
        }
    }
}

struct TintButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TintButtonBody(configuration: configuration)
    }

    private struct TintButtonBody: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            let pressed = isEnabled && configuration.isPressed
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(KukuColor.coral)
                .padding(.horizontal, 12)
                .frame(minHeight: KukuLayout.controlHeight)
                .background(
                    KukuColor.coral.opacity(pressed ? 0.14 : (isEnabled && hovering ? 0.11 : 0.075)),
                    in: RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous)
                        .stroke(KukuColor.coral.opacity(0.16), lineWidth: 1)
                }
                .opacity(isEnabled ? 1 : 0.45)
                .animation(Motion.snappy, value: hovering)
                .animation(Motion.snappy, value: pressed)
                .onHover { hovering = $0 }
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
        .accessibilityLabel("SayKuku")
    }
}

struct Waveform: View {
    var color: Color = KukuColor.coral
    var isActive = true
    var level: Double? = nil
    var barCount = 18
    var height: CGFloat = 26

    var body: some View {
        Group {
            if let level {
                bars { index in
                    let audibleLevel = CGFloat(level < 0.08 ? 0 : min(1, (level - 0.08) / 0.62))
                    let center = CGFloat(max(barCount - 1, 1)) / 2
                    let distance = abs(CGFloat(index) - center) / max(center, 1)
                    let envelope = 1 - distance * 0.42
                    return 3 + (height - 3) * audibleLevel * envelope
                }
                .animation(.linear(duration: 0.08), value: level)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 24, paused: !isActive)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    bars { index in
                        let phase = Double(index) * 0.68
                        let wave = isActive
                            ? (sin(t * 6.2 + phase) + sin(t * 3.3 - phase * 0.5)) * 0.22 + 0.52
                            : 0.14
                        return max(3, height * wave)
                    }
                }
            }
        }
    }

    private func bars(barHeight: @escaping (Int) -> CGFloat) -> some View {
        HStack(spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(index < barCount * 2 / 3 ? color : KukuColor.stone.opacity(0.22))
                    .frame(width: 2.5, height: barHeight(index))
            }
        }
        .frame(height: height)
    }
}

/// Uppercased, so keep it to a word or two. Longer section titles read better as plain text.
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
                        .font(.system(size: 11))
                        .foregroundStyle(KukuColor.stone)
                } else {
                    Text(" ")
                        .font(.system(size: 11))
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

/// Standard sheet header: icon tile, optional eyebrow, title and a one-sentence description.
/// Sheets close from their footer buttons, so the header has no close button.
struct KukuSheetHeader<Icon: View>: View {
    var eyebrow: String? = nil
    let title: String
    let description: String
    @ViewBuilder let icon: Icon

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            icon
                .frame(width: 48, height: 48)
                .background(
                    KukuColor.coralSoft,
                    in: RoundedRectangle(cornerRadius: KukuLayout.radiusMedium, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 5) {
                if let eyebrow {
                    SectionEyebrow(text: eyebrow)
                }
                Text(title)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(KukuColor.ink)
                Text(description)
                    .font(.system(size: 11.5))
                    .foregroundStyle(KukuColor.stone)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 18)
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
                                RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous)
                                    .fill(KukuColor.surfaceStrong)
                                    .shadow(color: Color.black.opacity(0.06), radius: 2, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == item ? .isSelected : [])
            }
        }
        .padding(3)
        .background(KukuColor.shade.opacity(0.045), in: RoundedRectangle(cornerRadius: KukuLayout.radiusMedium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: KukuLayout.radiusMedium, style: .continuous)
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
        elevated: Bool = false,
        fill: Color = KukuColor.surface
    ) -> some View {
        self
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(KukuColor.line, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(elevated ? 0.05 : 0), radius: 12, y: 5)
    }
}
