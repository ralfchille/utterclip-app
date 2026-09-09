import Foundation
import Observation

/// On-device log of past dictations, newest first, persisted as JSON in
/// Application Support. Capped so the file can't grow without bound.
@Observable
@MainActor
public final class HistoryStore {
    public static let shared = HistoryStore()

    public private(set) var entries: [HistoryEntry] = []

    private static let maxEntries = 200
    private let fileURL: URL

    private init() {
        var support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #if os(macOS)
        // iOS hands out a per-app container; macOS shares ~/Library/Application Support,
        // so the file needs its own folder there. iOS keeps the original path so the
        // history written before the framework split stays readable.
        support.appendPathComponent(Bundle.main.bundleIdentifier ?? "Utterclip")
        #endif
        try? FileManager.default.createDirectory(
            at: support, withIntermediateDirectories: true)
        fileURL = support.appendingPathComponent("history.json")
        load()
    }

    public func add(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
        save()
    }

    /// Mutates the entry with the given id in place (e.g. attaching a rewrite
    /// or a manual edit to the dictation it belongs to). Unknown ids are ignored.
    public func update(_ id: UUID, _ mutate: (inout HistoryEntry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        mutate(&entries[index])
        save()
    }

    /// Takes `IndexSet` so a SwiftUI `onDelete` can pass its offsets straight through;
    /// removes back-to-front (SwiftUI's `remove(atOffsets:)` lives in SwiftUI itself, which
    /// the core deliberately doesn't link).
    public func delete(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where entries.indices.contains(index) {
            entries.remove(at: index)
        }
        save()
    }

    public func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    public func clear() {
        entries.removeAll()
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
