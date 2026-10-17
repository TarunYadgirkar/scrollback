#if canImport(CloudKit)
import CloudKit
import Foundation

public enum CloudSyncError: Error, Equatable, LocalizedError {
    case noAccount
    case timedOut
    case needsUpdate

    public var errorDescription: String? {
        switch self {
        case .noAccount: "Sign in to iCloud to sync history away from your Mac."
        case .timedOut: "iCloud didn't answer. Try again in a bit."
        case .needsUpdate: "Your Mac sent history in a newer format. Update Scrollback on this iPhone."
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
    static let zoneReadyKey = "zoneReady"

    public init() {}

    /// Returns how many days were sent or removed.
    public func upload(from store: SessionStore) async throws -> Int {
        let container = CloudAccess.container()
        let database = container.privateCloudDatabase
        try await CloudAccess.checkAccount(container, store: store)
        if try await store.cloudState(Self.zoneReadyKey) == nil {
            _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: CloudAccess.zoneID)], deleting: [])
            try await store.setCloudState(Self.zoneReadyKey, Data([1]))
        }

        var batch: [Change] = []
        var sent = 0
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
                let record = CKRecord(recordType: CloudHistory.recordType, recordID: CKRecord.ID(recordName: day.recordName, zoneID: CloudAccess.zoneID))
                record.encryptedValues[CloudHistory.payloadKey] = payload
                record.encryptedValues[CloudHistory.versionKey] = CloudHistory.version
                batch.append(Change(day: day, digest: digest, record: record))
            }
            if batch.count >= Self.batchSize {
                sent += try await send(batch, to: database, store: store)
                batch.removeAll()
            }
        }
        if !batch.isEmpty { sent += try await send(batch, to: database, store: store) }
        return sent
    }

    private struct Change {
        let day: CloudDay
        let digest: String?
        let record: CKRecord?
    }

    private func send(_ batch: [Change], to database: CKDatabase, store: SessionStore) async throws -> Int {
        let saving = batch.compactMap(\.record)
        let deleting = batch.filter { $0.record == nil }.map { CKRecord.ID(recordName: $0.day.recordName, zoneID: CloudAccess.zoneID) }
        let results: (saveResults: [CKRecord.ID: Result<CKRecord, any Error>], deleteResults: [CKRecord.ID: Result<Void, any Error>])
        do {
            // The Mac is the only writer, so its copy always wins.
            results = try await database.modifyRecords(saving: saving, deleting: deleting, savePolicy: .allKeys, atomically: false)
        } catch let error where CloudAccess.isMissingZone(error) {
            try await store.resetCloudUploads()
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
                if CloudAccess.isMissingZone(error) {
                    try await store.resetCloudUploads()
                    throw error
                }
                // Left dirty, so the next refresh tries this day again.
                firstError = firstError ?? error
            case nil:
                break
            }
        }
        if let firstError { throw firstError }
        return sent
    }
}

/// Runs on the iPhone: applies every day the Mac sent since the last pull.
public struct CloudHistoryDownloader: Sendable {
    static let changeTokenKey = "changeToken"
    static let timeout: Duration = .seconds(20)

    public init() {}

    /// Returns how many sessions the store gained (negative when days shrank).
    public func pull(into store: SessionStore) async throws -> Int {
        try await PeerProtocol.withTimeout(Self.timeout, error: CloudSyncError.timedOut) {
            try await self.fetch(into: store)
        }
    }

    private func fetch(into store: SessionStore) async throws -> Int {
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
                return added
            }

            for (id, result) in changes.modificationResultsByID {
                guard let day = CloudDay(recordName: id.recordName), case .success(let modification) = result else { continue }
                let record = modification.record
                let version = (record.encryptedValues[CloudHistory.versionKey] as? NSNumber)?.int64Value ?? 0
                guard let payload = record.encryptedValues[CloudHistory.payloadKey] as? Data else { continue }
                let sessions: [Session]
                do {
                    sessions = try CloudHistory.unpack(payload, version: version)
                } catch CloudHistory.Failure.newerVersion {
                    // Stop before saving the token, so this day applies once the app is updated.
                    throw CloudSyncError.needsUpdate
                } catch {
                    continue
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
