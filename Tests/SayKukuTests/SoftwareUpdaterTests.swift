import AppKit
import Observation
import Testing
@testable import SayKuku

@Suite("Software update preferences")
@MainActor
struct SoftwareUpdaterTests {
    @Test("explicit legacy choices migrate once without replacing Sparkle choices")
    func migration() {
        for legacy: Bool? in [nil, false, true] {
            let environment = AppStateTestEnvironment()
            defer { environment.clean() }
            if let legacy { environment.defaults.set(legacy, forKey: "updates.automaticChecks") }
            environment.defaults.set("1.0.9", forKey: "updates.skippedVersion")
            SoftwareUpdater.migratePreferences(environment.defaults)
            #expect((environment.defaults.object(forKey: "SUEnableAutomaticChecks") as? Bool) == legacy)
            #expect(environment.defaults.object(forKey: "updates.skippedVersion") == nil)
            #expect(environment.defaults.object(forKey: "SUAutomaticallyUpdate") == nil)
            environment.defaults.set(false, forKey: "SUEnableAutomaticChecks")
            environment.defaults.set(false, forKey: "SUAutomaticallyUpdate")
            environment.defaults.set(true, forKey: "updates.automaticChecks")
            SoftwareUpdater.migratePreferences(environment.defaults)
            #expect(!environment.defaults.bool(forKey: "SUEnableAutomaticChecks"))
            #expect(!environment.defaults.bool(forKey: "SUAutomaticallyUpdate"))
        }
    }

    @Test("an existing Sparkle preference wins over a legacy setting")
    func existingPreference() {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        environment.defaults.set(false, forKey: "SUEnableAutomaticChecks")
        environment.defaults.set(true, forKey: "updates.automaticChecks")
        SoftwareUpdater.migratePreferences(environment.defaults)
        #expect(!environment.defaults.bool(forKey: "SUEnableAutomaticChecks"))
    }

    @Test("development app states never construct or start an updater")
    func disabledInDevelopment() {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        #expect(environment.makeState().softwareUpdater == nil)
    }
}

@MainActor @Observable
private final class TerminationActivity {
    var busy = true
    var pending = false
}

@Suite("Safe application termination")
@MainActor
struct AppTerminationTests {
    @Test("quit waits while tasks continue, then pauses new work during persistence only")
    func waitsAndSaves() async {
        let activity = TerminationActivity()
        let termination = AppTermination()
        var quitRequests = 0
        var paused = false
        var reply: Bool?
        termination.isBusy = { activity.busy }
        termination.pauseNewWork = { paused = $0 }
        termination.requestTermination = { quitRequests += 1 }
        termination.reply = { reply = $0 }
        termination.save = {
            #expect(paused)
            return true
        }
        #expect(termination.shouldTerminate() == .terminateCancel)
        #expect(!paused && quitRequests == 0)
        activity.busy = false
        #expect(await eventually { quitRequests == 1 })
        #expect(termination.shouldTerminate() == .terminateLater)
        #expect(await eventually { reply == true })
        #expect(paused && termination.isFinalizing)
        activity.busy = true
        activity.busy = false
        await Task.yield()
        #expect(quitRequests == 1)
    }

    @Test("save failures cancel termination and restore new work")
    func saveFailure() async {
        let termination = AppTermination()
        var paused = false
        var reply: Bool?
        termination.save = { false }
        termination.pauseNewWork = { paused = $0 }
        termination.reply = { reply = $0 }
        #expect(termination.shouldTerminate() == .terminateLater)
        #expect(await eventually { reply == false })
        #expect(!paused && !termination.isFinalizing)
    }

    @Test("unclaimed results require a choice before saving or discarding")
    func pendingResults() async {
        let termination = AppTermination()
        var permitsDiscard = false
        var saves = 0
        var reply: Bool?
        termination.hasPendingResult = { true }
        termination.confirmDiscard = { permitsDiscard }
        termination.save = { saves += 1; return true }
        termination.reply = { reply = $0 }
        #expect(termination.shouldTerminate() == .terminateCancel)
        #expect(saves == 0)
        permitsDiscard = true
        #expect(termination.shouldTerminate() == .terminateLater)
        #expect(await eventually { reply == true })
        #expect(saves == 1)
    }

    @Test("manual Sparkle relaunch uses the same task boundary without starting another task")
    func deferredInstall() async {
        let activity = TerminationActivity()
        let termination = AppTermination()
        termination.isBusy = { activity.busy }
        var installs = 0
        #expect(termination.deferUntilIdle { installs += 1 })
        #expect(installs == 0 && !termination.isFinalizing)
        activity.busy = false
        #expect(await eventually { installs == 1 })
        #expect(!termination.deferUntilIdle { installs += 1 })
        #expect(installs == 1)
    }

    @Test("a task started again while waiting postpones the same quit request")
    func resumedWork() async {
        let activity = TerminationActivity()
        let termination = AppTermination()
        termination.isBusy = { activity.busy }
        var installs = 0
        #expect(termination.deferUntilIdle { installs += 1 })
        activity.busy = false
        activity.busy = true
        try? await Task.sleep(for: .milliseconds(30))
        #expect(installs == 0)
        activity.busy = false
        #expect(await eventually { installs == 1 })
    }

    @Test("voice startup and model work are busy, while an unclaimed result waits for the user")
    func workflowStates() async throws {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        let response = AgentResponse(transcript: "Hello", action: .answer, output: "Unsaved result")
        let state = environment.makeState(dependencies: .fake(reasoning: FakeReasoning(agentReply: .success(response))))
        try state.settings.saveAPIKey("test")
        state.settings.soundCuesEnabled = false
        #expect(!state.workflow.hasActiveWork && !state.workflow.hasUnclaimedResult)
        state.workflow.startAgent()
        #expect(state.workflow.agentPhase == .starting)
        #expect(state.workflow.hasActiveWork)
        try #require(await eventually { state.workflow.agentPhase == .listening })
        #expect(state.workflow.hasActiveWork)
        state.workflow.finishAgentListening()
        #expect(state.workflow.hasActiveWork)
        try #require(await eventually { state.workflow.agentPhase == .answerReady })
        #expect(!state.workflow.hasActiveWork)
        #expect(state.workflow.hasUnclaimedResult)
        state.workflow.startsPaused = true
        state.workflow.startDictation()
        #expect(state.workflow.agentPhase == .answerReady)
        state.workflow.dismissAnswer()
        #expect(!state.workflow.hasActiveWork && !state.workflow.hasUnclaimedResult)
    }
}

@MainActor
private func eventually(_ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(2)
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
