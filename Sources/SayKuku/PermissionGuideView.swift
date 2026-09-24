import SwiftUI

struct PermissionGuideView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let allGranted = appState.systemPermissions.allRequiredPermissionsGranted
        VStack(spacing: 0) {
            KukuSheetHeader(
                eyebrow: appState.setupProgress?.title(appState),
                title: appState.text("开启两项权限，就能开口输入", "Two Permissions and You’re Ready to Talk"),
                description: appState.text(
                    "SayKuku 需要麦克风来听你说话，还需要辅助功能把文字写入输入框。",
                    "SayKuku needs the microphone to hear you and Accessibility to type into text fields."
                )
            ) {
                BrandMark(size: 22) // Sized for the 40 pt header tile.
            }

            KukuDivider(inset: 0)

            ScrollView {
                VStack(alignment: .leading, spacing: KukuLayout.sectionSpacing) {
                    KukuGroup {
                        PermissionActionRow(kind: .microphone)
                        KukuDivider()
                        PermissionActionRow(kind: .accessibility)
                    }

                    KukuGroup(appState.text("麦克风测试", "Microphone test")) {
                        MicrophoneTestPanel()
                    }
                }
                .padding(.horizontal, KukuLayout.sheetPadding)
                .padding(.vertical, KukuSpacing.xl)
            }

            KukuDivider(inset: 0)

            KukuSheetFooter(
                note: KukuSheetNote(text: appState.text("可随时在“设置 › 通用”中重新检查权限。", "You can recheck permissions anytime in Settings › General."))
            ) {
                if allGranted {
                    Button(appState.text("完成", "Done"), action: close)
                        .buttonStyle(.kukuPrimary)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(appState.text("以后再说", "Not Now"), action: close)
                        .buttonStyle(.kukuSecondary)
                        .keyboardShortcut(.cancelAction)
                    Button(appState.text("重新检查", "Recheck")) {
                        appState.refreshSystemPermissions()
                    }
                    .buttonStyle(.kukuPrimary)
                    .keyboardShortcut(.defaultAction)
                }
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
            KukuBadge(text: appState.text("已开启", "On"), tone: .success, symbol: "checkmark.circle.fill")
        case .restricted:
            KukuBadge(text: appState.text("受限制", "Restricted"), tone: .warning, symbol: "exclamationmark.triangle.fill")
        case .notDetermined, .denied:
            KukuBadge(text: appState.text("未开启", "Off"))
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
        case .microphone: appState.text("麦克风", "Microphone")
        case .accessibility: appState.text("辅助功能", "Accessibility")
        }
    }

    private var subtitle: String {
        switch kind {
        case .microphone:
            appState.text("仅在语音输入、语音 Agent 和麦克风测试时使用", "Used only for Voice Input, Voice Agent, and the microphone test")
        case .accessibility:
            appState.text(
                "用来识别 Fn 手势、把文字写入输入框并核对结果，使用语音 Agent 时也会读取选中文字。SayKuku 不会记录你的按键。",
                "Lets SayKuku detect Fn, type into text fields and check the result, and read selected text when you use Voice Agent. SayKuku never logs your keystrokes."
            )
        }
    }

    private func buttonTitle(for status: SystemPermissionStatus) -> String {
        if appState.systemPermissions.requesting == kind {
            return kind == .accessibility
                ? appState.text("正在打开…", "Opening…")
                : appState.text("正在请求…", "Requesting…")
        }
        switch status {
        case .notDetermined:
            return appState.text("开启", "Enable")
        case .denied, .restricted:
            return kind == .microphone
                ? appState.text("打开系统设置", "Open System Settings")
                : appState.text("开启", "Enable")
        case .authorized:
            return appState.text("已开启", "On")
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
                    Text(appState.text("麦克风音量", "Microphone level"))
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
                    appState.text("只检测音量，不会保存、上传或回放", "Checks the level only. Nothing is saved, uploaded, or played back."),
                    systemImage: "lock.fill"
                )
                .font(.kuku(.subheadline))
                .foregroundStyle(KukuColor.textSecondary)

                Spacer()

                Button(test.isRunning ? appState.text("停止测试", "Stop Test") : startButtonTitle) {
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
        return appState.text("使用系统默认输入设备", "Uses the system default input device")
    }

    private var startButtonTitle: String {
        appState.systemPermissions.microphoneStatus.isAuthorized
            ? appState.text("开始测试", "Start Test")
            : appState.text("开启并测试", "Enable & Test")
    }

    private var testStatus: String {
        switch appState.microphoneTest.phase {
        case .idle:
            return appState.text("尚未测试", "Not tested")
        case .starting:
            return appState.text("正在启动…", "Starting…")
        case .running:
            return appState.microphoneTest.level > 0.08
                ? appState.text("已检测到声音", "Sound detected")
                : appState.text("正在监听", "Listening")
        case .failed(.permissionRequired):
            return appState.text("需要麦克风权限", "Microphone permission required")
        case .failed(.noInputDevice):
            return appState.text("未找到输入设备", "No input device found")
        case .failed(.couldNotStart):
            return appState.text("无法启动", "Couldn’t start")
        }
    }
}

private struct AudioLevelMeter: View {
    @Environment(AppState.self) private var appState
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
        .accessibilityLabel(appState.text("麦克风输入音量", "Microphone input level"))
        .accessibilityValue("\(Int(level * 100))%")
    }
}
