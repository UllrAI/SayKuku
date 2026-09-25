import AppKit
import SwiftUI

// Shared components built only from the tokens in Theme.swift. Pages compose
// these instead of styling their own buttons, rows, fields and headers.

// MARK: - Buttons

/// The one button style. At most one `.primary` per page header, sheet footer or card.
/// Destructive actions use `.secondary` and confirm with a `role: .destructive` dialog button.
struct KukuButtonStyle: ButtonStyle {
    enum Kind {
        /// Coral fill with white text: the main action of a view.
        case primary
        /// Neutral fill with an outline: every other action.
        case secondary
        /// Text only until hovered: low-emphasis inline actions such as Show More or Copy Result.
        case plain
    }

    enum Size {
        case regular
        /// For dense rows and notices.
        case small
    }

    var kind: Kind = .secondary
    var size: Size = .regular

    func makeBody(configuration: Configuration) -> some View {
        KukuButtonBody(configuration: configuration, kind: kind, size: size)
    }
}

extension ButtonStyle where Self == KukuButtonStyle {
    static var kukuPrimary: KukuButtonStyle { KukuButtonStyle(kind: .primary) }
    static var kukuSecondary: KukuButtonStyle { KukuButtonStyle(kind: .secondary) }

    static func kuku(_ kind: KukuButtonStyle.Kind, size: KukuButtonStyle.Size = .regular) -> KukuButtonStyle {
        KukuButtonStyle(kind: kind, size: size)
    }
}

private struct KukuButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: KukuButtonStyle.Kind
    let size: KukuButtonStyle.Size
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous)
    }

    var body: some View {
        let pressed = isEnabled && configuration.isPressed
        let hovered = isEnabled && hovering
        configuration.label
            .font(.kuku(size == .regular ? .callout : .subheadline, weight: .semibold))
            .foregroundStyle(foreground(hovered: hovered))
            .lineLimit(1)
            .padding(.horizontal, size == .regular ? KukuSpacing.md : KukuSpacing.sm)
            .frame(minHeight: size == .regular ? KukuLayout.controlHeight : KukuLayout.controlHeightSmall)
            .background {
                shape
                    .fill(fill(hovered: hovered, pressed: pressed))
                    // Darkens the accent instead of fading it, so white text keeps its contrast.
                    .brightness(kind == .primary ? (pressed ? -0.08 : (hovered ? -0.04 : 0)) : 0)
            }
            .overlay {
                if kind == .secondary {
                    shape.strokeBorder(KukuColor.border, lineWidth: KukuBorder.width)
                }
            }
            .contentShape(shape)
            .scaleEffect(pressed ? KukuState.pressedScale : 1)
            .opacity(isEnabled ? 1 : KukuState.disabledOpacity)
            .animation(Motion.snappy, value: hovered)
            .animation(Motion.press, value: pressed)
            .onHover { hovering = $0 }
    }

    private func foreground(hovered: Bool) -> Color {
        switch kind {
        case .primary: KukuColor.onAccent
        case .secondary: KukuColor.textPrimary
        case .plain: hovered ? KukuColor.textPrimary : KukuColor.textSecondary
        }
    }

    private func fill(hovered: Bool, pressed: Bool) -> Color {
        switch kind {
        case .primary:
            KukuColor.accentFill
        case .secondary:
            pressed ? KukuColor.fillPressed : (hovered ? KukuColor.fillHover : KukuColor.fill)
        case .plain:
            pressed ? KukuColor.fillPressed : (hovered ? KukuColor.fillHover : Color.clear)
        }
    }
}

/// Pressed feedback for icon-only buttons that draw their own chrome.
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? KukuState.iconPressedScale : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// Icon-only button with a hover fill. `label` is spoken by VoiceOver; `help` is the tooltip and defaults to the label.
struct KukuIconButton: View {
    enum Size {
        /// `KukuLayout.iconButton`, for row actions and closing cards.
        case regular
        /// `KukuLayout.iconButtonSmall`, for removing chips and list items.
        case small
    }

    let symbol: String
    let label: String
    let help: String
    let size: Size
    let tint: Color
    let action: @MainActor () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    init(
        symbol: String,
        label: String,
        help: String? = nil,
        size: Size = .regular,
        tint: Color = KukuColor.textSecondary,
        action: @escaping @MainActor () -> Void
    ) {
        self.symbol = symbol
        self.label = label
        self.help = help ?? label
        self.size = size
        self.tint = tint
        self.action = action
    }

    var body: some View {
        let dimension = size == .regular ? KukuLayout.iconButton : KukuLayout.iconButtonSmall
        Button(action: action) {
            Image(systemName: symbol)
                .font(.kukuIcon(size == .regular ? .regular : .mini, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: dimension, height: dimension)
                .background(
                    isEnabled && hovering ? KukuColor.fillHover : Color.clear,
                    in: RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .opacity(isEnabled ? 1 : KukuState.disabledOpacity)
        .onHover { hovering = $0 }
        .animation(Motion.snappy, value: hovering)
        .accessibilityLabel(label)
        .help(help)
    }
}

// MARK: - Brand and live input

struct BrandMark: View {
    private static let size: CGFloat = 27

    var body: some View {
        Group {
            if let url = Bundle.appResources.url(forResource: "SayKuku", withExtension: "svg"),
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
        .foregroundStyle(KukuColor.coral)
        .frame(width: Self.size, height: Self.size)
        .accessibilityLabel("SayKuku")
    }
}

/// Live or idle waveform. Coral only while recording; neutral for playback.
/// The idle wave holds still when Reduce Motion is on.
struct Waveform: View {
    var color: Color = KukuColor.coral
    var level: Double? = nil
    var barCount = 18
    var height: CGFloat = 26
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                .animation(Motion.meter, value: level)
            } else if reduceMotion {
                bars { idleBarHeight($0, at: 0) }
            } else {
                TimelineView(.animation(minimumInterval: 1 / 24)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    bars { idleBarHeight($0, at: t) }
                }
            }
        }
    }

    private func idleBarHeight(_ index: Int, at t: TimeInterval) -> CGFloat {
        let phase = Double(index) * 0.68
        let wave = (sin(t * 6.2 + phase) + sin(t * 3.3 - phase * 0.5)) * 0.22 + 0.52
        return max(3, height * wave)
    }

    private func bars(barHeight: @escaping (Int) -> CGFloat) -> some View {
        HStack(spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(index < barCount * 2 / 3 ? color : KukuColor.textTertiary.opacity(0.4))
                    .frame(width: 2.5, height: barHeight(index))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Page structure

/// Uppercased, so keep it to a word or two. Longer section titles read better as plain text.
struct SectionEyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.kuku(.caption, weight: .semibold))
            .tracking(KukuTypography.eyebrowTracking)
            .foregroundStyle(KukuColor.textSecondary)
    }
}

/// Page header: the page's name as the title, plus one line on what the page is for.
struct ScreenHeader<Accessory: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let accessory: Accessory

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: KukuSpacing.lg) {
            VStack(alignment: .leading, spacing: KukuSpacing.xs) {
                Text(title)
                    .font(.kuku(.largeTitle))
                    .foregroundStyle(KukuColor.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.kuku(.callout))
                        .foregroundStyle(KukuColor.textSecondary)
                }
            }
            Spacer(minLength: KukuSpacing.xl)
            accessory
        }
        .frame(maxWidth: KukuLayout.pageMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, KukuLayout.pageGutter)
        .padding(.top, KukuLayout.pageTop)
        .padding(.bottom, KukuLayout.headerBottom)
    }
}

extension ScreenHeader where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Keeps page content on the shared leading edge and maximum width.
struct KukuPageContent<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: KukuLayout.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, KukuLayout.pageGutter)
    }
}

/// Scrolling page body below the header, tabs and divider.
struct KukuPageScroll<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            KukuPageContent { content }
                .padding(.top, KukuLayout.contentTop)
                .padding(.bottom, KukuLayout.contentBottom)
        }
    }
}

/// Segmented control for a page's second-level navigation.
/// Only the selection indicator animates; the content below switches at once, like a native tab view.
struct KukuTabBar<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: KukuSpacing.xxs) {
            ForEach(items, id: \.self) { item in
                let isSelected = selection == item
                Button {
                    selection = item
                } label: {
                    Text(title(item))
                        .font(.kuku(.callout, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? KukuColor.textPrimary : KukuColor.textSecondary)
                        .padding(.horizontal, KukuSpacing.md)
                        .frame(minWidth: 68, minHeight: KukuLayout.controlHeight - 2 * KukuSpacing.xxs)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous)
                                    .fill(KukuColor.surfaceRaised)
                                    .kukuShadow(.raised)
                                    .matchedGeometryEffect(id: "indicator", in: indicator)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        // Scoped here so the indicator slides without animating the page it controls.
        .animation(Motion.snappy, value: selection)
        .padding(KukuSpacing.xxs)
        .background(KukuColor.fill, in: RoundedRectangle(cornerRadius: KukuLayout.radiusMedium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: KukuLayout.radiusMedium, style: .continuous)
                .strokeBorder(KukuColor.border, lineWidth: KukuBorder.width)
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
        .padding(.bottom, KukuLayout.tabsBottom)
    }
}

/// Hairline divider. Rows in a card inset it to the text; page and sheet dividers use `inset: 0`.
struct KukuDivider: View {
    var inset: CGFloat = KukuLayout.rowPadding

    var body: some View {
        Rectangle()
            .fill(KukuColor.separator)
            .frame(height: 1)
            .padding(.leading, inset)
            .accessibilityHidden(true)
    }
}

// MARK: - Groups and rows

/// An eyebrow over a card of rows, separated by `KukuDivider`.
struct KukuGroup<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KukuLayout.groupTitleSpacing) {
            if let title {
                SectionEyebrow(text: title)
                    .padding(.leading, KukuSpacing.xs)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .kukuSurface()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Title with an optional caption, in the sizes every row shares.
struct KukuRowLabel: View {
    let title: String
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: KukuSpacing.xxs) {
            Text(title)
                .font(.kuku(.body))
                .foregroundStyle(KukuColor.textPrimary)
            if let caption {
                Text(caption)
                    .font(.kuku(.subheadline))
                    .foregroundStyle(KukuColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Label above a form field or a group of choices in a sheet.
struct KukuFieldLabel: View {
    let text: String
    var isRequired = false

    var body: some View {
        HStack(spacing: KukuSpacing.xxs) {
            Text(text)
                .foregroundStyle(KukuColor.textPrimary)
            if isRequired {
                Text("*")
                    .foregroundStyle(KukuColor.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .font(.kuku(.subheadline, weight: .semibold))
    }
}

/// Standard full-width row: label on the leading edge, one control on the trailing edge.
struct KukuRow<Accessory: View>: View {
    let title: String
    let caption: String?
    @ViewBuilder let accessory: Accessory

    init(_ title: String, caption: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.caption = caption
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: KukuSpacing.md) {
            KukuRowLabel(title: title, caption: caption)
            Spacer(minLength: KukuSpacing.md)
            accessory
        }
        .kukuRowFrame(hasCaption: caption != nil)
    }
}

extension View {
    /// Padding and minimum height shared by every row in a `KukuGroup`, for rows that can't be a `KukuRow`.
    func kukuRowFrame(hasCaption: Bool = true) -> some View {
        self
            .padding(.horizontal, KukuLayout.rowPadding)
            .padding(.vertical, KukuSpacing.sm)
            .frame(
                maxWidth: .infinity,
                minHeight: hasCaption ? KukuLayout.rowMinHeightWithCaption : KukuLayout.rowMinHeight,
                alignment: .leading
            )
    }
}

struct KukuToggleRow: View {
    let title: String
    var caption: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        KukuRow(title, caption: caption) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

/// Coral when selected, tertiary otherwise: the only accent in a selectable row or card.
struct KukuSelectionIndicator: View {
    enum Style {
        /// One of several: radio rows.
        case radio
        /// Any of several: choice cards, import suggestions.
        case checkbox
    }

    var style: Style = .checkbox
    let isSelected: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.kukuIcon(.medium))
            .foregroundStyle(isSelected ? KukuColor.coral : KukuColor.textTertiary)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }

    private var symbol: String {
        switch style {
        case .radio: isSelected ? "largecircle.fill.circle" : "circle"
        case .checkbox: isSelected ? "checkmark.circle.fill" : "circle"
        }
    }
}

/// Radio row inside a `KukuGroup`.
struct KukuChoiceRow: View {
    let title: String
    var caption: String? = nil
    let isSelected: Bool
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: KukuSpacing.md) {
                KukuSelectionIndicator(style: .radio, isSelected: isSelected)
                KukuRowLabel(title: title, caption: caption)
                Spacer(minLength: 0)
            }
            .kukuRowFrame(hasCaption: caption != nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension View {
    /// Surface for a card that responds to hover or selection: a neutral selected fill and a stronger outline, never a tint.
    func kukuInteractiveSurface(isSelected: Bool = false) -> some View {
        modifier(KukuInteractiveSurfaceModifier(isSelected: isSelected))
    }
}

private struct KukuInteractiveSurfaceModifier: ViewModifier {
    let isSelected: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: KukuLayout.radiusMedium, style: .continuous)
        content
            .background {
                ZStack {
                    shape.fill(KukuColor.surface)
                    shape.fill(isSelected ? KukuColor.selectedFill : (isEnabled && hovering ? KukuColor.rowHover : Color.clear))
                }
            }
            .overlay {
                shape.strokeBorder(isSelected ? KukuColor.borderStrong : KukuColor.border, lineWidth: KukuBorder.width)
            }
            .contentShape(shape)
            .onHover { hovering = $0 }
            .animation(Motion.snappy, value: hovering)
            .animation(Motion.snappy, value: isSelected)
    }
}

// MARK: - Lists

extension View {
    /// A plain `List` on the page canvas: no system background, rows only as tall as their content.
    func kukuList() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
    }

    /// A row of a `kukuList()`. The row draws its own background and dividers; `insets` sets the spacing.
    func kukuListRow(_ insets: EdgeInsets = EdgeInsets()) -> some View {
        listRowInsets(insets)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

extension Array where Element: Identifiable {
    /// The item to select once `id` is removed: the next one, or the previous one at the end.
    func selectionAfterRemoving(_ id: Element.ID) -> Element.ID? {
        guard let index = firstIndex(where: { $0.id == id }) else { return nil }
        let neighbor = index + 1 < count ? index + 1 : index - 1
        return indices.contains(neighbor) ? self[neighbor].id : nil
    }
}

// MARK: - Labels and indicators

/// Neutral capsule for categories and states. A tone only colors the optional icon.
struct KukuBadge: View {
    let text: String
    var tone: KukuStatusTone = .neutral
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: KukuSpacing.xs) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.kukuIcon(.mini, weight: .semibold))
                    .foregroundStyle(tone.iconColor)
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.kuku(.caption, weight: .semibold))
        .foregroundStyle(KukuColor.textSecondary)
        .padding(.horizontal, KukuSpacing.sm)
        .frame(minHeight: KukuLayout.badgeHeight)
        .background(KukuColor.fill, in: Capsule())
    }
}

/// Status line: a tone-colored icon followed by primary text. Used for connection state, inline errors and warnings.
struct KukuStatusLabel: View {
    let text: String
    let tone: KukuStatusTone
    var symbol: String? = nil
    var font: Font = .kuku(.subheadline)

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(KukuColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol ?? tone.symbol)
                .foregroundStyle(tone.iconColor)
        }
        .font(font)
    }
}

/// A key or shortcut, such as Fn or ⌃⌥⌘V.
struct KukuKeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.kuku(.caption, weight: .semibold))
            .foregroundStyle(KukuColor.textSecondary)
            .padding(.horizontal, KukuSpacing.iconText)
            .frame(minWidth: KukuLayout.badgeHeight, minHeight: KukuLayout.badgeHeight)
            .background(KukuColor.fill, in: RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous)
                    .strokeBorder(KukuColor.border, lineWidth: KukuBorder.width)
            }
    }
}

/// Neutral square behind a row or header icon. Decorative, so hidden from VoiceOver.
struct KukuIconTile: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.kukuIcon(.medium))
            .foregroundStyle(KukuColor.textSecondary)
            .frame(width: KukuLayout.iconTile, height: KukuLayout.iconTile)
            .background(KukuColor.fill, in: RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Fields

extension View {
    /// Field chrome shared by search and text fields: raised fill, hairline, coral focus ring.
    func kukuFieldChrome(isFocused: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous)
        return self
            .background(KukuColor.surfaceRaised, in: shape)
            .overlay {
                shape.strokeBorder(
                    isFocused ? KukuColor.focusRing : KukuColor.border,
                    lineWidth: isFocused ? KukuBorder.focusWidth : KukuBorder.width
                )
            }
            .animation(Motion.snappy, value: isFocused)
    }

    /// Plain `TextField` or `SecureField` in the shared chrome. The caller owns the focus state.
    func kukuField(isFocused: Bool) -> some View {
        self
            .textFieldStyle(.plain)
            .font(.kuku(.body))
            .padding(.horizontal, KukuSpacing.md)
            .frame(maxWidth: .infinity, minHeight: KukuLayout.controlHeight, alignment: .leading)
            .kukuFieldChrome(isFocused: isFocused)
    }
}

struct KukuSearchField: View {
    let prompt: String
    /// Spoken and tooltip label for the clear button.
    let clearLabel: String
    @Binding var text: String
    let width: CGFloat?
    /// Lets the page move focus here, e.g. from Find (⌘F). Without it the field keeps its own focus state.
    let focus: FocusState<Bool>.Binding?
    /// Runs after Esc clears the field, so the page can hand focus back to its content.
    let onExit: (@MainActor () -> Void)?
    @FocusState private var ownFocus: Bool

    /// `width: nil` fills the available width.
    init(
        prompt: String,
        clearLabel: String,
        text: Binding<String>,
        width: CGFloat? = KukuLayout.searchFieldWidth,
        focus: FocusState<Bool>.Binding? = nil,
        onExit: (@MainActor () -> Void)? = nil
    ) {
        self.prompt = prompt
        self.clearLabel = clearLabel
        _text = text
        self.width = width
        self.focus = focus
        self.onExit = onExit
    }

    private var isFocused: FocusState<Bool>.Binding { focus ?? $ownFocus }

    var body: some View {
        HStack(spacing: KukuSpacing.iconText) {
            Image(systemName: "magnifyingglass")
                .font(.kukuIcon(.small))
                .foregroundStyle(KukuColor.textSecondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.kuku(.callout))
                .focused(isFocused)
                .onExitCommand { clearAndLeave() }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.kukuIcon(.small))
                        .foregroundStyle(KukuColor.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(clearLabel)
                .help(clearLabel)
            }
        }
        .padding(.horizontal, KukuSpacing.md)
        .frame(width: width)
        .frame(minHeight: KukuLayout.controlHeight)
        .kukuFieldChrome(isFocused: isFocused.wrappedValue)
    }

    /// Esc clears the search and leaves the field, like the system search fields.
    private func clearAndLeave() {
        text = ""
        isFocused.wrappedValue = false
        onExit?()
    }
}

private struct SearchFieldFocusKey: FocusedValueKey {
    typealias Value = FocusState<Bool>.Binding
}

extension FocusedValues {
    /// Focus of the current page's search field, published for Find (⌘F).
    var searchFieldFocus: FocusState<Bool>.Binding? {
        get { self[SearchFieldFocusKey.self] }
        set { self[SearchFieldFocusKey.self] = newValue }
    }
}

/// Text input that owns its focus, for forms and custom values.
struct KukuTextField: View {
    let prompt: String
    @Binding var text: String
    let multiline: Bool
    let autoFocus: Bool
    let onSubmit: (@MainActor () -> Void)?
    @FocusState private var isFocused: Bool

    init(
        prompt: String,
        text: Binding<String>,
        multiline: Bool = false,
        autoFocus: Bool = false,
        onSubmit: (@MainActor () -> Void)? = nil
    ) {
        self.prompt = prompt
        _text = text
        self.multiline = multiline
        self.autoFocus = autoFocus
        self.onSubmit = onSubmit
    }

    var body: some View {
        Group {
            if multiline {
                TextField(prompt, text: $text, axis: .vertical)
                    .lineLimit(2...4)
                    .padding(.vertical, KukuSpacing.sm)
                    // Two lines of body text plus vertical padding.
                    .frame(minHeight: 56, alignment: .topLeading)
            } else {
                TextField(prompt, text: $text)
            }
        }
        .focused($isFocused)
        .onSubmit { onSubmit?() }
        .kukuField(isFocused: isFocused)
        .onAppear {
            if autoFocus { isFocused = true }
        }
    }
}

/// Pop-up choice drawn in the field chrome. The menu itself stays native, with a check on the current option.
/// `extra` adds items below the options, such as a Custom… entry.
struct KukuPicker<Option: Hashable, Extra: View>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String
    @ViewBuilder let extra: Extra

    init(
        _ title: String,
        options: [Option],
        selection: Binding<Option>,
        label: @escaping (Option) -> String,
        @ViewBuilder extra: () -> Extra
    ) {
        self.title = title
        self.options = options
        _selection = selection
        self.label = label
        self.extra = extra()
    }

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option)).tag(option)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            extra
        } label: {
            HStack(spacing: KukuSpacing.sm) {
                Text(label(selection))
                    .foregroundStyle(KukuColor.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.kukuIcon(.mini, weight: .semibold))
                    .foregroundStyle(KukuColor.textSecondary)
            }
            .font(.kuku(.body))
            .padding(.horizontal, KukuSpacing.md)
            .frame(width: KukuLayout.pickerWidth)
            .frame(minHeight: KukuLayout.controlHeight)
            .kukuFieldChrome(isFocused: false)
            .contentShape(Rectangle())
        }
        // A plain button style lets the menu draw this label instead of a system pop-up button.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(title)
        .accessibilityValue(label(selection))
    }
}

extension KukuPicker where Extra == EmptyView {
    init(_ title: String, options: [Option], selection: Binding<Option>, label: @escaping (Option) -> String) {
        self.init(title, options: options, selection: selection, label: label) { EmptyView() }
    }
}

// MARK: - Empty states

/// `ContentUnavailableView` at the shared minimum height, never tinted.
struct KukuEmptyState<Actions: View>: View {
    let title: String
    let symbol: String
    let message: String
    @ViewBuilder let actions: Actions

    init(title: String, symbol: String, message: String, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.symbol = symbol
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            actions
        }
        .frame(maxWidth: .infinity, minHeight: KukuLayout.emptyStateMinHeight)
    }
}

extension KukuEmptyState where Actions == EmptyView {
    init(title: String, symbol: String, message: String) {
        self.init(title: title, symbol: symbol, message: message) { EmptyView() }
    }
}

// MARK: - Sheets

/// Standard sheet header: icon tile, optional eyebrow, title and a one-sentence description.
/// Sheets close from their footer buttons, so the header has no close button.
struct KukuSheetHeader<Icon: View>: View {
    var eyebrow: String? = nil
    let title: String
    let description: String
    @ViewBuilder let icon: Icon

    var body: some View {
        HStack(alignment: .top, spacing: KukuSpacing.md) {
            icon
                .accessibilityHidden(true)
                .frame(width: KukuLayout.iconTileLarge, height: KukuLayout.iconTileLarge)
                .background(
                    KukuColor.fill,
                    in: RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous)
                )

            VStack(alignment: .leading, spacing: KukuSpacing.xs) {
                if let eyebrow {
                    SectionEyebrow(text: eyebrow)
                }
                Text(title)
                    .font(.kuku(.title))
                    .foregroundStyle(KukuColor.textPrimary)
                Text(description)
                    .font(.kuku(.callout))
                    .foregroundStyle(KukuColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: KukuSpacing.lg)
        }
        .padding(.horizontal, KukuLayout.sheetPadding)
        .padding(.top, KukuSpacing.xl)
        .padding(.bottom, KukuSpacing.lg)
    }
}

/// SF Symbol drawn in the sheet header's icon tile.
struct KukuSheetIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.kukuIcon(.large))
            .foregroundStyle(KukuColor.textSecondary)
    }
}

/// Caption on the leading side of a sheet footer: a quiet hint or an inline error.
struct KukuSheetNote: View {
    let text: String
    var isError = false

    var body: some View {
        Group {
            if isError {
                KukuStatusLabel(text: text, tone: .danger)
            } else {
                Text(text)
                    .font(.kuku(.subheadline))
                    .foregroundStyle(KukuColor.textSecondary)
            }
        }
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Sheet footer: an optional note on the leading side, then secondary and primary buttons.
/// Put a `KukuDivider(inset: 0)` above it.
struct KukuSheetFooter<Buttons: View>: View {
    let note: KukuSheetNote?
    @ViewBuilder let buttons: Buttons

    init(note: KukuSheetNote? = nil, @ViewBuilder buttons: () -> Buttons) {
        self.note = note
        self.buttons = buttons()
    }

    var body: some View {
        HStack(spacing: KukuSpacing.sm) {
            if let note { note }
            Spacer(minLength: KukuSpacing.md)
            buttons
        }
        .padding(.horizontal, KukuLayout.sheetPadding)
        .padding(.vertical, KukuSpacing.lg)
    }
}

/// Accent-colored link that opens a page in the browser.
struct KukuExternalLink: View {
    let title: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            Label(title, systemImage: "arrow.up.right.square")
        }
        .font(.kuku(.subheadline, weight: .medium))
        .foregroundStyle(KukuColor.accentText)
    }
}

// MARK: - Feedback

/// Visual body of the in-window toast. The owner posts the VoiceOver announcement.
struct KukuToast: View {
    let text: String
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.kuku(.callout, weight: .semibold))
            .foregroundStyle(KukuColor.toastText)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, KukuSpacing.lg)
            .padding(.vertical, KukuSpacing.sm)
            .frame(minHeight: KukuLayout.controlHeight)
            .background(
                KukuColor.toastSurface,
                in: RoundedRectangle(cornerRadius: KukuLayout.radiusLarge, style: .continuous)
            )
            .kukuShadow(.floating)
    }
}
