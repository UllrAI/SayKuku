import AppKit
import Observation
import Sparkle

/// Sparkle owns scheduling, downloads, verification and installation. Disabled outside release bundles.
@MainActor
@Observable
final class SoftwareUpdater: NSObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    var automaticChecks = true {
        didSet {
            guard let controller, controller.updater.automaticallyChecksForUpdates != automaticChecks else { return }
            controller.updater.automaticallyChecksForUpdates = automaticChecks
        }
    }
    var automaticDownloads = true {
        didSet {
            guard let controller, controller.updater.automaticallyDownloadsUpdates != automaticDownloads else { return }
            controller.updater.automaticallyDownloadsUpdates = automaticDownloads
        }
    }
    private(set) var canCheck = false
    private(set) var availableVersion: String?
    private(set) var installsOnQuit = false
    @ObservationIgnored var deferInstallation: ((@escaping () -> Void) -> Bool)?
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var pendingInstallation: UUID?

    init(defaults: UserDefaults) {
        Self.migratePreferences(defaults)
        super.init()
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        automaticChecks = controller.updater.automaticallyChecksForUpdates
        automaticDownloads = controller.updater.automaticallyDownloadsUpdates
        observations = [
            controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
                let value = change.newValue ?? false
                MainActor.assumeIsolated { self?.canCheck = value }
            },
            controller.updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] _, change in
                guard let value = change.newValue else { return }
                MainActor.assumeIsolated { self?.automaticChecks = value }
            },
            controller.updater.observe(\.automaticallyDownloadsUpdates, options: [.new]) { [weak self] _, change in
                guard let value = change.newValue else { return }
                MainActor.assumeIsolated { self?.automaticDownloads = value }
            }
        ]
    }

    func start() { controller?.startUpdater() }
    func checkManually() { controller?.checkForUpdates(nil) }

    /// Write explicit old choices once. Info.plist supplies defaults; later Sparkle choices stay authoritative.
    static func migratePreferences(_ defaults: UserDefaults) {
        guard !defaults.bool(forKey: "updates.sparkleMigrated") else { return }
        if defaults.object(forKey: "SUEnableAutomaticChecks") == nil,
           let old = defaults.object(forKey: "updates.automaticChecks") as? Bool {
            defaults.set(old, forKey: "SUEnableAutomaticChecks")
        }
        defaults.removeObject(forKey: "updates.automaticChecks")
        defaults.removeObject(forKey: "updates.skippedVersion")
        defaults.set(true, forKey: "updates.sparkleMigrated")
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        // Automatic checks never take focus from the user's typing or show a modal alert at launch.
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        availableVersion = update.displayVersionString
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        availableVersion = item.displayVersionString
        installsOnQuit = true
        // Leave install-on-quit to Sparkle. Never invoke its immediate relaunch handler automatically.
        return false
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        let token = UUID()
        pendingInstallation = token
        let deferred = deferInstallation? { [weak self] in
            guard self?.pendingInstallation == token else { return }
            self?.pendingInstallation = nil
            installHandler()
        } ?? false
        if !deferred { pendingInstallation = nil }
        return deferred
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        pendingInstallation = nil
        installsOnQuit = false
        availableVersion = nil
    }
}
