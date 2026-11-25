import CryptoKit
import Foundation
import Network
import Security
import XCTest
@testable import NexusCore

final class LocalServerTests: XCTestCase {
    func testListenerUsesAnAvailablePortWhenRequestedPortIsTaken() throws {
        let identity = try TLSIdentity.ephemeral()
        let original = LocalServer(identity: identity, id: Wire.id(), name: "Original", peers: []) { _ in }
        let fallback = LocalServer(identity: identity, id: Wire.id(), name: "Fallback", peers: []) { _ in }
        defer { original.stop(); fallback.stop() }

        let listening = expectation(description: "first listener occupies its port")
        original.onUpdate = {
            guard original.port != nil else { return }
            original.onUpdate = nil
            listening.fulfill()
        }
        original.start(port: 0, advertise: false)
        wait(for: [listening], timeout: 8)
        let occupiedPort = try XCTUnwrap(original.port)

        let recovered = expectation(description: "second listener opens a different port")
        fallback.onUpdate = {
            guard fallback.port != nil else { return }
            fallback.onUpdate = nil
            recovered.fulfill()
        }
        fallback.start(port: occupiedPort, advertise: false)
        wait(for: [recovered], timeout: 8)

        let port = try XCTUnwrap(fallback.port)
        XCTAssertNil(fallback.failure)
        XCTAssertNotEqual(port, occupiedPort)
        XCTAssertEqual(original.port, occupiedPort)
        XCTAssertEqual(try fallback.invite(host: "127.0.0.1").port, port)
    }

    func testTLSConsentReconnectAndRevocation() throws {
        let identity = try TLSIdentity.ephemeral()
        var persisted: [Peer] = []
        let server = LocalServer(identity: identity, id: Wire.id(), name: "Mac de teste", peers: []) {
            persisted = $0
        }
        let started = expectation(description: "open local TLS listener")
        server.onUpdate = { if server.port != nil { started.fulfill(); server.onUpdate = nil } }
        server.start(port: 0, advertise: false)
        defer { server.stop() }
        wait(for: [started], timeout: 8)
        let invitation = try server.invite(host: "127.0.0.1")

        let wrong = client(port: invitation.port, pin: Data(repeating: 0, count: 32))
        let rejectedPin = expectation(description: "TLS rejects wrong certificate fingerprint")
        wrong.onClose = { rejectedPin.fulfill() }
        wrong.start()
        wait(for: [rejectedPin], timeout: 15)
        XCTAssertNil(server.pending)

        let id = Wire.id()
        let credential = try Wire.random(32).base64EncodedString()
        let pin = try XCTUnwrap(Data(base64Encoded: invitation.pin))
        let connected = client(port: invitation.port, pin: pin)
        let pending = expectation(description: "pairing awaits Mac consent")
        let accepted = expectation(description: "Mac accepts the new phone")
        let revoked = expectation(description: "Mac closes a revoked connection")
        server.onUpdate = {
            if server.pending != nil {
                XCTAssertTrue(persisted.isEmpty)
                XCTAssertFalse(server.online.contains(id))
                pending.fulfill()
                server.onUpdate = nil
            }
        }
        connected.onMessage = { message in
            if message.type == "accepted" { accepted.fulfill() }
            if message.type == "reject" { revoked.fulfill() }
        }
        var pair = auth("pair", server: server.id, name: id, credential: credential)
        pair.name = "Android de teste"
        pair.model = "Modelo de teste"
        pair.token = invitation.token
        connected.start()
        connected.send(pair)
        wait(for: [pending], timeout: 8)
        server.confirm(id, allow: true)
        wait(for: [accepted], timeout: 8)
        XCTAssertEqual(persisted.map(\.id), [id])

        let resumed = expectation(description: "saved credential resumes the session")
        var nextRevoked = false
        let reconnect = client(port: invitation.port, pin: pin)
        reconnect.onMessage = { message in
            if message.type == "accepted" { resumed.fulfill() }
            if message.type == "reject", !nextRevoked { nextRevoked = true; revoked.fulfill() }
        }
        reconnect.start()
        reconnect.send(auth("resume", server: server.id, name: id, credential: credential))
        wait(for: [resumed], timeout: 8)
        XCTAssertTrue(server.online.contains(id))

        try server.revoke(id)
        wait(for: [revoked], timeout: 8)
        XCTAssertTrue(persisted.isEmpty)
        XCTAssertFalse(server.online.contains(id))

        let denied = expectation(description: "revoked credential cannot connect again")
        let disallowed = client(port: invitation.port, pin: pin)
        disallowed.onMessage = { message in
            XCTAssertEqual(message.type, "reject")
            denied.fulfill()
        }
        disallowed.start()
        disallowed.send(auth("resume", server: server.id, name: id, credential: credential))
        wait(for: [denied], timeout: 8)
    }

    private func auth(_ type: String, server: String, name: String, credential: String) -> Message {
        var message = Message(type)
        message.id = name
        message.serverId = server
        message.version = Wire.version
        message.credential = credential
        return message
    }

    private func client(port: UInt16, pin: Data) -> FramedConnection {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv13)
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, trust, complete in
            let ref = sec_trust_copy_ref(trust).takeRetainedValue()
            guard let certificate = (SecTrustCopyCertificateChain(ref) as? [SecCertificate])?.first else {
                complete(false)
                return
            }
            let digest = Data(SHA256.hash(data: SecCertificateCopyData(certificate) as Data))
            complete(digest == pin)
        }, .main)
        let address = NWEndpoint.Port(rawValue: port)!
        return FramedConnection(NWConnection(host: "127.0.0.1", port: address,
            using: NWParameters(tls: tls, tcp: NWProtocolTCP.Options())))
    }
}
