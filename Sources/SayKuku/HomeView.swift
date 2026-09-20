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

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                eyebrow: appState.text("快速开始", "Quick start"),
                title: appState.text("在当前输入框，直接开口", "Speak right where you type"),
                subtitle: appState.text("无需打开 SayKuku 窗口，使用 Fn 即可随时输入。", "Keep this window closed—Fn is always ready.")
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

                    Label(
                        appState.text("语音仅在你主动触发后发送", "Audio is sent only when you invoke it"),
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
            title: "Voice Input",
            subtitle: appState.text("按住说话，松开后写入当前光标", "Hold to speak, release to type"),
            symbol: "mic.fill",
            accent: KukuColor.coral
        ) {
            appState.startDictation()
        }
    }

    private var voiceAgentCard: some View {
        HomeGestureRow(
            key: "Fn Fn",
            title: "Voice Agent",
            subtitle: appState.text("说出意图，识别后直接执行或写回", "Say an intent to run it or write it back"),
            symbol: "sparkles",
            accent: KukuColor.graphite
        ) {
            appState.startAgent()
        }
    }
}

private struct HomeGestureRow: View {
    @Environment(AppState.self) private var appState
    let key: String
    let title: String
    let subtitle: String
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
                        .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                    Spacer()

                    Text(key)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(Color.black.opacity(0.055), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(KukuColor.stone)
                        .lineLimit(2)
                }

                HStack(spacing: 5) {
                    Text(appState.text("开始", "Open"))
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(accent.opacity(hovering ? 1 : 0.72))
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .background(hovering ? Color.white.opacity(0.32) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .kukuSurface(radius: KukuLayout.radiusLarge, elevated: true)
        .onHover { hovering = $0 }
        .animation(Motion.snappy, value: hovering)
    }
}

struct AgentPill: View {
    @Environment(AppState.self) private var appState
    @State private var showingContext = false

    private var width: CGFloat {
        switch appState.agentPhase {
        case .hidden: 0
        case .listening: appState.liveTranscript.isEmpty ? 216 : 360
        case .copyReady: 360
        case .transcribing, .processing: 132
        case .result: 88
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            if appState.agentPhase == .copyReady {
                CopyFallbackContent()
            } else if appState.agentPhase == .listening {
                Button(action: appState.dismissAgent) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .frame(width: 26, height: 26)
                        .background { Circle().fill(Color.white.opacity(0.09)) }
                }
                .buttonStyle(PressScaleStyle())

                Waveform(barCount: 5, height: 15)
                    .frame(width: 22)

                Text(!appState.liveTranscript.isEmpty ? appState.liveTranscript : appState.agentCommand)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button { showingContext.toggle() } label: {
                    Image(systemName: "scope")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .frame(width: 22, height: 26)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingContext, arrowEdge: .bottom) {
                    AgentContextPopover()
                }

                Button(action: appState.finishAgentListening) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background { Circle().fill(KukuColor.coral) }
                }
                .buttonStyle(PressScaleStyle())
            } else if appState.agentPhase == .transcribing || appState.agentPhase == .processing {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text(appState.agentPhase == .transcribing
                     ? appState.text("正在理解…", "Understanding…")
                     : appState.text("正在执行…", "Running…"))
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            } else if appState.agentPhase == .result {
                Label(appState.text("已完成", "Done"), systemImage: "checkmark")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(KukuColor.mint)
            }
        }
        .contentTransition(.interpolate)
        .animation(Motion.snappy, value: appState.agentPhase)
        .animation(Motion.snappy, value: appState.liveTranscript.isEmpty)
        .padding(.horizontal, 7)
        .frame(width: width, height: appState.agentPhase == .result ? 30 : 40)
        .background { Capsule().fill(KukuColor.graphite.opacity(0.98)) }
        .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.16), radius: 16, y: 7)
        .animation(Motion.pill, value: width)
    }
}

private struct AgentContextPopover: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appState.text("本次使用的上下文", "Context used this time"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(KukuColor.stone)

            ForEach(appState.contextItems) { item in
                HStack(spacing: 9) {
                    Image(systemName: item.symbol)
                        .foregroundStyle(KukuColor.coral)
                        .frame(width: 16)
                    Text(item.title.replacingOccurrences(
                        of: "28 字",
                        with: appState.text("28 字", "28 chars")
                    ))
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    if appState.agentPhase == .listening {
                        Button {
                            appState.contextItems.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(KukuColor.stone)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 230)
    }
}

struct DictationPill: View {
    @Environment(AppState.self) private var appState

    private var width: CGFloat {
        switch appState.dictationPhase {
        case .idle: 0
        case .listening: appState.liveTranscript.isEmpty ? 166 : 320
        case .copyReady: 360
        case .processing: appState.liveTranscript.isEmpty ? 132 : 320
        case .success: 88
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            switch appState.dictationPhase {
            case .idle:
                EmptyView()
            case .listening:
                Waveform(barCount: 6, height: 16)
                Text(appState.liveTranscript.isEmpty
                     ? appState.text("正在听…", "Listening…")
                     : appState.liveTranscript)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button(action: appState.finishDictation) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 25, height: 25)
                        .background(KukuColor.coral, in: Circle())
                        .foregroundStyle(.white)
                }
                .buttonStyle(PressScaleStyle())
            case .processing:
                ProgressView().controlSize(.small)
                Text(appState.liveTranscript.isEmpty
                     ? appState.text("正在整理…", "Formatting…")
                     : appState.liveTranscript)
                    .lineLimit(1)
            case .success:
                Image(systemName: "checkmark")
                Text(appState.text("已输入", "Done"))
            case .copyReady:
                CopyFallbackContent()
            }
        }
        .contentTransition(.interpolate)
        .animation(Motion.snappy, value: appState.dictationPhase)
        .animation(Motion.snappy, value: appState.liveTranscript.isEmpty)
        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
        .foregroundStyle(appState.dictationPhase == .success ? KukuColor.mint : KukuColor.ink)
        .padding(.horizontal, 10)
        .frame(width: width, height: appState.dictationPhase == .copyReady ? 40 : 34)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Color.white.opacity(0.5), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.76), lineWidth: 0.8))
        .shadow(color: Color.black.opacity(0.1), radius: 10, y: 4)
        .animation(Motion.pill, value: width)
    }
}

private struct CopyFallbackContent: View {
    @Environment(AppState.self) private var appState

    private var darkBackground: Bool { appState.agentPhase == .copyReady }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .foregroundStyle(KukuColor.coral)
            Text(appState.pendingCopyText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Button(action: appState.copyPendingText) {
                Label(appState.text("复制", "Copy"), systemImage: "doc.on.doc")
                    .font(.system(size: 10.5, weight: .semibold))
                    .padding(.horizontal, 9)
                    .frame(height: 25)
                    .background(Color.white.opacity(darkBackground ? 0.12 : 0.65), in: Capsule())
            }
            .buttonStyle(.plain)
            Button(action: appState.dismissCopyFallback) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 25, height: 25)
                    .background(Color.white.opacity(darkBackground ? 0.1 : 0.65), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
        .foregroundStyle(darkBackground ? Color.white : KukuColor.ink)
        .frame(maxWidth: .infinity)
    }
}
