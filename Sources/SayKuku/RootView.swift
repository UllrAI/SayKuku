import AppKit
import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            Sidebar(selection: $appState.destination)
                .navigationSplitViewColumnWidth(min: 176, ideal: 176, max: 176)
        } detail: {
            ZStack {
                KukuColor.canvas.ignoresSafeArea()

                Group {
                    switch appState.destination {
                    case .home:
                        HomeView()
                    case .history:
                        HistoryView()
                    case .knowledge:
                        KnowledgeView()
                    case .memory:
                        MemoryView()
                    case .settings:
                        SettingsView()
                    }
                }
                .id(appState.destination)

                if let toast = appState.toast {
                    VStack {
                        Spacer()
                        ToastView(toast: toast)
                            .padding(.bottom, 26)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(KukuColor.coral)
        .sheet(item: $appState.presentedSheet, onDismiss: { appState.presentNextSetupStep() }) { destination in
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
            HStack(spacing: 10) {
                BrandMark(size: 27)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("SayKuku")
                            .foregroundStyle(KukuColor.ink)
                        Text(".")
                            .foregroundStyle(KukuColor.coral)
                    }
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("Just Say It")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(KukuColor.stone)
                }
            }
            .padding(.top, 17)
            .padding(.horizontal, 16)
            .padding(.bottom, 22)

            VStack(spacing: 4) {
                ForEach(AppState.Destination.allCases.filter { $0 != .settings }) { destination in
                    navigationButton(destination)
                }
            }
            .padding(.horizontal, 9)

            Spacer()

            Divider()
                .opacity(0.45)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            navigationButton(.settings)
                .padding(.horizontal, 9)
                .padding(.bottom, 12)
        }
        .background(KukuColor.sidebar)
        .toolbar(removing: .sidebarToggle)
    }

    private func navigationButton(_ destination: AppState.Destination) -> some View {
        Button {
            selection = destination
        } label: {
            HStack(spacing: 10) {
                Image(systemName: destination.symbol)
                    .symbolVariant(selection == destination ? .fill : .none)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text(destination.title(appState))
                    .font(.system(size: 13, weight: selection == destination ? .semibold : .medium))
                Spacer()
            }
            .foregroundStyle(selection == destination || hovered == destination ? KukuColor.ink : KukuColor.stone)
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 36)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selection == destination
                          ? KukuColor.surfaceStrong
                          : (hovered == destination ? Color.white.opacity(0.38) : Color.clear))
            }
            .overlay {
                if selection == destination {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.7), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { inside in hovered = inside ? destination : nil }
        .animation(Motion.snappy, value: hovered)
    }

}

private struct ToastView: View {
    let toast: ToastMessage

    var body: some View {
        Label(toast.text, systemImage: toast.symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(KukuColor.graphite.opacity(0.96))
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.14), radius: 12, y: 5)
    }
}
