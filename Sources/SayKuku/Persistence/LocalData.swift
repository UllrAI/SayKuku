import Foundation
import Observation

/// History, Memory and correction suggestions, saved to `store.json`, plus the History recordings.
/// Changes are saved shortly after they happen, but only once the stored data has loaded.
@MainActor
@Observable
final class LocalData {
    var historyEntries: [HistoryEntry] = [] { didSet { schedulePersistence() } }
    var memoryEntities: [MemoryEntity] = [] { didSet { schedulePersistence() } }
    var corrections: [CorrectionRecord] = [] { didSet { schedulePersistence() } }
    /// Correction suggestions still waiting for an answer.
    var pendingCorrections: [CorrectionRecord] { corrections.filter { $0.status == .pending } }
    private(set) var localDataIssue: LocalStore.DataIssue?
    private(set) var legacyDataURL: URL?

    /// Shows a toast in SayKuku's windows; set by `AppState`.
    @ObservationIgnored var toastHandler: (@MainActor (_ text: String, _ symbol: String) -> Void)?

    @ObservationIgnored private let store: LocalStore
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var didStartLoading = false
    @ObservationIgnored private var isLoaded = false
    @ObservationIgnored private var persistenceGeneration = 0
    @ObservationIgnored private let persistenceDelay: Duration
    @ObservationIgnored private var persistenceTask: Task<Void, Never>?

    init(store: LocalStore, settings: AppSettings, persistenceDelay: Duration) {
        self.store = store
        self.settings = settings
        self.persistenceDelay = persistenceDelay
    }

    func commitMemory(_ analysis: MemoryAnalysis, selectedIDs: Set<UUID>) {
        memoryEntities = MemoryPipeline.commit(analysis: analysis, selectedIDs: selectedIDs, existing: memoryEntities)
    }

    /// Returns why the item couldn't be saved, or `nil` once it's added.
    func addMemory(name: String, type: EntityType, detail: String? = nil, aliases: [String] = []) -> MemorySaveError? {
        if let error = insertMemory(MemoryEntity(name: name, detail: detail ?? "", type: type, aliases: aliases)) {
            return error
        }
        showToast(localized("Remembered"), symbol: "checkmark.circle.fill")
        return nil
    }

    /// Adds the item without a toast; returns why it couldn't be added.
    private func insertMemory(_ candidate: MemoryEntity) -> MemorySaveError? {
        if let error = validateMemory(candidate) { return error }
        memoryEntities.insert(candidate, at: 0)
        return nil
    }

    /// Returns why the edit couldn't be saved, or `nil` once it's applied.
    func updateMemory(
        id: UUID,
        name: String,
        type: EntityType,
        detail: String,
        aliases: [String]
    ) -> MemorySaveError? {
        // The item was removed elsewhere; there is nothing left to update.
        guard let index = memoryEntities.firstIndex(where: { $0.id == id }) else { return nil }

        let candidate = MemoryEntity(
            id: id,
            name: name,
            detail: detail,
            type: type,
            aliases: aliases,
            source: memoryEntities[index].source,
            createdAt: memoryEntities[index].createdAt
        )
        if let error = validateMemory(candidate) { return error }

        memoryEntities[index] = candidate
        showToast(localized("Memory updated"), symbol: "checkmark.circle.fill")
        return nil
    }

    func removeMemory(id: UUID) {
        memoryEntities.removeAll { $0.id == id }
        showToast(localized("Deleted"), symbol: "trash")
    }

    func validateMemory(_ candidate: MemoryEntity) -> MemorySaveError? {
        guard !candidate.normalizedKey.isEmpty else { return .emptyName }
        if let existing = memoryEntities.first(where: { $0.id != candidate.id && $0.normalizedKey == candidate.normalizedKey }) {
            return .duplicate(existingName: existing.name)
        }
        return nil
    }

    func acceptCorrection(_ id: UUID) {
        guard let index = corrections.firstIndex(where: { $0.id == id }) else { return }
        corrections[index].status = .accepted
        let record = corrections[index]
        memoryEntities = MemoryPipeline.learn(
            record.raw, as: record.corrected, clue: record.clue, into: memoryEntities
        )
    }

    func ignoreCorrection(_ id: UUID) {
        if let index = corrections.firstIndex(where: { $0.id == id }) { corrections[index].status = .ignored }
    }

    /// Counts a correction the user just made. Until it has been asked about twice, returns it when
    /// `canPrompt` allows asking now, counted as asked.
    func recordCorrection(
        _ change: CorrectionCandidate, app: String, windowTitle: String, canPrompt: Bool
    ) -> CorrectionRecord? {
        // The clue goes to Qwen with later prompts, so it follows the Window Title privacy setting.
        let title = settings.windowTitleAllowed ? windowTitle.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let index: Int
        if let existing = corrections.firstIndex(where: { $0.raw == change.before && $0.corrected == change.after }) {
            index = existing
            corrections[index].count += 1
            corrections[index].lastSeenAt = .now
            corrections[index].lastApp = app
            corrections[index].lastWindowTitle = title
        } else {
            corrections.append(CorrectionRecord(
                raw: change.before, corrected: change.after, lastApp: app, lastWindowTitle: title
            ))
            index = corrections.index(before: corrections.endIndex)
        }
        guard corrections[index].shouldPrompt, canPrompt else { return nil }
        corrections[index].promptCount += 1
        return corrections[index]
    }

    func audio(for entry: HistoryEntry) async throws -> Data {
        guard let filename = entry.audioFilename else { throw LocalStoreError.invalidAudioFilename }
        return try await store.audio(named: filename)
    }

    func toggleHistoryStar(_ id: UUID) {
        guard let index = historyEntries.firstIndex(where: { $0.id == id }) else { return }
        historyEntries[index].isStarred.toggle()
    }

    func deleteHistoryEntry(_ id: UUID) {
        removeHistory { $0.id == id }
    }

    func clearHistory(keepingStarred: Bool) {
        removeHistory { !keepingStarred || !$0.isStarred }
        showToast(
            keepingStarred
                ? localized("History cleared. Starred items were kept.")
                : localized("History cleared"),
            symbol: "trash"
        )
    }

    func dismissLocalDataIssue() { localDataIssue = nil }

    func dismissLegacyDataNotice() {
        legacyDataURL = nil
        settings.legacyDataNoticeDismissed = true
    }

    /// Adds a History entry for a recording from `snapshot`; nil when History is off or the target is sensitive.
    func beginHistoryEntry(mode: HistoryMode, recording: AudioCapture.Recording, snapshot: TextTargetSnapshot?) -> UUID? {
        guard settings.historyRetention != .off, let snapshot, !snapshot.isSensitive else { return nil }
        let id = UUID()
        historyEntries.insert(HistoryEntry(
            id: id, mode: mode, app: snapshot.appName, durationSeconds: recording.duration,
            input: "", output: "", status: .processing
        ), at: 0)
        cleanExpiredHistory()
        return id
    }

    /// Saves the recording, if recordings are kept, and the entry it belongs to; false when either failed.
    func persistHistoryAudio(_ recording: AudioCapture.Recording, historyID: UUID?) async -> Bool {
        guard let historyID else { return true }
        var saveFailed = false
        if settings.storeVoiceAudio, !recording.wav.isEmpty {
            do {
                let filename = try await store.saveAudio(recording.wav, id: historyID)
                if historyEntries.contains(where: { $0.id == historyID }) {
                    updateHistory(historyID, audioFilename: filename)
                } else {
                    // The entry was deleted while its recording was being saved.
                    try? await store.removeAudio(named: filename)
                }
            } catch {
                saveFailed = true
            }
        }
        do {
            try await persistCurrentState()
        } catch {
            saveFailed = true
        }
        return !saveFailed
    }

    func updateHistory(
        _ id: UUID?, input: String? = nil, output: String? = nil,
        audioFilename: String? = nil, status: HistoryStatus? = nil, errorMessage: String? = nil
    ) {
        guard let id, let index = historyEntries.firstIndex(where: { $0.id == id }) else { return }
        if let input { historyEntries[index].input = input }
        if let output { historyEntries[index].output = output }
        if let audioFilename { historyEntries[index].audioFilename = audioFilename }
        if let status {
            let current = historyEntries[index].status
            if current == .processing || current == .awaitingConfirmation {
                historyEntries[index].status = status
                historyEntries[index].errorMessage = errorMessage
            }
        } else if let errorMessage {
            historyEntries[index].errorMessage = errorMessage
        }
    }

    /// Earlier builds saved these placeholders as detail; clear them so they stay out of the UI and prompts.
    private static let legacyPlaceholderDetails: Set<String> = ["手动添加", "Added manually", "来自纠正记忆", "From correction memory"]

    func loadStoredData() async {
        guard !didStartLoading else { return }
        didStartLoading = true
        localDataIssue = await store.dataIssue
        if !settings.legacyDataNoticeDismissed {
            legacyDataURL = await store.legacyEncryptedDataURL()
        }
        let snapshot: LocalStore.Snapshot
        do {
            snapshot = try await store.load()
        } catch {
            showToast(
                localized("Couldn’t read local data, so new changes won’t be saved. See History for details."),
                symbol: "exclamationmark.triangle.fill"
            )
            return
        }
        historyEntries = Self.merging(historyEntries, Self.recoveringInterruptedHistory(
            snapshot.history,
            message: localized("SayKuku quit before this finished")
        )).sorted { $0.createdAt > $1.createdAt }
        memoryEntities = Self.merging(memoryEntities, snapshot.entities.map { entity in
            var entity = entity
            if Self.legacyPlaceholderDetails.contains(entity.detail) { entity.detail = "" }
            return entity
        })
        corrections = Self.merging(corrections, snapshot.corrections)
        cleanExpiredHistory()
        // Saving before every array is in place would replace the stored data with part of it.
        isLoaded = true
        migrateLegacyCustomTerms()
        schedulePersistence()
        if localDataIssue != nil {
            showToast(
                localized("There was a problem reading local data. The original file was backed up. See History for details."),
                symbol: "exclamationmark.triangle.fill"
            )
        }
    }

    /// Earlier builds kept custom words in defaults; they now live in Memory as terms.
    /// Runs once Memory has loaded, so words already saved there are skipped as duplicates.
    private func migrateLegacyCustomTerms() {
        guard let terms = settings.takeLegacyCustomTerms() else { return }
        for term in terms { _ = insertMemory(MemoryEntity(name: term, type: .term)) }
    }

    /// Keeps records added while loading; stored records fill in the rest.
    private static func merging<Record: Identifiable>(_ current: [Record], _ stored: [Record]) -> [Record] {
        let currentIDs = Set(current.map(\.id))
        return current + stored.filter { !currentIDs.contains($0.id) }
    }

    /// Entries still processing at launch were cut off by a quit or crash; a confirmation card
    /// cannot be restored, so its action is cancelled. Keep the audio for retry where applicable.
    nonisolated static func recoveringInterruptedHistory(_ entries: [HistoryEntry], message: String) -> [HistoryEntry] {
        entries.map { entry in
            guard entry.status == .processing || entry.status == .awaitingConfirmation else { return entry }
            var recovered = entry
            recovered.status = entry.status == .processing ? .failed : .cancelled
            recovered.errorMessage = entry.status == .processing ? message : nil
            return recovered
        }
    }

    func cleanExpiredHistory() {
        guard let days = settings.historyRetention.days,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) else { return }
        removeHistory { !$0.isStarred && $0.createdAt < cutoff }
    }

    /// Removes matching entries and deletes their recordings.
    private func removeHistory(where shouldRemove: (HistoryEntry) -> Bool) {
        let removed = historyEntries.filter(shouldRemove)
        guard !removed.isEmpty else { return }
        historyEntries.removeAll(where: shouldRemove)
        let filenames = removed.compactMap(\.audioFilename)
        guard !filenames.isEmpty else { return }
        Task { [store] in
            for filename in filenames { try? await store.removeAudio(named: filename) }
        }
    }

    /// Coalesces a burst of changes, such as the several updates one dictation makes, into one write.
    private func schedulePersistence() {
        guard isLoaded else { return }
        persistenceTask?.cancel()
        persistenceTask = Task { [weak self, persistenceDelay] in
            do { try await Task.sleep(for: persistenceDelay) } catch { return }
            await self?.flushPersistence()
        }
    }

    /// Writes pending changes now and reports whether they were saved. Quitting waits for this.
    @discardableResult
    func flushPersistence() async -> Bool {
        do {
            try await persistCurrentState()
            return true
        } catch {
            showToast(
                localized("Couldn’t save your data, so recent changes may be lost. Check your available storage."),
                symbol: "exclamationmark.triangle.fill"
            )
            return false
        }
    }

    private func persistCurrentState() async throws {
        persistenceTask?.cancel()
        persistenceTask = nil
        guard let snapshot = nextPersistedSnapshot() else { return }
        try await store.replace(snapshot.value, generation: snapshot.generation)
    }

    /// The state to save, numbered so an older write never replaces a newer one; nil until stored data has loaded.
    private func nextPersistedSnapshot() -> (value: LocalStore.Snapshot, generation: Int)? {
        guard isLoaded else { return nil }
        persistenceGeneration += 1
        let value = LocalStore.Snapshot(
            history: historyEntries, entities: memoryEntities, corrections: corrections
        )
        return (value, persistenceGeneration)
    }

    private func showToast(_ text: String, symbol: String) {
        toastHandler?(text, symbol)
    }
}
