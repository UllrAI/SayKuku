import AppKit
import SwiftUI

struct MemoryView: View {
    @Environment(AppState.self) private var appState
    @Binding var selectedScope: MemoryScope

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                title: appState.text("记忆", "Memory"),
                subtitle: appState.text(
                    "纠正建议经你确认才会进入知识；最近对话 30 分钟后自动清除。",
                    "Corrections go into Knowledge only after you approve them. Recent conversations clear after 30 minutes."
                )
            )

            KukuPageTabs(
                items: MemoryScope.allCases,
                selection: $selectedScope,
                title: { $0.title(appState) }
            )

            KukuDivider(inset: 0)

            KukuPageScroll {
                VStack(spacing: KukuLayout.listSpacing) {
                    if selectedScope == .corrections {
                        let pending = appState.corrections.filter { $0.status == .pending }
                        if pending.isEmpty {
                            correctionsEmptyView
                        } else {
                            CorrectionSummary(pendingCount: pending.count)
                            ForEach(pending) { item in
                                CorrectionRow(item: item)
                            }
                        }
                    } else {
                        SessionMemoryView()
                    }
                }
            }
            // Each tab opens at the top instead of at the last tab's scroll offset.
            .id(selectedScope)
        }
    }

    @ViewBuilder
    private var correctionsEmptyView: some View {
        if appState.learnFromCorrections {
            KukuEmptyState(
                title: appState.text("还没有纠正建议", "No correction suggestions yet"),
                symbol: "sparkles",
                message: appState.text(
                    "改正识别错的词后，SayKuku 会在这里给出建议，确认后才会保存。",
                    "When you fix a word SayKuku got wrong, a suggestion shows up here. Nothing is saved until you approve it."
                )
            )
        } else {
            FeatureOffView(
                title: appState.text("已关闭“从纠正中学习”", "Learning from corrections is off"),
                message: appState.text(
                    "开启后，你改正的识别结果会作为建议出现在这里。",
                    "Turn it on to see suggestions from words you fix."
                ),
                systemImage: "sparkles"
            ) { appState.learnFromCorrections = true }
        }
    }
}

/// Empty state for a tab whose feature is turned off, with a way to turn it back on.
private struct FeatureOffView: View {
    @Environment(AppState.self) private var appState
    let title: String
    let message: String
    let systemImage: String
    let turnOn: () -> Void

    var body: some View {
        KukuEmptyState(title: title, symbol: systemImage, message: message) {
            Button(appState.text("开启", "Turn On"), action: turnOn)
                .buttonStyle(.kukuPrimary)
        }
    }
}

private struct CorrectionSummary: View {
    @Environment(AppState.self) private var appState
    let pendingCount: Int

    var body: some View {
        HStack(spacing: KukuSpacing.md) {
            KukuIconTile(symbol: "wand.and.stars")
            VStack(alignment: .leading, spacing: KukuSpacing.xxs) {
                Text(appState.text("纠正建议", "Correction suggestions"))
                    .font(.kuku(.headline))
                    .foregroundStyle(KukuColor.textPrimary)
                Text(appState.text(
                    "有 \(pendingCount) 条建议待确认，确认后才会保存。",
                    pendingCount == 1
                        ? "1 suggestion needs your review before it’s saved."
                        : "\(pendingCount) suggestions need your review before they’re saved."
                ))
                    .font(.kuku(.subheadline))
                    .foregroundStyle(KukuColor.textSecondary)
            }
        }
        .kukuCard()
    }
}

private struct CorrectionRow: View {
    @Environment(AppState.self) private var appState
    let item: CorrectionRecord

    var body: some View {
        HStack(spacing: KukuSpacing.md) {
            VStack(alignment: .leading, spacing: KukuSpacing.sm) {
                HStack(spacing: KukuSpacing.sm) {
                    Text(item.raw)
                        .strikethrough()
                        .foregroundStyle(KukuColor.textSecondary)
                    Image(systemName: "arrow.right")
                        .font(.kukuIcon(.small, weight: .semibold))
                        .foregroundStyle(KukuColor.textTertiary)
                    Text(item.corrected)
                        .fontWeight(.semibold)
                        .foregroundStyle(KukuColor.textPrimary)
                }
                .font(.kuku(.title3, weight: .regular))
                Text(appState.text(
                    "累计纠正 \(item.count) 次 · 最近在 \(item.lastApp)",
                    "Corrected \(item.count == 1 ? "once" : "\(item.count) times") · Last in \(item.lastApp)"
                ))
                    .font(.kuku(.caption))
                    .foregroundStyle(KukuColor.textSecondary)
            }
            Spacer()
            Button(appState.text("忽略", "Ignore")) {
                withAnimation(Motion.snappy) { appState.ignoreCorrection(item.id) }
                appState.showToast(appState.text("已忽略这条建议", "Suggestion ignored"), symbol: "xmark.circle")
            }
            .buttonStyle(.kukuSecondary)
            Button(appState.text("加入知识", "Add to Knowledge")) {
                withAnimation(Motion.spring) { appState.acceptCorrection(item.id) }
                appState.showToast(appState.text("已加入知识", "Added to Knowledge"), symbol: "checkmark.circle.fill")
            }
            .buttonStyle(.kukuSecondary)
        }
        .kukuCard()
    }
}

private struct SessionMemoryView: View {
    @Environment(AppState.self) private var appState
    @State private var confirmingClear = false

    var body: some View {
        // Refresh each minute so remaining times count down and expired turns drop out.
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let items = appState.sessions
            .filter { $0.expiresAt > now }
            .sorted { $0.createdAt > $1.createdAt }
        if items.isEmpty {
            emptyView
        } else {
            VStack(alignment: .leading, spacing: KukuSpacing.md) {
                HStack(spacing: KukuSpacing.md) {
                    Text(appState.text(
                        "在同一个 App 中再次使用语音 Agent 时，会参考这些对话，30 分钟后自动清除。",
                        "Voice Agent uses these in the same app. They’re cleared after 30 minutes."
                    ))
                        .font(.kuku(.subheadline))
                        .foregroundStyle(KukuColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: KukuSpacing.md)
                    Button(appState.text("全部清除…", "Clear All…")) { confirmingClear = true }
                        .buttonStyle(.kukuSecondary)
                }

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, session in
                        SessionRow(session: session, isLatest: index == 0, isLast: index == items.count - 1, now: now)
                    }
                }
                .kukuCard()
            }
            .confirmationDialog(
                appState.text("清除全部最近对话？", "Clear all recent conversations?"),
                isPresented: $confirmingClear,
                titleVisibility: .visible
            ) {
                Button(appState.text("全部清除", "Clear All"), role: .destructive) {
                    withAnimation(Motion.snappy) { appState.clearSessions() }
                    appState.showToast(appState.text("已清除最近对话", "Recent conversations cleared"), symbol: "trash")
                }
                Button(appState.text("取消", "Cancel"), role: .cancel) {}
            } message: {
                Text(appState.text(
                    "清除后语音 Agent 不会再参考这些对话，且无法恢复。",
                    "Voice Agent will stop using them. This can’t be undone."
                ))
            }
        }
    }

    @ViewBuilder
    private var emptyView: some View {
        if appState.continuousConversation {
            KukuEmptyState(
                title: appState.text("还没有最近对话", "No recent conversations yet"),
                symbol: "clock.arrow.circlepath",
                message: appState.text(
                    "使用语音 Agent 后，最近的对话会在这里保留 30 分钟。",
                    "Your recent Voice Agent conversations stay here for 30 minutes."
                )
            )
        } else {
            FeatureOffView(
                title: appState.text("已关闭“连续对话”", "Continuous conversation is off"),
                message: appState.text(
                    "开启后，语音 Agent 会记住同一个 App 中最近的对话。",
                    "Turn it on so Voice Agent remembers recent conversations in the same app."
                ),
                systemImage: "clock.arrow.circlepath"
            ) { appState.continuousConversation = true }
        }
    }
}

private struct SessionRow: View {
    @Environment(AppState.self) private var appState
    let session: AgentSession
    let isLatest: Bool
    let isLast: Bool
    let now: Date

    private var minutesLeft: Int {
        max(1, Int((session.expiresAt.timeIntervalSince(now) / 60).rounded(.up)))
    }

    var body: some View {
        HStack(alignment: .top, spacing: KukuSpacing.md) {
            Circle()
                .fill(isLatest ? KukuColor.textSecondary : KukuColor.borderStrong)
                .frame(width: KukuLayout.statusDot, height: KukuLayout.statusDot)
                // Centers the dot on the headline's first line.
                .padding(.top, KukuSpacing.xs)
            VStack(alignment: .leading, spacing: KukuSpacing.xxs) {
                Text(appName(for: session.app))
                    .font(.kuku(.headline))
                    .foregroundStyle(KukuColor.textPrimary)
                if !session.userCommand.isEmpty {
                    Text(session.userCommand)
                        .font(.kuku(.callout))
                        .foregroundStyle(KukuColor.textPrimary)
                        .lineLimit(2)
                }
                if !session.response.isEmpty {
                    Text(session.response)
                        .font(.kuku(.subheadline))
                        .foregroundStyle(KukuColor.textSecondary)
                        .lineSpacing(KukuTypography.paragraphSpacing)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: KukuSpacing.md)
            Text(appState.text("还剩 \(minutesLeft) 分钟", "Expires in \(minutesLeft) min"))
                .font(.kuku(.caption))
                .monospacedDigit()
                .foregroundStyle(KukuColor.textSecondary)
        }
        .padding(.bottom, isLast ? 0 : KukuSpacing.md)
        .background(alignment: .topLeading) {
            // Timeline line from this dot down to the next one, whatever the row height.
            if !isLast {
                Rectangle()
                    .fill(KukuColor.separator)
                    .frame(width: KukuBorder.width)
                    .padding(.top, KukuSpacing.xs + KukuLayout.statusDot + KukuSpacing.xs)
                    .padding(.leading, (KukuLayout.statusDot - KukuBorder.width) / 2)
            }
        }
    }

    /// Sessions store the bundle ID; show the app's name when it can be resolved.
    private func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        let name = FileManager.default.displayName(atPath: url.path(percentEncoded: false))
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

enum MemoryScope: String, CaseIterable, Identifiable {
    case corrections, shortTerm
    var id: String { rawValue }
    @MainActor func title(_ appState: AppState) -> String {
        switch self {
        case .corrections: appState.text("纠正", "Corrections")
        case .shortTerm: appState.text("短期", "Short-Term")
        }
    }
}
