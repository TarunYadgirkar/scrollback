#if canImport(CloudKit)
import CloudKit
import Foundation

public enum CloudSyncError: Error, Equatable, LocalizedError {
    case noAccount
    case timedOut
    case needsUpdate
    case deletedInSettings

    public var errorDescription: String? {
        switch self {
        case .noAccount: "Sign in to iCloud to sync history away from your Mac."
        case .timedOut: "iCloud didn't answer. Try again in a bit."
        case .needsUpdate: "Your Mac sent history in a newer format. Update Scrollback on this iPhone."
        case .deletedInSettings: "Scrollback's iCloud data was deleted in Settings."
        }
    }
}

/// History travels through the person's own private iCloud database only. Every payload
/// sits in encrypted values, which iCloud encrypts with keys from their own keychain.
enum CloudAccess {
    static let accountKey = "account"
    static let zoneID = CKRecordZone.ID(zoneName: CloudHistory.zoneName, ownerName: CKCurrentUserDefaultName)

    static func container() -> CKContainer { CKContainer(identifier: CloudHistory.containerID) }

    /// Throws unless iCloud is usable, and starts over when the signed-in account changed,
    /// since what the old account holds says nothing about the new one.
    static func checkAccount(_ container: CKContainer, store: SessionStore) async throws {
        guard try await container.accountStatus() == .available else { throw CloudSyncError.noAccount }
        let user = try await container.userRecordID().recordName
        let known = try await store.cloudState(accountKey).map { String(decoding: $0, as: UTF8.self) }
        guard known != user else { return }
        try await store.resetCloudUploads()
        try await store.setCloudState(accountKey, Data(user.utf8))
    }

    static func isMissingZone(_ error: any Error) -> Bool {
        guard let error = error as? CKError else { return false }
        return error.code == .zoneNotFound || error.code == .userDeletedZone
    }
}

/// Runs on the Mac: sends each day whose sessions changed since its last upload.
public struct CloudHistoryUploader: Sendable {
    static let batchSize = 50
    /// CloudKit refuses requests over about 2 MB; one record is at most `CloudHistory.maxPayloadBytes`.
    static let batchBytes = 1_000_000
    static let zoneReadyKey = "zoneReady"

    public init() {}

    /// Returns how many days were sent or removed. Days that fail stay dirty for the next run,
    /// and don't hold back the days after them; the first such error is thrown at the end.
    public func upload(from store: SessionStore) async throws -> Int {
        let container = CloudAccess.container()
        let database = container.privateCloudDatabase
        try await CloudAccess.checkAccount(container, store: store)
        if try await store.cloudState(Self.zoneReadyKey) == nil {
            let zone = CKRecordZone(zoneID: CloudAccess.zoneID)
            let (saved, _) = try await database.modifyRecordZones(saving: [zone], deleting: [])
            _ = try saved[zone.zoneID]?.get()
            try await store.setCloudState(Self.zoneReadyKey, Data([1]))
        }

        var batch: [Change] = []
        var bytes = 0
        var sent = 0
        var firstError: (any Error)?
        func flush() async throws {
            guard !batch.isEmpty else { return }
            let result = try await send(batch, to: database, store: store)
            sent += result.sent
            firstError = firstError ?? result.error
            batch.removeAll()
            bytes = 0
        }

        for day in try await store.cloudDirtyDays() {
            let sessions = try await store.sessions(startingIn: day)
            let digest = CloudHistory.digest(of: sessions)
            let previous = try await store.cloudDigest(for: day)
            guard digest != previous else {
                try await store.markCloudUploaded(day, digest: previous, ifStill: digest)
                continue
            }
            if digest == nil {
                batch.append(Change(day: day, digest: nil, record: nil))
            } else {
                // A day too big for one record stays dirty and is retried; the rest still go.
                guard let payload = try? CloudHistory.pack(sessions) else { continue }
                if bytes + payload.count > Self.batchBytes { try await flush() }
                let record = CKRecord(recordType: CloudHistory.recordType, recordID: CKRecord.ID(recordName: day.recordName, zoneID: CloudAccess.zoneID))
                record.encryptedValues[CloudHistory.payloadKey] = payload
                record.encryptedValues[CloudHistory.versionKey] = CloudHistory.version
                batch.append(Change(day: day, digest: digest, record: record))
                bytes += payload.count
            }
            if batch.count >= Self.batchSize { try await flush() }
        }
        try await flush()
        if let firstError { throw firstError }
        return sent
    }

    private struct Change {
        let day: CloudDay
        let digest: String?
        let record: CKRecord?
    }

    /// Errors for single days come back as `error`; errors that stop every day are thrown.
    private func send(_ batch: [Change], to database: CKDatabase, store: SessionStore) async throws -> (sent: Int, error: (any Error)?) {
        let saving = batch.compactMap(\.record)
        let deleting = batch.filter { $0.record == nil }.map { CKRecord.ID(recordName: $0.day.recordName, zoneID: CloudAccess.zoneID) }
        let results: (saveResults: [CKRecord.ID: Result<CKRecord, any Error>], deleteResults: [CKRecord.ID: Result<Void, any Error>])
        do {
            // The Mac is the only writer, so its copy always wins.
            results = try await database.modifyRecords(saving: saving, deleting: deleting, savePolicy: .allKeys, atomically: false)
        } catch let error as CKError where error.code == .limitExceeded && batch.count > 1 {
            let half = batch.count / 2
            let first = try await send(Array(batch[..<half]), to: database, store: store)
            let second = try await send(Array(batch[half...]), to: database, store: store)
            return (first.sent + second.sent, first.error ?? second.error)
        } catch let error as CKError where error.code == .limitExceeded {
            return (0, error)
        } catch {
            try await handleMissingZone(error, store: store)
            throw error
        }

        var sent = 0
        var firstError: (any Error)?
        for change in batch {
            let id = CKRecord.ID(recordName: change.day.recordName, zoneID: CloudAccess.zoneID)
            let outcome: Result<Void, any Error>? = change.record == nil
                ? results.deleteResults[id]
                : results.saveResults[id].map { $0.map { _ in () } }
            switch outcome {
            case .success?:
                try await store.markCloudUploaded(change.day, digest: change.digest, ifStill: change.digest)
                sent += 1
            case .failure(let error as CKError)? where change.record == nil && error.code == .unknownItem:
                try await store.markCloudUploaded(change.day, digest: nil, ifStill: nil)
            case .failure(let error)?:
                try await handleMissingZone(error, store: store)
                // Left dirty, so the next run tries this day again.
                firstError = firstError ?? error
            case nil:
                break
            }
        }
        return (sent, firstError)
    }

    private func handleMissingZone(_ error: any Error, store: SessionStore) async throws {
        guard CloudAccess.isMissingZone(error) else { return }
        // Forget what iCloud held, so a later run re-creates the zone and sends every day again.
        try await store.resetCloudUploads()
        if (error as? CKError)?.code == .userDeletedZone { throw CloudSyncError.deletedInSettings }
        throw error
    }
}

/// Runs on the iPhone: applies every day the Mac sent since the last pull.
public struct CloudHistoryDownloader: Sendable {
    static let changeTokenKey = "changeToken"
    static let timeout: Duration = .seconds(20)

    public init() {}

    /// Returns how many sessions the store gained (negative when days shrank), or nil
    /// when iCloud holds nothing from the Mac yet.
    public func pull(into store: SessionStore) async throws -> Int? {
        try await PeerProtocol.withTimeout(Self.timeout, error: CloudSyncError.timedOut) {
            try await self.fetch(into: store)
        }
    }

    private func fetch(into store: SessionStore) async throws -> Int? {
        let container = CloudAccess.container()
        let database = container.privateCloudDatabase
        try await CloudAccess.checkAccount(container, store: store)

        var token = try await store.cloudState(Self.changeTokenKey).flatMap(Self.token(from:))
        var restarted = false
        var added = 0
        while true {
            try Task.checkCancellation()
            let changes: (modificationResultsByID: [CKRecord.ID: Result<CKDatabase.RecordZoneChange.Modification, any Error>],
                          deletions: [CKDatabase.RecordZoneChange.Deletion],
                          changeToken: CKServerChangeToken,
                          moreComing: Bool)
            do {
                changes = try await database.recordZoneChanges(inZoneWith: CloudAccess.zoneID, since: token)
            } catch let error as CKError where error.code == .changeTokenExpired && !restarted {
                restarted = true
                token = nil
                continue
            } catch let error where CloudAccess.isMissingZone(error) {
                // The Mac hasn't sent anything yet (or the zone was wiped): nothing to apply.
                try await store.setCloudState(Self.changeTokenKey, nil)
                return added == 0 ? nil : added
            }

            // Anything that stops a day applying is thrown before the token is saved, so the
            // same changes come back next time instead of that day being skipped for good.
            for (id, result) in changes.modificationResultsByID {
                guard let day = CloudDay(recordName: id.recordName) else { continue }
                let record = try result.get().record
                let version = (record.encryptedValues[CloudHistory.versionKey] as? NSNumber)?.int64Value ?? 0
                guard let payload = record.encryptedValues[CloudHistory.payloadKey] as? Data else { continue }
                let sessions: [Session]
                do {
                    sessions = try CloudHistory.unpack(payload, version: version)
                } catch {
                    throw CloudSyncError.needsUpdate
                }
                added += try await store.replaceCloudDay(day, with: sessions)
            }
            for deletion in changes.deletions {
                guard let day = CloudDay(recordName: deletion.recordID.recordName) else { continue }
                added += try await store.replaceCloudDay(day, with: [])
            }
            token = changes.changeToken
            try await store.setCloudState(Self.changeTokenKey, try Self.data(from: changes.changeToken))
            if !changes.moreComing { return added }
        }
    }

    static func token(from data: Data) -> CKServerChangeToken? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    static func data(from token: CKServerChangeToken) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }
}
#endif
