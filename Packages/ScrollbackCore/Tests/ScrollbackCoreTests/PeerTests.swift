import CryptoKit
import Foundation
import Network
import Testing
@testable import ScrollbackCore

private let now = Date(timeIntervalSince1970: 1_760_000_000)

private let sample = [
    Session(device: .iphone, bundleID: "com.burbn.instagram", start: now.addingTimeInterval(-600), end: now.addingTimeInterval(-300), reason: .notification),
    Session(device: .mac, bundleID: "com.apple.Safari", start: now.addingTimeInterval(-200.25), end: now.addingTimeInterval(-10.5), reason: nil),
]

private func tempURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appending(path: "scrollback-peer-\(UUID().uuidString)/\(name)")
}

@Suite struct PeerRequestTests {
    let key = SymmetricKey(size: .bits256)

    @Test func roundTripsThroughJSON() throws {
        let request = PeerRequest.make(since: now.addingTimeInterval(-86_400), key: key, now: now)
        let decoded = try JSONDecoder().decode(PeerRequest.self, from: JSONEncoder().encode(request))
        #expect(decoded == request)
        #expect(decoded.verify(key: key, now: now))
    }

    @Test func rejectsWrongKey() {
        let request = PeerRequest.make(since: now, key: key, now: now)
        #expect(!request.verify(key: SymmetricKey(size: .bits256), now: now))
    }

    @Test func rejectsTamperedSince() {
        let request = PeerRequest.make(since: now, key: key, now: now)
        let tampered = PeerRequest(since: request.since - 86_400, sentAt: request.sentAt, auth: request.auth)
        #expect(!tampered.verify(key: key, now: now))
    }

    @Test func rejectsStaleOrFutureRequests() {
        let request = PeerRequest.make(since: now, key: key, now: now)
        #expect(request.verify(key: key, now: now.addingTimeInterval(PeerProtocol.clockSkewTolerance)))
        #expect(!request.verify(key: key, now: now.addingTimeInterval(PeerProtocol.clockSkewTolerance + 1)))
        #expect(!request.verify(key: key, now: now.addingTimeInterval(-PeerProtocol.clockSkewTolerance - 1)))
    }
}

@Suite struct PeerResponseTests {
    let key = SymmetricKey(size: .bits256)

    @Test func sealAndOpenPreserveSessions() throws {
        let request = PeerRequest.make(since: now, key: key, now: now)
        let opened = try PeerResponse.open(PeerResponse.seal(sample, for: request, key: key), for: request, key: key)
        #expect(opened == sample)
        #expect(opened.map(\.id) == sample.map(\.id))
    }

    @Test func openFailsWithWrongKey() throws {
        let request = PeerRequest.make(since: now, key: key, now: now)
        let sealed = try PeerResponse.seal(sample, for: request, key: key)
        #expect(throws: (any Error).self) { try PeerResponse.open(sealed, for: request, key: SymmetricKey(size: .bits256)) }
    }

    @Test func openFailsForADifferentRequest() throws {
        let original = PeerRequest.make(since: now, key: key, now: now)
        let later = PeerRequest.make(since: now, key: key, now: now.addingTimeInterval(1))
        let sealed = try PeerResponse.seal(sample, for: original, key: key)
        #expect(throws: (any Error).self) { try PeerResponse.open(sealed, for: later, key: key) }
    }
}

@Suite struct PeerFrameTests {
    @Test func prefixesBigEndianLength() {
        let framed = PeerFrame.frame(Data(repeating: 7, count: 300))
        #expect(Array(framed.prefix(4)) == [0, 0, 1, 44])
        #expect(PeerFrame.length(fromHeader: framed.prefix(4)) == 300)
    }

    @Test func rejectsShortHeader() {
        #expect(PeerFrame.length(fromHeader: Data([0, 1])) == nil)
    }
}

@Suite struct PeerKeyTests {
    @Test func createsKeyOnceWithPrivatePermissions() throws {
        let url = tempURL("peer.key")
        let first = try PeerKey.loadOrCreateOnMac(at: url)
        let second = try PeerKey.loadOrCreateOnMac(at: url)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(first == second)
        #expect(permissions == 0o600)
    }

    @Test func decodeRejectsWrongLength() {
        #expect(PeerKey.decode("") == nil)
        #expect(PeerKey.decode(Data(repeating: 1, count: 16).base64EncodedString()) == nil)
        #expect(PeerKey.decode(Data(repeating: 1, count: 32).base64EncodedString() + "\n") != nil)
    }
}

@Suite(.serialized, .timeLimit(.minutes(1))) struct PeerSyncTests {
    @Test func clientPullsSessionsFromServer() async throws {
        let key = SymmetricKey(size: .bits256)
        let macStore = try SessionStore(url: tempURL("mac.sqlite"))
        try await macStore.upsert(sample)
        let (server, port) = try await startServer(store: macStore, key: key)
        defer { server.stop() }

        let phoneStore = try SessionStore(url: tempURL("phone.sqlite"))
        let inserted = try await PeerClient(key: key).sync(into: phoneStore, endpoint: .hostPort(host: "127.0.0.1", port: port))

        #expect(inserted == sample.count)
        #expect(try await phoneStore.unsynced().isEmpty)
        let window = DateInterval(start: now.addingTimeInterval(-3_600), end: now)
        #expect(try await phoneStore.sessions(overlapping: window) == sample)
    }

    @Test func serverIgnoresClientWithWrongKey() async throws {
        let macStore = try SessionStore(url: tempURL("mac.sqlite"))
        try await macStore.upsert(sample)
        let (server, port) = try await startServer(store: macStore, key: SymmetricKey(size: .bits256))
        defer { server.stop() }

        let phoneStore = try SessionStore(url: tempURL("phone.sqlite"))
        await #expect(throws: PeerSyncError.rejected) {
            try await PeerClient(key: SymmetricKey(size: .bits256)).sync(into: phoneStore, endpoint: .hostPort(host: "127.0.0.1", port: port))
        }
        #expect(try await phoneStore.count() == 0)
    }

    @Test func storeFiltersByEnd() async throws {
        let store = try SessionStore(url: tempURL("mac.sqlite"))
        try await store.upsert(sample)
        #expect(try await store.sessions(endingAfter: now.addingTimeInterval(-100)).map(\.bundleID) == ["com.apple.Safari"])
    }

    private func startServer(store: SessionStore, key: SymmetricKey) async throws -> (PeerServer, NWEndpoint.Port) {
        let (statuses, continuation) = AsyncStream.makeStream(of: PeerServer.Status.self)
        let server = PeerServer(store: store, key: key) { continuation.yield($0) }
        try server.start()
        for await status in statuses {
            if status == .waiting { break }
            if case .failed(let message) = status { Issue.record("Listener failed: \(message)") }
        }
        return (server, try #require(server.port))
    }
}
