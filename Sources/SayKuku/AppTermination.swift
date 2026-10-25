import AppKit
import Observation

/// Waits before requesting termination; only the final save pauses new work.
@MainActor
@Observable
final class AppTermination {
    private(set) var isFinalizing = false
    @ObservationIgnored var isBusy: () -> Bool = { false }
    @ObservationIgnored var hasPendingResult: () -> Bool = { false }
    @ObservationIgnored var confirmDiscard: () -> Bool = { false }
    @ObservationIgnored var save: () async -> Bool = { true }
    @ObservationIgnored var pauseNewWork: (Bool) -> Void = { _ in }
    @ObservationIgnored var requestTermination: () -> Void = { NSApp.terminate(nil) }
    @ObservationIgnored var reply: (Bool) -> Void = { NSApp.reply(toApplicationShouldTerminate: $0) }
    @ObservationIgnored var waitingHandler: (() -> Void)?
    @ObservationIgnored private var whenIdle: (() -> Void)?

    /// Used by Sparkle before relaunching, and by a normal Quit while a task is running.
    @discardableResult
    func deferUntilIdle(_ action: @escaping () -> Void) -> Bool {
        guard isBusy() else { return false }
        whenIdle = action
        waitingHandler?()
        observeWork()
        return true
    }

    private func observeWork() {
        guard whenIdle != nil else { return }
        let busy = withObservationTracking { isBusy() } onChange: { [weak self] in
            Task { @MainActor in self?.observeWork() }
        }
        guard !busy else { return }
        // AppKit's terminateLater runs a nested event loop. Enter it from a run-loop
        // callback, not a running Swift task, so the final save can run on MainActor.
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            MainActor.assumeIsolated { self?.runWhenIdle() }
        }
    }

    private func runWhenIdle() {
        guard !isBusy() else { observeWork(); return }
        let action = whenIdle
        whenIdle = nil
        action?()
    }

    func shouldTerminate() -> NSApplication.TerminateReply {
        guard !isFinalizing else { return .terminateLater }
        if deferUntilIdle({ [weak self] in self?.requestTermination() }) { return .terminateCancel }
        guard !hasPendingResult() || confirmDiscard() else { return .terminateCancel }
        isFinalizing = true
        pauseNewWork(true)
        Task {
            let saved = await save()
            if !saved {
                isFinalizing = false
                pauseNewWork(false)
            }
            reply(saved)
        }
        return .terminateLater
    }
}
