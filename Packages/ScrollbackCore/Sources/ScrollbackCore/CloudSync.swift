#if canImport(CloudKit)
import CloudKit
import Foundation

public enum CloudSyncError: Error, Equatable, LocalizedError {
    case noAccount
    case accountUnavailable(String)
    case timedOut
    case needsUpdate
    case deletedInSettings

    public var errorDescription: String? {
        switch self {
        case .noAccount: "Sign in to iCloud to sync history away from your Mac."
        case .accountUnavailable(let reason): reason
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
        switch try await container.accountStatus() {
        case .available: break
        case .noAccount: throw CloudSyncError.noAccount
        case .restricted: throw CloudSyncError.accountUnavailable("iCloud is restricted on this device (Screen Time or a profile).")
        case .temporarilyUnavailable: throw CloudSyncError.accountUnavailable("iCloud needs attention: open Settings and check your Apple Account.")
        default: throw CloudSyncError.accountUnavailable("Couldn't check iCloud. Try again in a bit.")
        }
        let user = try await container.userRecordID().recordName
        let known = try await store.cloudState(accountKey).map { String(decoding: $0, as: UTF8.self) }
        guard known != user else { return }
        try await store.resetCloudUploads()
        try await store.setCloudState(accountKey, Data(user.utf8))
    }

    static func isTransient(_ error: CKError) -> Bool {
        [.networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy].contains(error.code)
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
    static let restoredKey = "restored"
    static let restoreTokenKey = "restoreToken"
    /// Set when the person deleted Scrollback's iCloud data in Settings. Nothing is sent until
    /// they turn sync back on, so a relaunch can't quietly put their history back.
    static let deletedInSettingsKey = "deletedInSettings"

    public init() {}

    public func isPaused(_ store: SessionStore) async throws -> Bool {
        try await store.cloudState(Self.deletedInSettingsKey) != nil
    }

    public func resume(_ store: SessionStore) async throws {
        try await store.setCloudState(Self.deletedInSettingsKey, nil)
    }

    /// Returns how many days were sent or removed. Days that fail stay dirty for the next run,
    /// and don't hold back the days after them; the first such error is thrown at the end.
    public func upload(from store: SessionStore) async throws -> Int {
        let container = CloudAccess.container()
        let database = container.privateCloudDatabase
        try await CloudAccess.checkAccount(container, store: store)
        if try await isPaused(store) { throw CloudSyncError.deletedInSettings }
        if try await store.cloudState(Self.restoredKey) == nil {
            try await restore(from: database, into: store)
            try await store.setCloudState(Self.restoredKey, Data([1]))
        }
        if try await store.cloudState(Self.zoneReadyKey) == nil {
            let zone = CKRecordZone(zoneID: CloudAccess.zoneID)
            let (saved, _) = try await database.modifyRecordZones(saving: [zone], deleting: [])
            _ = try saved[zone.zoneID]?.get()
            try await store.setCloudState(Self.zoneReadyKey, Data([1]))
        }

        let coversFrom = try await store.earliestStart() ?? .distantPast
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
                record.encryptedValues[CloudHistory.asOfKey] = Date.now
                record.encryptedValues[CloudHistory.coversFromKey] = coversFrom
                batch.append(Change(day: day, digest: digest, record: record))
                bytes += payload.count
            }
            if batch.count >= Self.batchSize { try await flush() }
        }
        try await flush()
        if let firstError { throw firstError }
        return sent
    }

    /// A Mac store that's new to this iCloud account (fresh install, wiped database) first takes in
    /// what iCloud already holds. Biome only reaches back a few weeks, so without this its first
    /// upload would overwrite older or partly covered days with less than they had.
    private func restore(from database: CKDatabase, into store: SessionStore) async throws {
        // Saved after every page, so a big history that outlasts one run picks up where it stopped.
        var token = try await store.cloudState(Self.restoreTokenKey).flatMap(CloudHistoryDownloader.token(from:))
        while true {
            let changes: (modificationResultsByID: [CKRecord.ID: Result<CKDatabase.RecordZoneChange.Modification, any Error>],
                          deletions: [CKDatabase.RecordZoneChange.Deletion],
                          changeToken: CKServerChangeToken,
                          moreComing: Bool)
            do {
                changes = try await database.recordZoneChanges(inZoneWith: CloudAccess.zoneID, since: token)
            } catch let error where CloudAccess.isMissingZone(error) {
                // Nothing to take in. After a deletion in Settings this only runs once the person
                // turned sync back on, and the zone is re-created right after.
                return
            } catch let error as CKError where error.code == .changeTokenExpired && token != nil {
                token = nil
                try await store.setCloudState(Self.restoreTokenKey, nil)
                continue
            }
            for (id, result) in changes.modificationResultsByID {
                guard let day = CloudDay(recordName: id.recordName) else { continue }
                let record: CKRecord
                switch result {
                case .success(let modification): record = modification.record
                case .failure(let error as CKError) where CloudAccess.isTransient(error): throw error
                case .failure: continue
                }
                let version = (record.encryptedValues[CloudHistory.versionKey] as? NSNumber)?.int64Value ?? 0
                guard let payload = record.encryptedValues[CloudHistory.payloadKey] as? Data else { continue }
                let sessions: [Session]
                do {
                    sessions = try CloudHistory.unpack(payload, version: version)
                } catch CloudHistory.Failure.newerVersion {
                    // A newer Mac build wrote this; overwriting it with what this build knows would lose data.
                    throw CloudSyncError.needsUpdate
                } catch {
                    continue
                }
                let inDay = sessions.filter { day.contains($0.start) }
                let cloudDigest = CloudHistory.digest(of: inDay)
                try await store.insertMissing(inDay)
                // A day iCloud already has exactly as this store now does needn't be sent back.
                let merged = CloudHistory.digest(of: try await store.sessions(startingIn: day))
                if merged == cloudDigest { try await store.markCloudUploaded(day, digest: merged, ifStill: merged) }
            }
            token = changes.changeToken
            try await store.setCloudState(Self.restoreTokenKey, try CloudHistoryDownloader.data(from: changes.changeToken))
            if !changes.moreComing { return }
        }
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
        if (error as? CKError)?.code == .userDeletedZone {
            try await store.setCloudState(Self.deletedInSettingsKey, Data([1]))
            throw CloudSyncError.deletedInSettings
        }
        throw error
    }
}

/// Runs on the iPhone: applies every day the Mac sent since the last pull.
public struct CloudHistoryDownloader: Sendable {
    static let changeTokenKey = "changeToken"
    static let lastMacSaveKey = "lastMacSave"
    static let timeout: Duration = .seconds(20)

    public init() {}

    /// The newest time the Mac packed a day this phone has applied.
    public static func lastMacSave(in store: SessionStore) async -> Date? {
        guard let data = try? await store.cloudState(lastMacSaveKey), data.count == 8 else { return nil }
        return Date(timeIntervalSince1970: data.withUnsafeBytes { $0.loadUnaligned(as: Double.self) })
    }

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

            // A day that a later app version could read, or a short outage, is thrown before the
            // token is saved so the same changes come back. A day this build can never read is
            // skipped, so it can't hold back every day after it.
            for (id, result) in changes.modificationResultsByID {
                guard let day = CloudDay(recordName: id.recordName) else { continue }
                let modification: CKDatabase.RecordZoneChange.Modification
                switch result {
                case .success(let value): modification = value
                case .failure(let error as CKError) where CloudAccess.isTransient(error): throw error
                case .failure: continue
                }
                let record = modification.record
                let version = (record.encryptedValues[CloudHistory.versionKey] as? NSNumber)?.int64Value ?? 0
                guard let payload = record.encryptedValues[CloudHistory.payloadKey] as? Data else { continue }
                let sessions: [Session]
                do {
                    sessions = try CloudHistory.unpack(payload, version: version)
                } catch CloudHistory.Failure.newerVersion {
                    throw CloudSyncError.needsUpdate
                } catch {
                    continue
                }
                let asOf = record.encryptedValues[CloudHistory.asOfKey] as? Date
                let coversFrom = record.encryptedValues[CloudHistory.coversFromKey] as? Date ?? .distantPast
                added += try await store.replaceCloudDay(day, with: sessions, asOf: asOf ?? .distantFuture, coversFrom: coversFrom)
                let newest = await Self.lastMacSave(in: store) ?? .distantPast
                if let asOf, asOf > newest {
                    let seconds = asOf.timeIntervalSince1970
                    try await store.setCloudState(Self.lastMacSaveKey, withUnsafeBytes(of: seconds) { Data($0) })
                }
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
