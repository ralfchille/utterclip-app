import CloudKit
import Foundation
import os

/// Reads the other devices' activity and fresh dictations straight from CloudKit — the same
/// zone SwiftData mirrors into, fetched with a change token every few seconds. This is what the
/// Mac's phone indicator runs on: Core Data's own import is scheduled by the system and, for
/// an app in the background, can sit unexecuted for minutes. A change fetch with nothing new
/// costs one small request. Read-only; nothing is written here.
@MainActor
public final class RemoteZoneWatcher {
    public static let shared = RemoteZoneWatcher()
    public static let didChange = Notification.Name("utterclip.remoteZoneDidChange")

    /// Latest activity per device (other devices only).
    public private(set) var activities: [String: ActivitySync.Remote] = [:]
    /// Recent dictations from other devices, by id — enough to show and claim one before the
    /// local store has imported it.
    public private(set) var dictations: [UUID: HistoryEntry] = [:]

    private let database = CKContainer(identifier: SyncPreference.containerIdentifier).privateCloudDatabase
    private let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)
    private static let tokenKey = "remoteZoneChangeToken"
    private static let logger = Logger(subsystem: "com.ralfchille.utterclip", category: "zone-watch")
    private var timer: Timer?
    private var polling = false
    private var lastPoll = Date.distantPast
    /// Seconds between polls; the caller adjusts it (window visible vs hidden).
    public var interval: TimeInterval = 5

    private init() {}

    public func start() {
        guard timer == nil, SyncPreference.isEnabled else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Task { await poll() }
    }

    private func tick() {
        guard Date().timeIntervalSince(lastPoll) >= interval else { return }
        Task { await poll() }
    }

    /// One change fetch; parses activity and dictation records, drops the rest.
    public func poll() async {
        guard !polling else { return }
        polling = true
        lastPoll = .now
        defer { polling = false }
        let mine = DeviceIdentity.id
        var changed = false
        var expired = false
        let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        config.previousServerChangeToken = token
        let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zoneID], configurationsByRecordZoneID: [zoneID: config])
        operation.fetchAllChanges = true
        operation.qualityOfService = .userInitiated
        operation.recordWasChangedBlock = { [weak self] _, result in
            guard case .success(let record) = result else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.absorb(record, mine: mine) { changed = true }
            }
        }
        operation.recordZoneChangeTokensUpdatedBlock = { [weak self] _, newToken, _ in
            Task { @MainActor [weak self] in self?.token = newToken }
        }
        operation.recordZoneFetchResultBlock = { [weak self] _, result in
            Task { @MainActor [weak self] in
                switch result {
                case .success(let (newToken, _, _)): self?.token = newToken
                case .failure(let error):
                    if let ckError = error as? CKError, ckError.code == .changeTokenExpired { expired = true }
                    Self.logger.error("Zone fetch failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            operation.fetchRecordZoneChangesResultBlock = { _ in continuation.resume() }
            database.add(operation)
        }
        // Blocks above hop to the main actor; give them a turn before reading the flags.
        await Task.yield()
        if expired { token = nil }
        // Also notify when nothing new arrived but the freshest activity aged out, so an
        // indicator does not outlive its ten minutes.
        let current = latestRemote(within: 10 * 60)
        if changed || current != lastReported {
            lastReported = current
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    private var lastReported: ActivitySync.Remote?

    /// True when the record is one we show. Core Data mirrors entity `X` as record type
    /// `CD_X` with `CD_<attribute>` fields; UUIDs travel as strings.
    private func absorb(_ record: CKRecord, mine: String) -> Bool {
        switch record.recordType {
        case "CD_DeviceActivity":
            guard let deviceID = record["CD_deviceID"] as? String, deviceID != mine else { return false }
            let remote = ActivitySync.Remote(
                deviceID: deviceID,
                deviceName: record["CD_deviceName"] as? String ?? "iPhone",
                phase: record["CD_phase"] as? String ?? "idle",
                dictationID: (record["CD_dictationID"] as? String).flatMap(UUID.init(uuidString:)),
                updatedAt: record["CD_updatedAt"] as? Date ?? record.modificationDate ?? .now)
            if let known = activities[deviceID], known.updatedAt > remote.updatedAt { return false }
            activities[deviceID] = remote
            return true
        case "CD_Dictation":
            guard let origin = record["CD_originDevice"] as? String, origin != mine,
                  let idString = record["CD_id"] as? String, let id = UUID(uuidString: idString),
                  let date = record["CD_date"] as? Date,
                  date > Date().addingTimeInterval(-60 * 60) else { return false }
            dictations[id] = HistoryEntry(
                id: id, date: date,
                rawTranscript: record["CD_rawTranscript"] as? String ?? "",
                styledText: record["CD_styledText"] as? String,
                styleID: record["CD_styleID"] as? String,
                originDevice: origin)
            // Keep the map small: only the last hour matters.
            dictations = dictations.filter { $0.value.date > Date().addingTimeInterval(-60 * 60) }
            return true
        default:
            return false
        }
    }

    /// The other devices' most recent activity within `within` seconds.
    public func latestRemote(within: TimeInterval) -> ActivitySync.Remote? {
        activities.values
            .filter { $0.updatedAt > Date().addingTimeInterval(-within) }
            .max { $0.updatedAt < $1.updatedAt }
    }

    private var token: CKServerChangeToken? {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.tokenKey) else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
        }
        set {
            if let newValue, let data = try? NSKeyedArchiver.archivedData(withRootObject: newValue, requiringSecureCoding: true) {
                UserDefaults.standard.set(data, forKey: Self.tokenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.tokenKey)
            }
        }
    }
}
