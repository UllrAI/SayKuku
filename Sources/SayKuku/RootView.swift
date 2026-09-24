import Accessibility
import AppKit
import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    // Pages are rebuilt on navigation, so the selections people come back to live here.
    @State private var historyFilter: HistoryFilter = .all
    @State private var historySearch = ""
    @State private var knowledgeSearch = ""
    @State private var knowledgeFilter: KnowledgeFilter = .all
    @State private var memoryScope: MemoryScope = .corrections

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
                    case .memory:
                        MemoryView(selectedScope: $memoryScope)
                    case .settings:
                        SettingsView(selection: $appState.settingsSection)
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appState.refreshSystemPermissions()
        }
    }
}

private struct Sidebar: View {
    @Environment(AppState.self) private var appState
    @Binding var selection: AppState.Destination
    @State private var hovered: AppState.Destination?

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
                ForEach(AppState.Destination.allCases.filter { $0 != .settings }) { destination in
                    navigationButton(destination)
                }
            }
            .padding(.horizontal, KukuSpacing.sm)

            Spacer()

            KukuDivider(inset: 0)
                .padding(.horizontal, KukuSpacing.lg)
                .padding(.bottom, KukuSpacing.sm)

            navigationButton(.settings)
                .padding(.horizontal, KukuSpacing.sm)
                .padding(.bottom, KukuSpacing.md)
        }
        .background(KukuColor.sidebar)
        .toolbar(removing: .sidebarToggle)
    }

    private func navigationButton(_ destination: AppState.Destination) -> some View {
        let isSelected = selection == destination
        let isHovered = hovered == destination
        return Button {
            selection = destination
        } label: {
            HStack(spacing: KukuSpacing.sm) {
                Image(systemName: destination.symbol)
                    .symbolVariant(isSelected ? .fill : .none)
                    .font(.kukuIcon(.regular))
                    // Fixed icon column so titles line up whatever the symbol's width.
                    .frame(width: 18)
                Text(destination.title(appState))
                    .font(.kuku(.body, weight: isSelected ? .semibold : .medium))
                Spacer()
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
        .accessibilityLabel(destination.title(appState))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { inside in hovered = inside ? destination : nil }
        .animation(Motion.snappy, value: hovered)
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
