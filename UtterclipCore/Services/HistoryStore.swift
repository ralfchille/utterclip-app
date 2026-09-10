import Foundation
import Observation
import SwiftData
import os

/// Log of past dictations, newest first. Since 1.1 it lives in a SwiftData store that
/// CloudKit keeps in step across the user's devices (their private database; nothing of
/// ours in between). The public surface is unchanged from the JSON days, so the views and
/// `RecorderViewModel` did not have to move.
@Observable
@MainActor
public final class HistoryStore {
    public static let shared = HistoryStore()

    /// Newest first. Refreshed after every local write and whenever CloudKit imports changes.
    public private(set) var entries: [HistoryEntry] = []

    /// Whether this store is attached to CloudKit (false when sync is off or the account
    /// setup failed and the store fell back to local-only).
    public private(set) var isSyncing = false

    private static let maxEntries = 200
    private static let migratedKey = "historyMigratedToSwiftData"
    private static let logger = Logger(subsystem: "com.ralfchille.utterclip", category: "history")

    private let store = CloudStore.shared
    private var context: ModelContext { store.context }
    private var changeObserver: NSObjectProtocol?

    private init() {
        isSyncing = store.isSyncing
        migrateLegacyFileIfNeeded(in: CloudStore.directory())
        refresh()
        // CloudKit imports land on a background context; the store relays them as `didChange`.
        changeObserver = NotificationCenter.default.addObserver(
            forName: CloudStore.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    // MARK: - Public API (unchanged from the JSON store)

    public func add(_ entry: HistoryEntry) {
        context.insert(Dictation(
            id: entry.id, date: entry.date, rawTranscript: entry.rawTranscript,
            styledText: entry.styledText, styleID: entry.styleID, originDevice: entry.originDevice))
        save()
        refresh()
    }

    /// Mutates the entry with the given id in place (e.g. attaching a rewrite
    /// or a manual edit to the dictation it belongs to). Unknown ids are ignored.
    public func update(_ id: UUID, _ mutate: (inout HistoryEntry) -> Void) {
        guard let stored = dictation(id: id) else { return }
        var entry = stored.entry
        mutate(&entry)
        stored.rawTranscript = entry.rawTranscript
        stored.styledText = entry.styledText
        stored.styleID = entry.styleID
        save()
        refresh()
    }

    public func delete(at offsets: IndexSet) {
        for index in offsets where entries.indices.contains(index) {
            if let stored = dictation(id: entries[index].id) { context.delete(stored) }
        }
        save()
        refresh()
    }

    public func delete(id: UUID) {
        if let stored = dictation(id: id) { context.delete(stored) }
        save()
        refresh()
    }

    public func clear() {
        for stored in fetchAll() { context.delete(stored) }
        save()
        refresh()
    }

    /// Re-reads the store. The remote-change observer covers CloudKit imports; the History
    /// screen also calls this when it opens, so it never shows a stale list.
    public func reload() {
        refresh()
    }

    /// The stored entry with this id, fresh from the store.
    public func entry(id: UUID) -> HistoryEntry? {
        dictation(id: id)?.entry
    }

    // MARK: - Store

    /// Everything, newest first, after housekeeping: duplicates by id (the same entry
    /// imported twice) collapse to the oldest copy, and the newest `maxEntries` survive.
    private func refresh() {
        var all = fetchAll()
        var seen = Set<UUID>()
        var changed = false
        for stored in all where !seen.insert(stored.id).inserted {
            context.delete(stored)
            changed = true
        }
        all = all.filter { seen.contains($0.id) }
        if all.count > Self.maxEntries {
            for stored in all[Self.maxEntries...] { context.delete(stored) }
            all = Array(all.prefix(Self.maxEntries))
            changed = true
        }
        if changed { save() }
        entries = all.map(\.entry)
    }

    private func fetchAll() -> [Dictation] {
        let descriptor = FetchDescriptor<Dictation>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        do {
            return try context.fetch(descriptor)
        } catch {
            Self.logger.error("History fetch failed: \(error, privacy: .public)")
            return []
        }
    }

    private func dictation(id: UUID) -> Dictation? {
        var descriptor = FetchDescriptor<Dictation>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func save() { store.save() }

    // MARK: - Migration from history.json (1.0)

    /// Imports the 1.0 JSON log once, then renames the file so a later launch can't import
    /// it again. The rename (rather than a delete) keeps one release worth of safety net.
    private func migrateLegacyFileIfNeeded(in directory: URL) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.migratedKey) else { return }
        let fileURL = directory.appendingPathComponent("history.json")
        defer { defaults.set(true, forKey: Self.migratedKey) }
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let legacy = try? decoder.decode([HistoryEntry].self, from: data) else {
            Self.logger.error("history.json could not be read; leaving it in place.")
            return
        }
        let existing = Set(fetchAll().map(\.id))
        for entry in legacy where !existing.contains(entry.id) {
            context.insert(Dictation(
                id: entry.id, date: entry.date, rawTranscript: entry.rawTranscript,
                styledText: entry.styledText, styleID: entry.styleID))
        }
        save()
        try? FileManager.default.moveItem(at: fileURL, to: directory.appendingPathComponent("history.json.migrated"))
        Self.logger.notice("Imported \(legacy.count, privacy: .public) dictations from history.json")
    }
}
