import Network
@testable import NexusCore
import XCTest

final class PeerHostTests: XCTestCase {
    func testIPv4FromEndpoint() throws {
        func endpoint(_ host: NWEndpoint.Host) -> NWEndpoint { .hostPort(host: host, port: 1234) }
        XCTAssertEqual(FramedConnection.ipv4(from: endpoint(.ipv4(try XCTUnwrap(IPv4Address("192.168.3.31"))))), "192.168.3.31")
        XCTAssertEqual(FramedConnection.ipv4(from: endpoint(.ipv6(try XCTUnwrap(IPv6Address("::ffff:192.168.3.31"))))), "192.168.3.31")
        XCTAssertNil(FramedConnection.ipv4(from: endpoint(.ipv6(try XCTUnwrap(IPv6Address("fe80::1"))))))
        XCTAssertNil(FramedConnection.ipv4(from: endpoint(.name("celular.local", nil))))
        XCTAssertNil(FramedConnection.ipv4(from: nil))
    }
}
