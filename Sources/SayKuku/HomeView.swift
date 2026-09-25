import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @State private var practiceText = ""
    @FocusState private var practiceFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                title: localized("Quick Start"),
                subtitle: localized("Press Fn in any text field. No need to open SayKuku.")
            )

            Spacer()
                .frame(height: KukuSpacing.xxxl)

            KukuPageContent {
                VStack(alignment: .leading, spacing: KukuSpacing.md) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: KukuSpacing.md) {
                            voiceInputCard
                            voiceAgentCard
                        }

                        VStack(spacing: KukuSpacing.md) {
                            voiceInputCard
                            voiceAgentCard
                        }
                    }

                    VStack(alignment: .leading, spacing: KukuSpacing.sm) {
                        Text(localized("Try it here"))
                            .font(.kuku(.headline))
                            .foregroundStyle(KukuColor.textPrimary)
                        Text(localized(
                            "Click here and press Fn to talk. Select text and press Fn twice to have Voice Agent rewrite it."
                        ))
                        .font(.kuku(.subheadline))
                        .foregroundStyle(KukuColor.textSecondary)
                        TextEditor(text: $practiceText)
                            .focused($practiceFocused)
                            .font(.kuku(.body))
                            .scrollContentBackground(.hidden)
                            // About three lines of body text.
                            .frame(height: 70)
                            .padding(KukuSpacing.sm)
                            .kukuFieldChrome(isFocused: practiceFocused)
                            .accessibilityLabel(localized("Voice practice field"))
                    }
                    .kukuCard(radius: KukuLayout.radiusLarge)

                    Label(
                        localized("SayKuku only records and sends audio after you press Fn or your shortcut"),
                        systemImage: "lock.fill"
                    )
                    .font(.kuku(.subheadline))
                    .foregroundStyle(KukuColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            Spacer(minLength: KukuSpacing.xxxl)
        }
    }

    private var voiceInputCard: some View {
        HomeGestureRow(
            key: "Fn",
            title: appState.voiceInputTitle,
            subtitle: appState.inputMode == .hold
                ? localized("Hold to talk, release to insert")
                : localized("Tap to start, tap again to insert"),
            shortcut: appState.globalShortcut(for: .voiceInput),
            symbol: "mic.fill"
        ) {
            practiceFocused = true
        }
    }

    private var voiceAgentCard: some View {
        HomeGestureRow(
            key: "Fn Fn",
            title: appState.voiceAgentTitle,
            subtitle: localized("Rewrite selected text, ask questions, or open pages"),
            shortcut: appState.globalShortcut(for: .voiceAgent),
            symbol: "sparkles"
        ) {
            practiceFocused = true
        }
    }
}

private struct HomeGestureRow: View {
    @Environment(AppState.self) private var appState
    let key: String
    let title: String
    let subtitle: String
    /// The optional global shortcut, shown for people without an Fn key.
    let shortcut: GlobalShortcut?
    let symbol: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: KukuSpacing.md) {
                HStack {
                    KukuIconTile(symbol: symbol)
                    Spacer()
                    KukuKeyCap(text: key)
                }

                VStack(alignment: .leading, spacing: KukuSpacing.xs) {
                    Text(title)
                        .font(.kuku(.title3))
                        .foregroundStyle(KukuColor.textPrimary)
                    Text(subtitle)
                        .font(.kuku(.subheadline))
                        .foregroundStyle(KukuColor.textSecondary)
                        .lineLimit(2)
                }

                if let shortcut {
                    Text(localized("or \(shortcut.displayString)"))
                        .font(.kuku(.caption))
                        .foregroundStyle(KukuColor.textSecondary)
                }
            }
            .padding(KukuLayout.cardPadding)
            // Keeps both cards the same height when their subtitles wrap differently.
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .background(
                hovering ? KukuColor.rowHover : Color.clear,
                in: RoundedRectangle(cornerRadius: KukuLayout.radiusLarge, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .kukuSurface(radius: KukuLayout.radiusLarge, elevated: true)
        .onHover { hovering = $0 }
        .animation(Motion.snappy, value: hovering)
    }
}
