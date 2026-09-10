import CloudKit
import Foundation
import os

/// Reads the other devices' live state straight from CloudKit (the `UtterclipLive` zone that
/// `LiveSync` writes), with a change token, every couple of seconds while the window is up.
/// Read-only; drives the Mac's phone indicator.
@MainActor
public final class RemoteZoneWatcher {
    public static let shared = RemoteZoneWatcher()
    public static let didChange = Notification.Name("utterclip.remoteZoneDidChange")

    /// Latest live state per other device.
    public private(set) var remotes: [String: LiveSync.Remote] = [:]

    private let database = CKContainer(identifier: SyncPreference.containerIdentifier).privateCloudDatabase
    private static let logger = Logger(subsystem: "com.ralfchille.utterclip", category: "zone-watch")
    private var timer: Timer?
    private var polling = false
    private var lastPoll = Date.distantPast
    /// In memory only: each launch starts with a full read of the (tiny) zone.
    private var token: CKServerChangeToken?
    private var lastReported: LiveSync.Remote?
    private var lastStale = false
    private var reportedMissingZone = false
    /// Seconds between polls; the caller adjusts it (window visible vs hidden).
    public var interval: TimeInterval = 2
    /// An in-progress phase older than this means the phone has not synced since.
    public static let staleAfter: TimeInterval = 90

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

    /// One change fetch against the live zone.
    public func poll() async {
        guard !polling else { return }
        polling = true
        lastPoll = .now
        defer { polling = false }
        var changed = false
        var expired = false
        let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        config.previousServerChangeToken = token
        let zoneID = LiveSync.zoneID
        let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zoneID], configurationsByRecordZoneID: [zoneID: config])
        operation.fetchAllChanges = true
        operation.qualityOfService = .userInitiated
        var seen = 0
        operation.recordWasChangedBlock = { [weak self] _, result in
            guard case .success(let record) = result, record.recordType == LiveSync.recordType else { return }
            Task { @MainActor [weak self] in
                seen += 1
                guard let self, let remote = LiveSync.remote(from: record) else { return }
                if let known = self.remotes[remote.deviceID], known.updatedAt > remote.updatedAt { return }
                self.remotes[remote.deviceID] = remote
                changed = true
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
                    guard let ck = error as? CKError else { return }
                    switch ck.code {
                    case .changeTokenExpired: expired = true
                    case .zoneNotFound, .userDeletedZone:
                        if self?.reportedMissingZone == false { Self.logger.notice("Live zone does not exist yet."); self?.reportedMissingZone = true }
                    default: Self.logger.error("Live zone fetch failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            operation.fetchRecordZoneChangesResultBlock = { _ in continuation.resume() }
            database.add(operation)
        }
        await Task.yield() // the blocks above hop to the main actor first
        if seen > 0 { Self.logger.notice("Live zone: \(seen, privacy: .public) record(s) fetched, \(self.remotes.count, privacy: .public) other device(s).") }
        if expired { token = nil }
        let current = latestRemote()
        let stale = current.map { $0.isInProgress && Date().timeIntervalSince($0.updatedAt) > Self.staleAfter } ?? false
        if changed || current != lastReported || stale != lastStale {
            lastReported = current
            lastStale = stale
            if changed, let current { Self.logger.notice("Live: \(current.deviceName, privacy: .public) \(current.phase, privacy: .public)") }
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    /// The other devices' most recent live state.
    public func latestRemote() -> LiveSync.Remote? {
        remotes.values.max { $0.updatedAt < $1.updatedAt }
    }
}
