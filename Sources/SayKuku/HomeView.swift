import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @State private var practiceText = ""
    @FocusState private var practiceFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                title: appState.text("快速开始", "Quick Start"),
                subtitle: appState.text("在任意输入框按 Fn 即可，不用打开 SayKuku。", "Press Fn in any text field. No need to open SayKuku.")
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
                        Text(appState.text("试写区", "Try it here"))
                            .font(.kuku(.headline))
                            .foregroundStyle(KukuColor.textPrimary)
                        Text(appState.text(
                            "点这里，按 Fn 说句话；选中文字后连按两次 Fn，让语音 Agent 改写。",
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
                            .accessibilityLabel(appState.text("语音试写区", "Voice practice field"))
                    }
                    .kukuCard(radius: KukuLayout.radiusLarge)

                    Label(
                        appState.text("只在你按下 Fn 或快捷键后才录音并发送", "SayKuku only records and sends audio after you press Fn or your shortcut"),
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
                ? appState.text("按住说话，松开即输入", "Hold to talk, release to insert")
                : appState.text("单击开始说话，再单击即输入", "Tap to start, tap again to insert"),
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
            subtitle: appState.text("改写选中文字、提问或打开网页", "Rewrite selected text, ask questions, or open pages"),
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
                    Text(appState.text("或 \(shortcut.displayString)", "or \(shortcut.displayString)"))
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
