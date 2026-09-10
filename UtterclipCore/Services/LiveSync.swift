import CloudKit
import Foundation
import os
#if canImport(UIKit)
import UIKit
#endif

/// The live channel between devices: one small CloudKit record per device, written straight
/// to the user's private database on every phase change — recording, transcribing, rewriting,
/// done (with the finished text), idle. It bypasses Core Data's export scheduler, which
/// batches and defers for tens of seconds; a direct save is on the server in about a second.
/// The Mac's `RemoteZoneWatcher` polls the same zone. History still syncs through SwiftData.
@MainActor
public enum LiveSync {
    static let zoneID = CKRecordZone.ID(zoneName: "UtterclipLive", ownerName: CKCurrentUserDefaultName)
    static let recordType = "LiveState"
    private static let database = CKContainer(identifier: SyncPreference.containerIdentifier).privateCloudDatabase
    private static let logger = Logger(subsystem: "com.ralfchille.utterclip", category: "live-sync")
    /// Writes run one after another so an older phase can never overtake a newer one.
    private static var chain: Task<Void, Never>?
    private static var zoneReady = false

    /// Another device's live state.
    public struct Remote: Equatable {
        public let deviceID: String
        public let deviceName: String
        public let phase: String
        public let updatedAt: Date
        /// The finished dictation, carried in the record itself when the phase is `done`.
        public let entry: HistoryEntry?

        public var isInProgress: Bool { ["recording", "transcribing", "rewriting"].contains(phase) }
    }

    /// Publishes this device's phase; `entry` travels with `done` so the other side can show
    /// and claim the result without waiting for History to sync.
    public static func publish(phase: String, entry: HistoryEntry?) {
        guard SyncPreference.isEnabled else { return }
        let record = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: "device-\(DeviceIdentity.id)", zoneID: zoneID))
        record["deviceID"] = DeviceIdentity.id
        record["deviceName"] = DeviceIdentity.kind
        record["phase"] = phase
        record["updatedAt"] = Date()
        if let entry {
            record["dictationID"] = entry.id.uuidString
            record["date"] = entry.date
            record["rawTranscript"] = entry.rawTranscript
            record["styledText"] = entry.styledText
            record["styleID"] = entry.styleID
        }
        let previous = chain
        chain = Task { @MainActor in
            await previous?.value
            let hold = KeepAlive.begin()
            defer { KeepAlive.end(hold) }
            await save(record, retryOnMissingZone: true)
        }
    }

    private static func save(_ record: CKRecord, retryOnMissingZone: Bool) async {
        let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        operation.savePolicy = .allKeys // this device is the only writer of its record
        operation.qualityOfService = .userInitiated
        // With the per-record result blocks, a record's own failure (zone missing, say) is
        // reported *only* there — the operation-level result still says success.
        let result: Result<Void, Error> = await withCheckedContinuation { continuation in
            var recordFailure: Error?
            operation.perRecordSaveBlock = { _, result in
                if case .failure(let error) = result { recordFailure = error }
            }
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success: continuation.resume(returning: recordFailure.map { .failure($0) } ?? .success(()))
                case .failure(let error): continuation.resume(returning: .failure(error))
                }
            }
            database.add(operation)
        }
        switch result {
        case .success:
            zoneReady = true
            logger.notice("Live state saved: \(record["phase"] as? String ?? "?", privacy: .public)")
        case .failure(let error):
            if retryOnMissingZone, Self.isMissingZone(error) {
                await createZone()
                await save(record, retryOnMissingZone: false)
            } else if retryOnMissingZone {
                // Transient (network, throttling): one more try after a moment.
                logger.notice("Live state save failed (\(error.localizedDescription, privacy: .public)); retrying.")
                try? await Task.sleep(for: .seconds(2))
                await save(record, retryOnMissingZone: false)
            } else {
                logger.error("Live state save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Zone missing, reported either at the top level or wrapped in a partial failure.
    private static func isMissingZone(_ error: Error) -> Bool {
        guard let ck = error as? CKError else { return false }
        if ck.code == .zoneNotFound || ck.code == .userDeletedZone { return true }
        if ck.code == .partialFailure, let inner = ck.partialErrorsByItemID?.values {
            return inner.contains { ($0 as? CKError).map { $0.code == .zoneNotFound || $0.code == .userDeletedZone } ?? false }
        }
        return false
    }

    private static func createZone() async {
        let operation = CKModifyRecordZonesOperation(recordZonesToSave: [CKRecordZone(zoneID: zoneID)], recordZoneIDsToDelete: nil)
        operation.qualityOfService = .userInitiated
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            operation.perRecordZoneSaveBlock = { _, result in
                if case .failure(let error) = result {
                    logger.error("Live zone creation failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            operation.modifyRecordZonesResultBlock = { result in
                if case .failure(let error) = result {
                    logger.error("Live zone creation failed: \(error.localizedDescription, privacy: .public)")
                } else {
                    logger.notice("Live zone created.")
                }
                continuation.resume()
            }
            database.add(operation)
        }
    }

    /// Parses a `LiveState` record from the zone; nil for this device's own record.
    static func remote(from record: CKRecord) -> Remote? {
        guard let deviceID = record["deviceID"] as? String, deviceID != DeviceIdentity.id else { return nil }
        var entry: HistoryEntry?
        if let idString = record["dictationID"] as? String, let id = UUID(uuidString: idString),
           let raw = record["rawTranscript"] as? String {
            entry = HistoryEntry(
                id: id, date: record["date"] as? Date ?? record["updatedAt"] as? Date ?? .now,
                rawTranscript: raw, styledText: record["styledText"] as? String,
                styleID: record["styleID"] as? String, originDevice: deviceID)
        }
        return Remote(
            deviceID: deviceID,
            deviceName: record["deviceName"] as? String ?? "iPhone",
            phase: record["phase"] as? String ?? "idle",
            updatedAt: record["updatedAt"] as? Date ?? record.modificationDate ?? .now,
            entry: entry)
    }
}

/// iOS: the phone is usually locked or put away right after a dictation; a background task
/// keeps the process alive until the live-state save (and Core Data's export) has gone out.
@MainActor
enum KeepAlive {
    #if canImport(UIKit) && !os(watchOS)
    static func begin() -> UIBackgroundTaskIdentifier {
        UIApplication.shared.beginBackgroundTask(withName: "utterclip.live-sync") { }
    }
    static func end(_ task: UIBackgroundTaskIdentifier) {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
    }
    #else
    static func begin() -> Int { 0 }
    static func end(_ task: Int) {}
    #endif
}
