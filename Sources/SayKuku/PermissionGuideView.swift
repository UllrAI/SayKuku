import SwiftUI

struct PermissionGuideView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(KukuColor.coralSoft)
                    BrandMark(size: 25)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 5) {
                    Text(appState.text("准备好，说一句就开始", "Get ready to speak"))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text(appState.text(
                        "SayKuku 需要麦克风来听你说话，并使用辅助功能把文字写入当前应用。",
                        "SayKuku uses the microphone to hear you and Accessibility to type into the current app."
                    ))
                    .font(.system(size: 11.5))
                    .foregroundStyle(KukuColor.stone)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 16)

                Button {
                    close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 26, height: 26)
                        .background(KukuColor.shade.opacity(0.055), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(appState.text("关闭", "Close"))
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 18)

            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        PermissionActionRow(kind: .microphone)
                            .kukuSurface(radius: KukuLayout.radiusMedium)
                        PermissionActionRow(kind: .accessibility)
                            .kukuSurface(radius: KukuLayout.radiusMedium)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionEyebrow(text: appState.text("麦克风测试", "Microphone test"))
                            .padding(.leading, 4)
                        MicrophoneTestPanel()
                            .kukuSurface(radius: KukuLayout.radiusMedium)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }

            Divider().opacity(0.5)

            HStack(spacing: 10) {
                Text(appState.text("权限可随时在设置中重新检查。", "You can recheck permissions anytime in Settings."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(KukuColor.stone)
                Spacer()
                Button(appState.text("稍后", "Later")) {
                    close()
                }
                .buttonStyle(HoverFillButtonStyle())
                Button(appState.systemPermissions.allRequiredPermissionsGranted
                       ? appState.text("开始使用", "Start using")
                       : appState.text("重新检查", "Recheck")) {
                    if appState.systemPermissions.allRequiredPermissionsGranted {
                        close()
                    } else {
                        appState.refreshSystemPermissions()
                    }
                }
                .buttonStyle(HoverFillButtonStyle(prominent: true))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 620, height: 590)
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
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .symbolVariant(status.isAuthorized ? .fill : .none)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(status.isAuthorized ? KukuColor.mint : KukuColor.coral)
                .frame(width: 34, height: 34)
                .background(
                    (status.isAuthorized ? KukuColor.mint : KukuColor.coral).opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                    PermissionStatusBadge(status: status)
                }
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(KukuColor.stone)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 14)

            if status.isAuthorized {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(KukuColor.mint)
                    .accessibilityLabel(appState.text("已开启", "Enabled"))
            } else {
                Button(buttonTitle(for: status)) {
                    Task { await appState.requestPermission(kind) }
                }
                .buttonStyle(TintButtonStyle())
                .disabled(appState.systemPermissions.requesting != nil)
            }
        }
        .padding(.horizontal, 15)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
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
            appState.text("仅在开始语音输入、语音 Agent 或输入测试时访问", "Used only for Voice Input, Voice Agent, or the input test")
        case .accessibility:
            appState.text("用于响应 Fn，并把文字写入当前输入框；不会读取其他键盘输入", "Used for Fn and typing into the current field; other keystrokes are not read")
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
                ? appState.text("打开设置", "Open Settings")
                : appState.text("开启", "Enable")
        case .authorized:
            return appState.text("已开启", "Enabled")
        }
    }
}

struct PermissionStatusBadge: View {
    @Environment(AppState.self) private var appState
    let status: SystemPermissionStatus

    var body: some View {
        Text(title)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(status.isAuthorized ? KukuColor.mint : KukuColor.stone)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(
                (status.isAuthorized ? KukuColor.mint : KukuColor.shade).opacity(0.065),
                in: Capsule()
            )
    }

    private var title: String {
        switch status {
        case .notDetermined: appState.text("未请求", "Not requested")
        case .denied: appState.text("未开启", "Not enabled")
        case .restricted: appState.text("受限制", "Restricted")
        case .authorized: appState.text("已开启", "Enabled")
        }
    }
}

struct MicrophoneTestPanel: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let test = appState.microphoneTest
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(appState.text("麦克风音量", "Microphone level"))
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(deviceSubtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(KukuColor.stone)
                }
                Spacer()
                Circle()
                    .fill(test.isRunning ? KukuColor.mint : KukuColor.stone.opacity(0.35))
                    .frame(width: 7, height: 7)
                Text(testStatus)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(test.isRunning ? KukuColor.mint : KukuColor.stone)
            }

            AudioLevelMeter(level: test.level)

            HStack(spacing: 10) {
                Label(
                    appState.text("只检测音量，不保存、不上传、不回放", "Level only; never saved, uploaded, or played back"),
                    systemImage: "lock.fill"
                )
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(KukuColor.stone)

                Spacer()

                Button(test.isRunning ? appState.text("停止测试", "Stop test") : startButtonTitle) {
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
                .buttonStyle(TintButtonStyle())
                .disabled(test.phase == .starting || appState.systemPermissions.requesting != nil)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDisappear { test.stop() }
    }

    private var deviceSubtitle: String {
        if !appState.microphoneTest.deviceName.isEmpty {
            return appState.microphoneTest.deviceName
        }
        return appState.text("使用系统默认输入设备", "Uses the system default input device")
    }

    private var startButtonTitle: String {
        appState.systemPermissions.microphoneStatus.isAuthorized
            ? appState.text("开始测试", "Start test")
            : appState.text("开启并测试", "Enable & test")
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
            return appState.text("未找到输入设备", "No input device")
        case .failed(.couldNotStart):
            return appState.text("无法启动", "Could not start")
        }
    }
}

private struct AudioLevelMeter: View {
    @Environment(AppState.self) private var appState
    let level: Double
    private let barCount = 24

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<barCount, id: \.self) { index in
                let threshold = Double(index + 1) / Double(barCount)
                Capsule()
                    .fill(level >= threshold ? KukuColor.mint : KukuColor.ink.opacity(0.075))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 18)
        .animation(.linear(duration: 0.08), value: level)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(appState.text("麦克风输入音量", "Microphone input level"))
        .accessibilityValue("\(Int(level * 100))%")
    }
}
