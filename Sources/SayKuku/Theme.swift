import AppKit
import SwiftUI

// Design tokens. The rules for using them live in the design system guide; the
// short version: neutrals carry hierarchy, coral is the only accent, and status
// colors only ever mean status. Shared components are in DesignSystem.swift.

// MARK: - Color

enum KukuColor {
    // MARK: Backgrounds

    /// Window content background.
    static let canvas = adaptive(light: KukuTone(0.969, 0.965, 0.957), dark: KukuTone(0.110, 0.106, 0.102))
    static let sidebar = adaptive(light: KukuTone(0.941, 0.937, 0.929), dark: KukuTone(0.086, 0.083, 0.080))
    /// Cards, groups and list rows on the canvas.
    static let surface = adaptive(light: KukuTone(0.992, 0.991, 0.988), dark: KukuTone(0.141, 0.137, 0.133))
    /// Raised on a surface or fill: the selected tab, text fields, popover-like panels.
    static let surfaceRaised = adaptive(light: KukuTone(white: 1), dark: KukuTone(0.176, 0.172, 0.167))
    /// Card background for the floating panel, which has no window backdrop behind it.
    static let overlaySurface = adaptive(light: KukuTone(white: 1, alpha: 0.62), dark: KukuTone(0.16, 0.155, 0.15, alpha: 0.96))
    /// In-window toast. Inverted so it reads over any content.
    static let toastSurface = adaptive(light: KukuTone(0.157, 0.153, 0.145, alpha: 0.96), dark: KukuTone(0.235, 0.231, 0.224, alpha: 0.96))
    static let toastText = adaptive(light: KukuTone(white: 1), dark: KukuTone(white: 0.96))

    // MARK: Text

    static let textPrimary = adaptive(light: KukuTone(0.110, 0.106, 0.098), dark: KukuTone(0.929, 0.922, 0.910))
    /// Captions, descriptions and metadata. At least 4.5:1 on every background.
    static let textSecondary = adaptive(
        light: KukuTone(0.380, 0.369, 0.349), dark: KukuTone(0.667, 0.655, 0.635),
        highContrast: (light: KukuTone(0.220, 0.212, 0.200), dark: KukuTone(0.827, 0.820, 0.808))
    )
    /// Placeholders, unselected indicators and decorative glyphs. Never for information people need to read.
    static let textTertiary = adaptive(light: KukuTone(0.545, 0.533, 0.514), dark: KukuTone(0.478, 0.467, 0.451))

    // MARK: Lines

    /// Outline of cards, groups, controls and fields.
    static let border = adaptive(
        light: KukuTone(white: 0, alpha: 0.09), dark: KukuTone(white: 1, alpha: 0.10),
        highContrast: (light: KukuTone(white: 0, alpha: 0.40), dark: KukuTone(white: 1, alpha: 0.45))
    )
    /// Outline of selected choices and hovered fields.
    static let borderStrong = adaptive(
        light: KukuTone(white: 0, alpha: 0.16), dark: KukuTone(white: 1, alpha: 0.18),
        highContrast: (light: KukuTone(white: 0, alpha: 0.70), dark: KukuTone(white: 1, alpha: 0.75))
    )
    /// Dividers between rows and below page tabs.
    static let separator = adaptive(
        light: KukuTone(white: 0, alpha: 0.07), dark: KukuTone(white: 1, alpha: 0.08),
        highContrast: (light: KukuTone(white: 0, alpha: 0.30), dark: KukuTone(white: 1, alpha: 0.35))
    )

    // MARK: Neutral fills

    /// Resting fill of secondary controls, tab tracks, icon tiles, badges and key caps.
    static let fill = adaptive(light: KukuTone(white: 0, alpha: 0.045), dark: KukuTone(white: 1, alpha: 0.06))
    static let fillHover = adaptive(light: KukuTone(white: 0, alpha: 0.07), dark: KukuTone(white: 1, alpha: 0.09))
    static let fillPressed = adaptive(light: KukuTone(white: 0, alpha: 0.10), dark: KukuTone(white: 1, alpha: 0.13))
    /// Hover on rows and cards that have no fill of their own.
    static let rowHover = adaptive(light: KukuTone(white: 0, alpha: 0.03), dark: KukuTone(white: 1, alpha: 0.045))
    /// Selected sidebar item, choice card or radio row.
    static let selectedFill = adaptive(light: KukuTone(white: 0, alpha: 0.065), dark: KukuTone(white: 1, alpha: 0.10))

    // MARK: Accent

    /// The brand color and the only accent. Brand mark, selection indicators, live recording.
    static let coral = adaptive(light: KukuTone(0.93, 0.255, 0.18), dark: KukuTone(0.97, 0.36, 0.29))
    /// Primary button fill; deep enough for `onAccent` text at about 4.5:1.
    static let accentFill = adaptive(light: KukuTone(0.85, 0.22, 0.15), dark: KukuTone(0.80, 0.25, 0.19))
    /// Coral for text and links, at least 4.5:1 on canvas and surface.
    static let accentText = adaptive(light: KukuTone(0.78, 0.20, 0.13), dark: KukuTone(0.98, 0.44, 0.37))
    /// Background of an in-progress accent state, such as a shortcut being recorded. Use sparingly.
    static let accentSubtle = adaptive(light: KukuTone(0.93, 0.255, 0.18, alpha: 0.08), dark: KukuTone(0.97, 0.36, 0.29, alpha: 0.16))
    static let onAccent = Color.white
    static let focusRing = adaptive(light: KukuTone(0.93, 0.255, 0.18, alpha: 0.5), dark: KukuTone(0.97, 0.36, 0.29, alpha: 0.6))

    // MARK: Status

    /// Status colors are for icons, dots and meters only; the text next to them stays neutral.
    static let success = adaptive(light: KukuTone(0.204, 0.576, 0.408), dark: KukuTone(0.353, 0.741, 0.553))
    static let warning = adaptive(light: KukuTone(0.851, 0.557, 0.137), dark: KukuTone(0.937, 0.690, 0.314))
    static let danger = adaptive(light: KukuTone(0.816, 0.184, 0.220), dark: KukuTone(0.96, 0.40, 0.41))

    /// `highContrast` applies with Increase Contrast; tokens without it keep their regular values.
    fileprivate static func adaptive(
        light: KukuTone,
        dark: KukuTone,
        highContrast: (light: KukuTone, dark: KukuTone)? = nil
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let appearances: [NSAppearance.Name] = [
                .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
            ]
            let tone = switch appearance.bestMatch(from: appearances) ?? .aqua {
            case .darkAqua: dark
            case .accessibilityHighContrastAqua: highContrast?.light ?? light
            case .accessibilityHighContrastDarkAqua: highContrast?.dark ?? dark
            default: light
            }
            return tone.nsColor
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

/// Meaning of a badge, status line or notice. Tones color only the icon; text stays neutral.
enum KukuStatusTone: Sendable {
    case neutral, success, warning, danger

    var iconColor: Color {
        switch self {
        case .neutral: KukuColor.textSecondary
        case .success: KukuColor.success
        case .warning: KukuColor.warning
        case .danger: KukuColor.danger
        }
    }

    var symbol: String {
        switch self {
        case .neutral: "info.circle"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .danger: "exclamationmark.circle.fill"
        }
    }
}

// MARK: - Spacing and layout

/// Spacing scale on a 4 pt grid. Use these for padding and stack spacing.
enum KukuSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    /// Between an icon and its text, the one step off the 4 pt grid.
    static let iconText: CGFloat = 6
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
}

enum KukuLayout {
    // Page
    static let sidebarWidth: CGFloat = 176
    static let pageMaxWidth: CGFloat = 760
    static let pageGutter: CGFloat = KukuSpacing.xxl
    static let pageTop: CGFloat = KukuSpacing.xxl
    static let headerBottom: CGFloat = KukuSpacing.lg
    static let tabsBottom: CGFloat = KukuSpacing.md
    static let contentTop: CGFloat = KukuSpacing.xl
    static let contentBottom: CGFloat = KukuSpacing.xxxl
    /// Between groups or major blocks on a page.
    static let sectionSpacing: CGFloat = KukuSpacing.xxl
    /// Between a group's eyebrow and its card.
    static let groupTitleSpacing: CGFloat = KukuSpacing.sm
    /// Between stacked cards in a list.
    static let listSpacing: CGFloat = KukuSpacing.sm

    // Cards and rows
    static let cardPadding: CGFloat = KukuSpacing.lg
    static let rowPadding: CGFloat = KukuSpacing.lg
    static let rowMinHeight: CGFloat = 44
    static let rowMinHeightWithCaption: CGFloat = 56

    // Controls
    static let controlHeight: CGFloat = 32
    static let controlHeightSmall: CGFloat = 24
    static let badgeHeight: CGFloat = 20
    /// `KukuIconButton` hit areas, regular and small.
    static let iconButton: CGFloat = 28
    static let iconButtonSmall: CGFloat = 20
    /// Status and timeline dots.
    static let statusDot: CGFloat = 8
    static let iconTile: CGFloat = 32
    static let iconTileLarge: CGFloat = 40
    static let searchFieldWidth: CGFloat = 220
    static let pickerWidth: CGFloat = 220
    static let emptyStateMinHeight: CGFloat = 180

    // Sheets
    static let sheetWidth: CGFloat = 560
    static let sheetWideWidth: CGFloat = 640
    static let sheetHeight: CGFloat = 540
    static let sheetPadding: CGFloat = KukuSpacing.xxl

    // Overlay
    static let pillHeight: CGFloat = 36
    static let pillButton: CGFloat = 24

    // Radius. Capsule() is for pills, badges and chips; Circle() for round pill buttons.
    /// Controls, fields, icon tiles, key caps.
    static let radiusSmall: CGFloat = 8
    /// Cards, groups, list rows, tab tracks.
    static let radiusMedium: CGFloat = 12
    /// Hero cards, the answer card and toasts.
    static let radiusLarge: CGFloat = 16
}

enum KukuBorder {
    static let width: CGFloat = 1
    static let focusWidth: CGFloat = 1.5
}

enum KukuState {
    static let disabledOpacity: Double = 0.45
    /// Pressed buttons shrink slightly; with Reduce Motion they hold still.
    static var pressedScale: CGFloat { Motion.isReduced ? 1 : 0.98 }
    static var iconPressedScale: CGFloat { Motion.isReduced ? 1 : 0.94 }
}

// MARK: - Typography

/// Eight sizes, no half points. Rounded only for titles; weights stay within regular, medium and semibold.
enum KukuTextStyle: Sendable {
    /// Page title in `ScreenHeader`.
    case largeTitle
    /// Sheet titles and settings section titles.
    case title
    /// Hero card titles, such as the Home gesture cards.
    case title3
    /// Card and list row titles.
    case headline
    /// Content, inputs, settings row titles.
    case body
    /// Buttons, tabs, overlay pills, page subtitles, secondary content.
    case callout
    /// Captions and descriptions under a title.
    case subheadline
    /// Eyebrows, badges, key caps, timestamps.
    case caption

    var size: CGFloat {
        switch self {
        case .largeTitle: 22
        case .title: 18
        case .title3: 15
        case .headline, .body: 13
        case .callout: 12
        case .subheadline: 11
        case .caption: 10
        }
    }

    var weight: Font.Weight {
        switch self {
        case .largeTitle, .title, .title3, .headline: .semibold
        case .caption: .medium
        case .body, .callout, .subheadline: .regular
        }
    }

    var design: Font.Design {
        switch self {
        case .largeTitle, .title, .title3: .rounded
        default: .default
        }
    }
}

enum KukuTypography {
    /// Extra line spacing for paragraphs of three or more lines.
    static let paragraphSpacing: CGFloat = 2
    /// Tracking for uppercased eyebrows.
    static let eyebrowTracking: CGFloat = 0.6
}

/// SF Symbol sizes. Match the weight of the text next to the icon; `.medium` by default.
enum KukuIconSize: CGFloat, Sendable {
    /// Inside badges and small round pill buttons.
    case mini = 9
    /// Next to captions and subheadlines, chevrons.
    case small = 11
    /// Next to body text, row actions, the sidebar.
    case regular = 13
    /// In a regular icon tile.
    case medium = 15
    /// In a large icon tile, such as a sheet header.
    case large = 18
}

extension Font {
    static func kuku(_ style: KukuTextStyle, weight: Font.Weight? = nil) -> Font {
        .system(size: style.size, weight: weight ?? style.weight, design: style.design)
    }

    static func kukuIcon(_ size: KukuIconSize, weight: Font.Weight = .medium) -> Font {
        .system(size: size.rawValue, weight: weight)
    }
}

// MARK: - Elevation

/// Three neutral shadows. Never tint a shadow; never glow.
struct KukuShadow: Sendable {
    let color: Color
    let radius: CGFloat
    let y: CGFloat

    /// Selected tab and other small raised controls.
    static let raised = KukuShadow(
        color: KukuColor.adaptive(light: KukuTone(white: 0, alpha: 0.08), dark: KukuTone(white: 0, alpha: 0.35)),
        radius: 1.5,
        y: 1
    )
    /// Elevated cards, such as the Home gesture cards.
    static let card = KukuShadow(
        color: KukuColor.adaptive(light: KukuTone(white: 0, alpha: 0.05), dark: KukuTone(white: 0, alpha: 0.30)),
        radius: 10,
        y: 3
    )
    /// Toasts, the answer card and other floating panels.
    static let floating = KukuShadow(
        color: KukuColor.adaptive(light: KukuTone(white: 0, alpha: 0.14), dark: KukuTone(white: 0, alpha: 0.45)),
        radius: 16,
        y: 6
    )
}

// MARK: - Motion

/// Every token is nil with Reduce Motion, so changes apply without animating.
/// Read on each use rather than from the environment because models animate their changes too.
enum Motion {
    static var isReduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Hover, selection and other small state changes.
    static var snappy: Animation? { animation(.easeInOut(duration: 0.22)) }
    /// Inserting, removing or reordering list content.
    static var spring: Animation? { animation(.spring(response: 0.42, dampingFraction: 0.76, blendDuration: 0.15)) }
    /// Overlay appearance and sheet step changes.
    static var panel: Animation? { animation(.spring(response: 0.5, dampingFraction: 0.82, blendDuration: 0.2)) }
    /// Overlay pill width changes.
    static var pill: Animation? { animation(.spring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.12)) }
    /// Pressed feedback on buttons.
    static var press: Animation? { animation(.spring(response: 0.24, dampingFraction: 0.75)) }
    /// Audio level meters and waveforms that follow live input.
    static var meter: Animation? { animation(.linear(duration: 0.08)) }

    private static func animation(_ animation: Animation) -> Animation? {
        isReduced ? nil : animation
    }
}

// MARK: - Surface modifiers

extension View {
    /// Filled, outlined surface. `elevated` adds the card shadow and is for hero cards only.
    func kukuSurface(
        radius: CGFloat = KukuLayout.radiusMedium,
        elevated: Bool = false,
        fill: Color = KukuColor.surface
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(fill, in: shape)
            .overlay { shape.strokeBorder(KukuColor.border, lineWidth: KukuBorder.width) }
            .kukuShadow(elevated ? KukuShadow.card : nil)
    }

    /// A padded card that fills the available width.
    func kukuCard(radius: CGFloat = KukuLayout.radiusMedium) -> some View {
        self
            .padding(KukuLayout.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kukuSurface(radius: radius)
    }

    func kukuShadow(_ shadow: KukuShadow?) -> some View {
        self.shadow(color: shadow?.color ?? .clear, radius: shadow?.radius ?? 0, y: shadow?.y ?? 0)
    }

    /// Glass capsule behind every overlay pill.
    func kukuGlassPill() -> some View {
        modifier(KukuGlassPillModifier())
    }
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

enum KukuPillLayout {
    static func width(
        for text: String,
        minimum: CGFloat,
        fixedContentWidth: CGFloat,
        maximum: CGFloat = 350,
        fontWeight: NSFont.Weight = .semibold
    ) -> CGFloat {
        // Pill text is always callout; only the weight differs between states and errors.
        let font = NSFont.systemFont(ofSize: KukuTextStyle.callout.size, weight: fontWeight)
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        return min(max(ceil(textWidth + fixedContentWidth), minimum), maximum)
    }

    /// Error feedback wraps to a second line once it reaches the maximum width.
    static func errorWidth(for text: String) -> CGFloat {
        width(for: text, minimum: 120, fixedContentWidth: 46, maximum: 340, fontWeight: .medium)
    }
}
