import Foundation
import os

/// Where the time went after one recording stopped, kept with its History entry and logged as one line.
/// Stages, durations and outcomes only: never text, audio or prompts.
struct WorkflowTiming: Codable, Equatable, Sendable {
    /// In the order they run; a run records only the stages it went through.
    enum Stage: String, Codable, CaseIterable, Sendable {
        /// Saving the recording and History, which recognition waits for.
        case saveRecording
        /// Waiting for the realtime connection and the audio still queued for it.
        case upload
        /// From the commit to the first realtime text; missing when the text started before the commit.
        case firstText
        /// From the commit to the final realtime text.
        case finalText
        /// One batch recognition request, on its own or after realtime failed.
        case batch
        /// The text-model pass over light dictation.
        case refine
        /// The Agent's request.
        case agent
        /// Writing into the app, including the wait to verify it, so it ends a little after the text shows.
        case insert
    }

    struct Step: Codable, Equatable, Sendable {
        var stage: Stage
        var milliseconds: Int
    }

    enum StopReason: String, Codable, Sendable {
        case manual, autoStop, limit, deviceChange
    }

    enum Route: String, Codable, Sendable {
        case realtime, batch
        /// Realtime failed, then batch recognition ran.
        case fallback
    }

    enum Result: String, Codable, Sendable {
        /// Written into the app, or the Agent's action ran.
        case completed
        /// Left on the copy card because writing failed or was off.
        case copied
        /// The Agent's answer or action card is waiting.
        case shown
        case failed, cancelled
    }

    var stopReason: StopReason
    /// Shortcut to a running microphone.
    var micStartMilliseconds: Int?
    /// Microphone running to a ready realtime connection; it overlaps speaking.
    var connectMilliseconds: Int?
    var steps: [Step] = []
    var route: Route?
    /// "changed", "unchanged", or the `DictationRefinement.Fallback` that kept the first pass.
    var refinement: String?
    /// The `TextWriteOutcome` of the write.
    var insertion: String?
    /// The Agent's action.
    var action: String?
    var result: Result?
    /// `Log.describe` of the failure.
    var error: String?
    /// Stop to the result: the text written, the card shown, or the failure.
    var totalMilliseconds: Int?

    func milliseconds(_ stage: Stage) -> Int? {
        steps.first { $0.stage == stage }?.milliseconds
    }

    /// One line of `key=value` pairs, for the log.
    var summary: String {
        var parts = ["stop=\(stopReason.rawValue)", "result=\(result?.rawValue ?? "unfinished")"]
        if let totalMilliseconds { parts.append("total=\(totalMilliseconds)ms") }
        if let micStartMilliseconds { parts.append("mic=\(micStartMilliseconds)ms") }
        if let connectMilliseconds { parts.append("connect=\(connectMilliseconds)ms") }
        if let route { parts.append("route=\(route.rawValue)") }
        for step in steps {
            var part = "\(step.stage.rawValue)=\(step.milliseconds)ms"
            if step.stage == .refine, let refinement { part += "(\(refinement))" }
            if step.stage == .insert, let insertion { part += "(\(insertion))" }
            parts.append(part)
        }
        if let action { parts.append("action=\(action)") }
        if let error { parts.append("error=\(error)") }
        return parts.joined(separator: " ")
    }
}

/// Builds the `WorkflowTiming` of one recording from its stop to its result, then logs it once.
@MainActor
final class WorkflowTrace {
    let mode: HistoryMode
    private let stopped = ContinuousClock.now
    private(set) var timing: WorkflowTiming
    private var commitSent: ContinuousClock.Instant?
    private var firstText: ContinuousClock.Instant?
    private var isFinished = false

    init(mode: HistoryMode, stopReason: WorkflowTiming.StopReason, micStart: Duration?, connect: Duration?) {
        self.mode = mode
        timing = WorkflowTiming(
            stopReason: stopReason,
            micStartMilliseconds: micStart.map(Self.milliseconds),
            connectMilliseconds: connect.map(Self.milliseconds)
        )
    }

    /// Times `body` as `stage`, also when it throws.
    func measure<T>(_ stage: WorkflowTiming.Stage, _ body: () async throws -> T) async rethrows -> T {
        let started = ContinuousClock.now
        defer { record(stage, since: started) }
        return try await body()
    }

    func record(_ stage: WorkflowTiming.Stage, since started: ContinuousClock.Instant) {
        record(stage, duration: started.duration(to: .now))
    }

    func setRoute(_ route: WorkflowTiming.Route) { timing.route = route }
    func setRefinement(_ refinement: String) { timing.refinement = refinement }
    func setInsertion(_ outcome: TextWriteOutcome) { timing.insertion = String(describing: outcome) }
    func setAction(_ action: AgentResponse.Action) { timing.action = action.rawValue }

    /// The realtime commit is about to be sent; text that arrives from now on counts as its first text.
    func noteCommit() { commitSent = .now }

    /// Realtime text arrived at `instant`, which may be read after the final text is already in.
    func noteRealtimeText(at instant: ContinuousClock.Instant) {
        guard let commitSent, firstText == nil, instant >= commitSent else { return }
        firstText = instant
    }

    /// Ends the trace and logs it; later calls change nothing and return the same timing.
    @discardableResult
    func finish(_ result: WorkflowTiming.Result, error: Error? = nil) -> WorkflowTiming {
        guard !isFinished else { return timing }
        isFinished = true
        if let commitSent, let firstText { record(.firstText, duration: commitSent.duration(to: firstText)) }
        timing.result = result
        timing.error = error.map(Log.describe)
        timing.totalMilliseconds = Self.milliseconds(stopped.duration(to: .now))
        let summary = timing.summary
        let name = mode == .dictation ? "Dictation" : "Agent"
        if result == .failed {
            Log.workflow.error("\(name, privacy: .public) trace: \(summary, privacy: .public)")
        } else {
            Log.workflow.notice("\(name, privacy: .public) trace: \(summary, privacy: .public)")
        }
        return timing
    }

    private func record(_ stage: WorkflowTiming.Stage, duration: Duration) {
        timing.steps.removeAll { $0.stage == stage }
        timing.steps.append(WorkflowTiming.Step(stage: stage, milliseconds: Self.milliseconds(duration)))
        let order = WorkflowTiming.Stage.allCases
        timing.steps.sort { order.firstIndex(of: $0.stage)! < order.firstIndex(of: $1.stage)! }
    }

    nonisolated static func milliseconds(_ duration: Duration) -> Int {
        Int((duration / .milliseconds(1)).rounded())
    }
}
