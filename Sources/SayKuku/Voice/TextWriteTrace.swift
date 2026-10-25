import Foundation
import os

/// Timing only: never accepts dictated text, field values or clipboard contents.
@MainActor
final class TextWriteTrace {
    enum Stage: String, CaseIterable {
        case validateTarget, axWritable, axSet, axVerify, axVerifyReads, axFallbackCheck
        case pasteValidate, clipboardBackup, clipboardPrepare, pasteDelay, pasteRevalidate, postPaste
        case pasteVerify, pasteVerifyReads, pasteFallbackCheck, clipboardRestoreDelay, clipboardRestore
    }

    enum Verification: String, CaseIterable {
        case accessibility = "ax", paste
        var readStage: Stage { self == .accessibility ? .axVerifyReads : .pasteVerifyReads }
    }

    enum Milestone: String { case axAccepted, pastePosted, axVerified, pasteVerified }

    private let id = UUID().uuidString
    private let bundleID: String
    private let started = ContinuousClock.now
    private var durations: [Stage: Duration] = [:]
    private var milestones: [Milestone: Int] = [:]
    private var attempts: [Verification: Int] = [:]
    private var lengthMismatches: [Verification: Int] = [:]
    var clipboardItems = 0
    var clipboardBytes = 0

    init(bundleID: String) {
        self.bundleID = bundleID
        Log.text.notice("Text write begin: id=\(self.id, privacy: .public) bundle=\(bundleID, privacy: .public)")
    }

    func measure<T>(_ stage: Stage, _ body: () throws -> T) rethrows -> T {
        let start = ContinuousClock.now
        defer { record(stage, duration: start.duration(to: .now)) }
        return try body()
    }

    func measure<T>(_ stage: Stage, _ body: () async throws -> T) async rethrows -> T {
        let start = ContinuousClock.now
        defer { record(stage, duration: start.duration(to: .now)) }
        return try await body()
    }

    func record(_ stage: Stage, duration: Duration) {
        durations[stage, default: .zero] += duration
    }

    func milliseconds(_ stage: Stage) -> Int? { durations[stage].map(WorkflowTrace.milliseconds) }

    func verificationAttempt(_ route: Verification) { attempts[route, default: 0] += 1 }
    func lengthMismatch(_ route: Verification) { lengthMismatches[route, default: 0] += 1 }

    func mark(_ milestone: Milestone) {
        let elapsed = WorkflowTrace.milliseconds(started.duration(to: .now))
        milestones[milestone] = elapsed
        Log.text.notice("Text write milestone: id=\(self.id, privacy: .public) event=\(milestone.rawValue, privacy: .public) elapsed=\(elapsed)ms")
    }

    func finish(_ outcome: TextWriteOutcome?) {
        let summary = summary(outcome)
        Log.text.notice("Text write trace: \(summary, privacy: .public)")
    }

    func summary(_ outcome: TextWriteOutcome?) -> String {
        var parts = ["id=\(id)", "bundle=\(bundleID)",
                     "result=\(outcome.map { String(describing: $0) } ?? "interrupted")",
                     "total=\(WorkflowTrace.milliseconds(started.duration(to: .now)))ms"]
        for stage in Stage.allCases {
            if let value = milliseconds(stage) { parts.append("\(stage.rawValue)=\(value)ms") }
        }
        for milestone in [Milestone.axAccepted, .pastePosted, .axVerified, .pasteVerified] {
            if let value = milestones[milestone] { parts.append("\(milestone.rawValue)At=\(value)ms") }
        }
        for route in Verification.allCases where attempts[route] != nil {
            parts.append("\(route.rawValue)Attempts=\(attempts[route, default: 0])")
            parts.append("\(route.rawValue)LengthMismatches=\(lengthMismatches[route, default: 0])")
        }
        parts += ["clipboardItems=\(clipboardItems)", "clipboardBytes=\(clipboardBytes)"]
        return parts.joined(separator: " ")
    }
}
