import Foundation
import os

/// The app's only loggers, one per area, so `log stream` can filter by subsystem and category.
/// Messages carry states, error types, bundle IDs, status codes and counts: never text, audio, prompts or keys.
enum Log {
    fileprivate static let subsystem = Bundle.main.bundleIdentifier ?? "SayKuku"
    static let audio = Logger(subsystem: subsystem, category: "Audio")
    static let qwen = Logger(subsystem: subsystem, category: "Qwen")
    static let store = Logger(subsystem: subsystem, category: "Store")
    static let shortcut = Logger(subsystem: subsystem, category: "Shortcut")
    static let permissions = Logger(subsystem: subsystem, category: "Permissions")
    static let text = Logger(subsystem: subsystem, category: "TextInteraction")
    static let update = Logger(subsystem: subsystem, category: "Update")
    static let workflow = Logger(subsystem: subsystem, category: "Workflow")

    /// An error's type and case, or its domain and code, never its message:
    /// messages can echo dictated text or server replies.
    static func describe(_ error: Error) -> String {
        let name = String(describing: type(of: error))
        if case .server(let status, _) = error as? QwenError { return "\(name).server(\(status))" }
        let mirror = Mirror(reflecting: error)
        guard mirror.displayStyle == .enum else {
            let nsError = error as NSError
            return "\(nsError.domain) \(nsError.code)"
        }
        // A case with associated values is named by its label; a plain case prints as its name.
        return "\(name).\(mirror.children.first?.label ?? String(describing: error))"
    }
}

extension OSSignposter {
    /// Intervals on the way from Fn to the pill, for the os_signpost instrument (see docs/COMPATIBILITY.md).
    /// Computed so this nonisolated extension holds no global state of a possibly non-Sendable type.
    static var performance: OSSignposter {
        OSSignposter(subsystem: Log.subsystem, category: "Performance")
    }
}
