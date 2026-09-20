import SwiftUI

struct MemoryView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedScope: MemoryScope = .corrections

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            ScreenHeader(
                eyebrow: "Memory",
                title: appState.text("越用越准，但始终由你决定", "Gets better, always on your terms")
            ) {
                Toggle(appState.text("从纠正中学习", "Learn from corrections"), isOn: $appState.learnFromCorrections)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 11, weight: .medium))
            }

            KukuPageTabs(
                items: MemoryScope.allCases,
                selection: $selectedScope,
                title: { $0.title(appState) }
            )

            Divider().opacity(0.55)

            ScrollView {
                KukuPageContent {
                    VStack(spacing: 14) {
                        if selectedScope == .corrections {
                            CorrectionSummary()
                            ForEach(CorrectionSample.samples) { item in
                                CorrectionRow(item: item)
                            }
                        } else if selectedScope == .shortTerm {
                            SessionMemoryView()
                        } else {
                            LongTermMemoryView()
                        }
                    }
                }
                .padding(.vertical, 20)
            }
        }
    }
}

private struct CorrectionSummary: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(KukuColor.coralSoft)
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(KukuColor.coral)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(appState.text("本周识别准确率正在提升", "Recognition is improving this week"))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(appState.text(
                    "发现 3 组重复纠正，只有你确认后才会进入长期 Knowledge。",
                    "Three repeated corrections found. Only confirmed items enter long-term Knowledge."
                ))
                    .font(.system(size: 11))
                    .foregroundStyle(KukuColor.stone)
            }
            Spacer()
            Text("+8.4%")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(KukuColor.mint)
        }
        .padding(15)
        .kukuSurface(radius: KukuLayout.radiusMedium)
    }
}

private struct CorrectionRow: View {
    @Environment(AppState.self) private var appState
    let item: CorrectionSample
    @State private var resolved = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) {
                    Text(item.raw)
                        .strikethrough()
                        .foregroundStyle(KukuColor.stone)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(KukuColor.coral)
                    Text(item.corrected)
                        .fontWeight(.semibold)
                }
                .font(.system(size: 15, design: .rounded))
                Text(appState.text(
                    "过去 7 天纠正 \(item.count) 次 · 最近在 \(item.context)",
                    "Corrected \(item.count) times in 7 days · Last in \(item.context)"
                ))
                    .font(.system(size: 10))
                    .foregroundStyle(KukuColor.stone)
            }
            Spacer()
            if resolved {
                Label(appState.text("已加入", "Added"), systemImage: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(KukuColor.mint)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button(appState.text("忽略", "Ignore")) { withAnimation(Motion.snappy) { resolved = true } }
                    .buttonStyle(HoverFillButtonStyle())
                Button(appState.text("加入 Knowledge", "Add to Knowledge")) { withAnimation(Motion.spring) { resolved = true } }
                    .buttonStyle(TintButtonStyle())
            }
        }
        .padding(14)
        .kukuSurface(radius: KukuLayout.radiusMedium)
    }
}

private struct SessionMemoryView: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(SessionSample.samples.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 5) {
                        Circle()
                            .fill(index == 0 ? KukuColor.coral : KukuColor.stone.opacity(0.35))
                            .frame(width: 9, height: 9)
                        if index < SessionSample.samples.count - 1 {
                            Rectangle().fill(KukuColor.line).frame(width: 1, height: 52)
                        }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title)
                            .font(.system(size: 13, weight: .semibold))
                        Text(item.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(KukuColor.stone)
                            .lineSpacing(3)
                    }
                    Spacer()
                    Text(item.ttl)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(KukuColor.stone)
                }
            }
        }
        .padding(17)
        .kukuSurface(radius: KukuLayout.radiusMedium)
    }
}

private struct LongTermMemoryView: View {
    let groups = [
        ("固定拼写", "AniKuku · BifroMQ · WorkBuddy", "character.cursor.ibeam"),
        ("常用关系", "张越 → owns → AniKuku", "point.3.connected.trianglepath.dotted"),
        ("语言偏好", "中文输入优先使用全角标点", "textformat")
    ]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(groups, id: \.0) { group in
                HStack(spacing: 15) {
                    Image(systemName: group.2)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(KukuColor.coral)
                        .frame(width: 38, height: 38)
                        .background(KukuColor.coralSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.0).font(.system(size: 13, weight: .semibold))
                        Text(group.1).font(.system(size: 11)).foregroundStyle(KukuColor.stone)
                    }
                    Spacer()
                    Button { } label: { Image(systemName: "ellipsis") }
                        .buttonStyle(.plain)
                }
                .padding(14)
                .kukuSurface(radius: KukuLayout.radiusMedium)
            }
        }
    }
}

enum MemoryScope: String, CaseIterable, Identifiable {
    case corrections, shortTerm, longTerm
    var id: String { rawValue }
    @MainActor func title(_ appState: AppState) -> String {
        switch self {
        case .corrections: appState.text("纠正", "Corrections")
        case .shortTerm: appState.text("短期", "Short-term")
        case .longTerm: appState.text("长期", "Long-term")
        }
    }
}

struct CorrectionSample: Identifiable {
    let id = UUID()
    let raw: String
    let corrected: String
    let count: Int
    let context: String
    static let samples = [
        CorrectionSample(raw: "张月", corrected: "张越", count: 4, context: "Safari"),
        CorrectionSample(raw: "work body", corrected: "WorkBuddy", count: 3, context: "Slack"),
        CorrectionSample(raw: "Bifro M Q", corrected: "BifroMQ", count: 2, context: "VS Code")
    ]
}

struct SessionSample: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let ttl: String
    static let samples = [
        SessionSample(title: "当前 Agent Session", detail: "Safari · 选中文字 · Translate · 2 条 Follow-up", ttl: "8 min"),
        SessionSample(title: "最近提及", detail: "AniKuku · 张越 · internal testing", ttl: "42 min"),
        SessionSample(title: "最近听写", detail: "只保存字符数与纠错，不保存原始音频。", ttl: "Today")
    ]
}
