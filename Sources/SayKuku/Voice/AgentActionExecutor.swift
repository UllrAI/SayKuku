import AppKit
import os

enum AgentActionError: LocalizedError {
    case deleteNeedsInsert
    case openFailed
    case shortcutFailed
    case shortcutTimedOut

    var errorDescription: String? {
        switch self {
        case .deleteNeedsInsert: localized("Turn on Insert automatically to delete text by voice.")
        case .openFailed: localized("Couldn’t open this address. Check your default browser.")
        case .shortcutFailed: localized("Couldn’t run the shortcut. Check it in the Shortcuts app.")
        case .shortcutTimedOut: localized("The shortcut took over a minute, so it was stopped.")
        }
    }
}

enum AgentActionExecutor {
    /// Context that someone other than the user may have written, such as a web page hiding instructions.
    private static let untrustedContextKinds: [ContextItem.Kind] = [
        .selectedText, .previousOutput, .window, .clipboard, .browser, .screen, .session
    ]

    @MainActor
    static func execute(
        _ response: AgentResponse, engine: SearchEngine,
        openURL: @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) async throws {
        if let url = try validate(response, engine: engine) {
            guard openURL(url) else { throw AgentActionError.openFailed }
        } else if response.action == .runShortcut, let name = response.shortcutName {
            try await runShortcut(named: name)
        }
    }

    /// Checks the payload an action needs, before a confirmation card offers it or the action runs.
    /// Returns the address to open for links and searches.
    @discardableResult
    static func validate(_ response: AgentResponse, engine: SearchEngine) throws -> URL? {
        switch response.action {
        case .writeText, .answer:
            return nil
        case .openURL:
            guard let url = webURL(response.url) else { throw QwenError.invalidResponse }
            return url
        case .webSearch:
            guard let query = response.query, !query.isEmpty, let url = engine.url(for: query) else {
                throw QwenError.invalidResponse
            }
            return url
        case .runShortcut:
            guard response.shortcutName?.isEmpty == false else { throw QwenError.invalidResponse }
            return nil
        }
    }

    /// A shortcut can change files or other apps, so it always requires approval. Links and searches
    /// require approval when the model saw text that someone other than the user may have written.
    static func needsConfirmation(_ response: AgentResponse, context: [ContextItem]) -> Bool {
        response.action == .runShortcut || (
            [.openURL, .webSearch].contains(response.action)
                && context.contains { untrustedContextKinds.contains($0.kind) }
        )
    }

    /// Whether a writeText reply replaces text the model saw only the start of, which would drop the rest.
    /// A deletion drops all of it by design, so it never needs the full text.
    static func replacesClippedText(_ response: AgentResponse, context: [ContextItem]) -> Bool {
        guard response.action == .writeText, !response.deletesPrevious else { return false }
        let source: ContextItem.Kind = response.target == .previous ? .previousOutput : .selectedText
        return context.contains { $0.kind == source && $0.isClipped }
    }

    /// Only plain web links; credentials such as `https://google.com@evil.com` would disguise the real host.
    private static func webURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased()),
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    /// Waits for `shortcuts run` off the main thread so a failing shortcut is reported instead of shown as done.
    /// A stuck shortcut is stopped after a minute, and cancelling the workflow stops it right away.
    private static func runShortcut(named name: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        // Launch and cancel share a lock, so a cancel either stops the launch or sees the running process.
        let cancelled = OSAllocatedUnfairLock(initialState: false)
        let timedOut = OSAllocatedUnfairLock(initialState: false)
        let timeout = Task {
            try await Task.sleep(for: .seconds(60))
            timedOut.withLock { didTimeOut in
                guard process.isRunning else { return }
                didTimeOut = true
                process.terminate()
            }
        }
        defer { timeout.cancel() }
        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                let launchError: (any Error)? = cancelled.withLock { isCancelled in
                    guard !isCancelled else { return CancellationError() }
                    do {
                        try process.run()
                        return nil
                    } catch {
                        return error
                    }
                }
                if let launchError { continuation.resume(throwing: launchError) }
            }
        } onCancel: {
            cancelled.withLock { isCancelled in
                isCancelled = true
                // Terminating a process that never launched raises an exception.
                if process.isRunning { process.terminate() }
            }
        }
        try Task.checkCancellation()
        if timedOut.withLock({ $0 }) { throw AgentActionError.shortcutTimedOut }
        guard status == 0 else { throw AgentActionError.shortcutFailed }
    }
}
