import Accessibility
import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    // Pages are rebuilt on navigation, so the selections people come back to live here.
    @State private var historyFilter: HistoryFilter = .all
    @State private var historySearch = ""
    @State private var knowledgeSearch = ""
    @State private var knowledgeFilter: EntityType?

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            Sidebar(selection: $appState.destination)
                .navigationSplitViewColumnWidth(
                    min: KukuLayout.sidebarWidth,
                    ideal: KukuLayout.sidebarWidth,
                    max: KukuLayout.sidebarWidth
                )
        } detail: {
            ZStack {
                KukuColor.canvas.ignoresSafeArea()

                Group {
                    switch appState.destination {
                    case .home:
                        HomeView()
                    case .history:
                        HistoryView(filter: $historyFilter, search: $historySearch)
                    case .knowledge:
                        KnowledgeView(search: $knowledgeSearch, filter: $knowledgeFilter)
                    }
                }
                .id(appState.destination)

                if let toast = appState.toast {
                    VStack {
                        Spacer()
                        ToastView(toast: toast)
                            .padding(.bottom, KukuSpacing.xxl)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(KukuColor.coral)
        .sheet(item: $appState.presentedSheet) { destination in
            switch destination {
            case .onboarding:
                DomainOnboardingView()
                    .environment(appState)
            case .permissions:
                PermissionGuideView()
                    .environment(appState)
            case .qwenSetup:
                QwenSetupView()
                    .environment(appState)
            }
        }
    }
}

private struct Sidebar: View {
    @Environment(AppState.self) private var appState
    @Binding var selection: AppState.Destination

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: KukuSpacing.sm) {
                BrandMark()
                VStack(alignment: .leading, spacing: KukuSpacing.xxs) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("SayKuku")
                            .foregroundStyle(KukuColor.textPrimary)
                        Text(".")
                            .foregroundStyle(KukuColor.coral)
                    }
                    .font(.kuku(.title))
                    Text("Just Say It")
                        .font(.kuku(.caption))
                        .foregroundStyle(KukuColor.textSecondary)
                }
            }
            .padding(.top, KukuSpacing.lg)
            .padding(.horizontal, KukuSpacing.lg)
            .padding(.bottom, KukuSpacing.xl)

            VStack(spacing: KukuSpacing.xs) {
                ForEach(AppState.Destination.allCases) { destination in
                    SidebarButton(
                        title: destination.title,
                        symbol: destination.symbol,
                        isSelected: selection == destination,
                        badgeCount: destination == .knowledge ? appState.pendingCorrections.count : 0
                    ) {
                        selection = destination
                    }
                }
            }
            .padding(.horizontal, KukuSpacing.sm)

            Spacer()

            KukuDivider(inset: 0)
                .padding(.horizontal, KukuSpacing.lg)
                .padding(.bottom, KukuSpacing.sm)

            // Settings lives in its own window, so this button never shows as selected.
            SidebarButton(title: localized("Settings"), symbol: "gearshape", isSelected: false) {
                appState.showSettings()
            }
            .padding(.horizontal, KukuSpacing.sm)
            .padding(.bottom, KukuSpacing.md)
        }
        .background(KukuColor.sidebar)
        .toolbar(removing: .sidebarToggle)
    }
}

private struct SidebarButton: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    /// Items waiting on this page, such as correction suggestions; hidden at zero.
    var badgeCount = 0
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: KukuSpacing.sm) {
                Image(systemName: symbol)
                    .symbolVariant(isSelected ? .fill : .none)
                    .font(.kukuIcon(.regular))
                    // Fixed icon column so titles line up whatever the symbol's width.
                    .frame(width: 18)
                Text(title)
                    .font(.kuku(.body, weight: isSelected ? .semibold : .medium))
                Spacer()
                if badgeCount > 0 {
                    KukuBadge(text: "\(badgeCount)")
                        .monospacedDigit()
                }
            }
            .foregroundStyle(isSelected || isHovered ? KukuColor.textPrimary : KukuColor.textSecondary)
            .padding(.horizontal, KukuSpacing.md)
            .frame(maxWidth: .infinity, minHeight: KukuLayout.controlHeight)
            .contentShape(Rectangle())
            .background(
                isSelected ? KukuColor.selectedFill : (isHovered ? KukuColor.rowHover : Color.clear),
                in: RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(badgeCount > 0 ? localized("\(badgeCount) suggestions") : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { isHovered = $0 }
        .animation(Motion.snappy, value: isHovered)
    }
}

private struct ToastView: View {
    let toast: ToastMessage

    var body: some View {
        KukuToast(text: toast.text, symbol: toast.symbol)
            // Caps the wrap width; the pill itself stays as narrow as its text.
            .frame(maxWidth: 480)
            .padding(.horizontal, KukuSpacing.xxl)
            .onChange(of: toast.id, initial: true) {
                AccessibilityNotification.Announcement(toast.text).post()
            }
    }
}
