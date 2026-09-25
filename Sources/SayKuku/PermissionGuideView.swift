import SwiftUI

struct PermissionGuideView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let allGranted = appState.systemPermissions.allRequiredPermissionsGranted
        VStack(spacing: 0) {
            KukuSheetHeader(
                eyebrow: appState.setupProgress?.title,
                title: localized("Turn On Microphone and Accessibility"),
                description: localized("SayKuku needs the microphone to hear you and Accessibility to type into text fields.")
            ) {
                KukuSheetIcon(symbol: "checkmark.shield.fill")
            }

            KukuDivider(inset: 0)

            ScrollView {
                VStack(alignment: .leading, spacing: KukuLayout.sectionSpacing) {
                    KukuGroup {
                        PermissionActionRow(kind: .microphone)
                        KukuDivider()
                        PermissionActionRow(kind: .accessibility)
                    }

                    KukuGroup(localized("Microphone test")) {
                        MicrophoneTestPanel()
                    }
                }
                .padding(.horizontal, KukuLayout.sheetPadding)
                .padding(.vertical, KukuSpacing.xl)
            }

            KukuDivider(inset: 0)

            KukuSheetFooter(
                note: KukuSheetNote(text: localized("You can recheck this later in Settings › General."))
            ) {
                // Status refreshes when you come back from System Settings, so there is no Recheck button.
                if !allGranted {
                    Button(appState.setupSkipTitle, action: close)
                        .buttonStyle(.kukuSecondary)
                        .keyboardShortcut(.cancelAction)
                }
                Button(appState.setupContinueTitle, action: close)
                    .buttonStyle(.kukuPrimary)
                    .keyboardShortcut(allGranted ? KeyboardShortcut.defaultAction : nil)
                    .disabled(!allGranted)
            }
        }
        .frame(width: KukuLayout.sheetWideWidth, height: KukuLayout.sheetHeight)
        .background(KukuColor.canvas)
        .task { appState.refreshSystemPermissions() }
        .onDisappear { appState.microphoneTest.stop() }
    }

    private func close() {
        appState.dismissPermissionGuide()
        dismiss()
    }
}

struct PermissionActionRow: View {
    @Environment(AppState.self) private var appState
    let kind: SystemPermissionKind

    var body: some View {
        let status = appState.systemPermissions.status(for: kind)
        HStack(spacing: KukuSpacing.md) {
            // The tile stays neutral; the badge carries the status.
            KukuIconTile(symbol: symbol)
                .symbolVariant(status.isAuthorized ? .fill : .none)

            VStack(alignment: .leading, spacing: KukuSpacing.xxs) {
                HStack(spacing: KukuSpacing.sm) {
                    Text(title)
                        .font(.kuku(.body))
                        .foregroundStyle(KukuColor.textPrimary)
                    badge(for: status)
                }
                Text(subtitle)
                    .font(.kuku(.subheadline))
                    .foregroundStyle(KukuColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: KukuSpacing.md)

            // The badge already says it's on, so a granted row needs no trailing control.
            if !status.isAuthorized {
                Button(buttonTitle(for: status)) {
                    Task { await appState.requestPermission(kind) }
                }
                .buttonStyle(.kukuSecondary)
                .disabled(appState.systemPermissions.requesting != nil)
            }
        }
        .kukuRowFrame()
    }

    private func badge(for status: SystemPermissionStatus) -> KukuBadge {
        switch status {
        case .authorized:
            KukuBadge(text: localized("On"), tone: .success, symbol: "checkmark.circle.fill")
        case .restricted:
            KukuBadge(text: localized("Restricted"), tone: .warning, symbol: "exclamationmark.triangle.fill")
        case .notDetermined, .denied:
            KukuBadge(text: localized("Off"))
        }
    }

    private var symbol: String {
        switch kind {
        case .microphone: "mic"
        case .accessibility: "accessibility"
        }
    }

    private var title: String {
        switch kind {
        case .microphone: localized("Microphone")
        case .accessibility: localized("Accessibility")
        }
    }

    private var subtitle: String {
        switch kind {
        case .microphone:
            localized("Used only for Voice Input, Voice Agent, and the microphone test")
        case .accessibility:
            localized(
                "Lets SayKuku detect Fn, type into text fields and check the result, and read selected text when you use Voice Agent. SayKuku never logs your keystrokes."
            )
        }
    }

    private func buttonTitle(for status: SystemPermissionStatus) -> String {
        if appState.systemPermissions.requesting == kind {
            return kind == .accessibility
                ? localized("Opening…")
                : localized("Requesting…")
        }
        switch status {
        case .notDetermined:
            return localized("Enable")
        case .denied, .restricted:
            return kind == .microphone || appState.systemPermissions.hasPromptedForAccessibility
                ? localized("Open System Settings")
                : localized("Enable")
        case .authorized:
            return localized("On")
        }
    }
}

struct MicrophoneTestPanel: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let test = appState.microphoneTest
        VStack(alignment: .leading, spacing: KukuSpacing.md) {
            HStack(spacing: KukuSpacing.sm) {
                VStack(alignment: .leading, spacing: KukuSpacing.xxs) {
                    Text(localized("Microphone level"))
                        .font(.kuku(.body))
                        .foregroundStyle(KukuColor.textPrimary)
                    Text(deviceSubtitle)
                        .font(.kuku(.subheadline))
                        .foregroundStyle(KukuColor.textSecondary)
                }
                Spacer()
                Circle()
                    .fill(statusDotColor)
                    .frame(width: KukuLayout.statusDot, height: KukuLayout.statusDot)
                Text(testStatus)
                    .font(.kuku(.subheadline, weight: .medium))
                    .foregroundStyle(KukuColor.textSecondary)
            }

            AudioLevelMeter(level: test.level)

            HStack(spacing: KukuSpacing.sm) {
                Label(
                    localized("Checks the level only. Nothing is saved, uploaded, or played back."),
                    systemImage: "lock.fill"
                )
                .font(.kuku(.subheadline))
                .foregroundStyle(KukuColor.textSecondary)

                Spacer()

                Button(test.isRunning ? localized("Stop Test") : startButtonTitle) {
                    if test.isRunning {
                        test.stop()
                    } else {
                        Task {
                            var granted = appState.systemPermissions.microphoneStatus.isAuthorized
                            if !granted {
                                granted = await appState.requestPermission(.microphone)
                            }
                            if granted {
                                test.start()
                            }
                        }
                    }
                }
                .buttonStyle(.kukuSecondary)
                .disabled(test.phase == .starting || appState.systemPermissions.requesting != nil)
            }
        }
        .padding(KukuLayout.rowPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDisappear { test.stop() }
    }

    private var statusDotColor: Color {
        switch appState.microphoneTest.phase {
        case .running: KukuColor.success
        case .failed: KukuColor.warning
        case .idle, .starting: KukuColor.textTertiary
        }
    }

    private var deviceSubtitle: String {
        if !appState.microphoneTest.deviceName.isEmpty {
            return appState.microphoneTest.deviceName
        }
        return localized("Uses the system default input device")
    }

    private var startButtonTitle: String {
        appState.systemPermissions.microphoneStatus.isAuthorized
            ? localized("Start Test")
            : localized("Enable & Test")
    }

    private var testStatus: String {
        switch appState.microphoneTest.phase {
        case .idle:
            return localized("Not tested")
        case .starting:
            return localized("Starting…")
        case .running:
            return appState.microphoneTest.level > 0.08
                ? localized("Sound detected")
                : localized("Listening")
        case .failed(.permissionRequired):
            return localized("Microphone permission required")
        case .failed(.noInputDevice):
            return localized("No input device found")
        case .failed(.couldNotStart):
            return localized("Couldn’t start")
        }
    }
}

private struct AudioLevelMeter: View {
    let level: Double
    private let barCount = 24

    var body: some View {
        HStack(alignment: .center, spacing: KukuSpacing.xs) {
            ForEach(0..<barCount, id: \.self) { index in
                let threshold = Double(index + 1) / Double(barCount)
                Capsule()
                    // Live input is an in-progress state, so the lit bars are coral.
                    .fill(level >= threshold ? KukuColor.coral : KukuColor.fillHover)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 18) // Meter geometry.
        .animation(Motion.meter, value: level)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localized("Microphone input level"))
        .accessibilityValue("\(Int(level * 100))%")
    }
}
