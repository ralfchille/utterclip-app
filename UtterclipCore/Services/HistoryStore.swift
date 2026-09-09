import CoreData
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

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private var remoteChangeObserver: NSObjectProtocol?

    private init() {
        let directory = Self.storeDirectory()
        let (container, syncing) = Self.makeContainer(in: directory, sync: SyncPreference.isEnabled)
        self.container = container
        self.isSyncing = syncing
        migrateLegacyFileIfNeeded(in: directory)
        refresh()
        // CloudKit imports land in the persistent store on a background context; this is the
        // signal to re-read. Debounced by the run loop: several imports in a row coalesce.
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    // MARK: - Public API (unchanged from the JSON store)

    public func add(_ entry: HistoryEntry) {
        context.insert(Dictation(
            id: entry.id, date: entry.date, rawTranscript: entry.rawTranscript,
            styledText: entry.styledText, styleID: entry.styleID))
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

    private func save() {
        do {
            try context.save()
        } catch {
            Self.logger.error("History save failed: \(error, privacy: .public)")
        }
    }

    /// Application Support: iOS hands out a per-app container; macOS shares
    /// ~/Library/Application Support, so the files get their own folder there.
    private static func storeDirectory() -> URL {
        var support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #if os(macOS)
        support.appendPathComponent(Bundle.main.bundleIdentifier ?? "Utterclip")
        #endif
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support
    }

    /// The CloudKit-backed store when sync is on, else a local one. A failure to open the
    /// synced store (no account setup, entitlement mismatch in an unsigned build) degrades
    /// to local; a failure to open any store on disk degrades to memory so the app still runs.
    private static func makeContainer(in directory: URL, sync: Bool) -> (ModelContainer, Bool) {
        let schema = Schema([Dictation.self])
        let url = directory.appendingPathComponent("Utterclip.store")
        if sync {
            let cloud = ModelConfiguration("Utterclip", schema: schema, url: url,
                                           cloudKitDatabase: .private(SyncPreference.containerIdentifier))
            if let container = try? ModelContainer(for: schema, configurations: [cloud]) {
                return (container, true)
            }
            logger.error("CloudKit-backed history store unavailable; continuing local-only.")
        }
        let local = ModelConfiguration("Utterclip", schema: schema, url: url, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: [local]) {
            return (container, false)
        }
        logger.fault("History store on disk unavailable; using an in-memory store.")
        let memory = ModelConfiguration("Utterclip", schema: schema, isStoredInMemoryOnly: true)
        return (try! ModelContainer(for: schema, configurations: [memory]), false)
    }

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
