import SwiftUI

struct HomeView: View {
    var body: some View {
        ZStack {
            KukuColor.canvas.ignoresSafeArea()
            HomeReadyState()
        }
    }
}

private struct HomeReadyState: View {
    @Environment(AppState.self) private var appState
    @State private var practiceText = ""
    @FocusState private var practiceFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                eyebrow: appState.text("快速开始", "Quick start"),
                title: appState.text("在当前输入框，直接开口", "Speak right where you type"),
                subtitle: appState.text("在任意输入框按 Fn 即可，不用打开 SayKuku。", "Press Fn in any text field. No need to open SayKuku.")
            )

            Spacer()
                .frame(height: 46)

            KukuPageContent {
                VStack(alignment: .leading, spacing: 15) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            voiceInputCard
                            voiceAgentCard
                        }

                        VStack(spacing: 12) {
                            voiceInputCard
                            voiceAgentCard
                        }
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        Text(appState.text("试写区", "Try it here"))
                            .font(.system(size: 12, weight: .semibold))
                        Text(appState.text(
                            "点这里，按 Fn 说句话；选中文字后连按两次 Fn，让语音 Agent 改写。",
                            "Click here and press Fn to talk. Select text and press Fn twice to have Voice Agent rewrite it."
                        ))
                        .font(.system(size: 11))
                        .foregroundStyle(KukuColor.stone)
                        TextEditor(text: $practiceText)
                            .focused($practiceFocused)
                            .font(.system(size: 13))
                            .scrollContentBackground(.hidden)
                            .frame(height: 70)
                            .padding(8)
                            .background(KukuColor.canvas, in: RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous))
                            .accessibilityLabel(appState.text("语音试写区", "Voice practice field"))
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .kukuSurface(radius: KukuLayout.radiusLarge)

                    Label(
                        appState.text("只在你按下 Fn 或快捷键后才录音并发送", "SayKuku only records and sends audio after you press Fn or your shortcut"),
                        systemImage: "lock.fill"
                    )
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(KukuColor.stone)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            Spacer(minLength: 40)
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
            symbol: "mic.fill",
            accent: KukuColor.coral
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
            symbol: "sparkles",
            accent: KukuColor.ink
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
    let accent: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 34, height: 34)
                        .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous))

                    Spacer()

                    Text(key)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(KukuColor.shade.opacity(0.055), in: RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(KukuColor.stone)
                        .lineLimit(2)
                }

                if let shortcut {
                    Text(appState.text("或 \(shortcut.displayString)", "or \(shortcut.displayString)"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(KukuColor.stone)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .background(hovering ? KukuColor.highlight.opacity(0.32) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .kukuSurface(radius: KukuLayout.radiusLarge, elevated: true)
        .onHover { hovering = $0 }
        .animation(Motion.snappy, value: hovering)
    }
}
