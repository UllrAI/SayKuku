// Isolated signed integration host. No production store, permissions or Keychain access.
import AppKit
import Observation

@MainActor @Observable
final class TestActivity { var busy = true }

@MainActor
final class TestDelegate: NSObject, NSApplicationDelegate {
    let activity = TestActivity()
    let updater = SoftwareUpdater(defaults: .standard)
    let termination = AppTermination()
    let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SAYKUKU_UPDATE_TEST_ROOT"]!)
    var timer: Timer?
    var lastCommand = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        termination.isBusy = { [weak self] in self?.activity.busy ?? false }
        termination.pauseNewWork = { [weak self] paused in self?.log("paused=\(paused)") }
        termination.waitingHandler = { [weak self] in self?.log("waiting") }
        termination.save = { [weak self] in
            guard let self else { return false }
            let fails = FileManager.default.fileExists(atPath: root.appendingPathComponent("save-fails").path)
            log("saved=\(!fails)")
            if !fails { try? Data("saved".utf8).write(to: root.appendingPathComponent("saved"), options: .atomic) }
            return !fails
        }
        updater.deferInstallation = { [weak self] handler in self?.termination.deferUntilIdle(handler) ?? false }
        log("launched=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")!)")
        updater.start()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func tick() {
        let status: [String: Any] = ["ready": updater.installsOnQuit, "busy": activity.busy,
                                    "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")!,
                                    "pid": ProcessInfo.processInfo.processIdentifier]
        try? JSONSerialization.data(withJSONObject: status).write(to: root.appendingPathComponent("status.json"), options: .atomic)
        guard let command = try? String(contentsOf: root.appendingPathComponent("command"), encoding: .utf8), command != lastCommand else { return }
        lastCommand = command
        switch command.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "busy": activity.busy = true
        case "idle": activity.busy = false
        case "quit", "quit-again": NSApp.terminate(nil)
        case "manual": updater.checkManually()
        default: break
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        termination.shouldTerminate()
    }

    func log(_ text: String) {
        let line = Data((text + "\n").utf8)
        let file = root.appendingPathComponent("events.log")
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else { try? line.write(to: file) }
    }
}

@main
struct TestHost {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = TestDelegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
