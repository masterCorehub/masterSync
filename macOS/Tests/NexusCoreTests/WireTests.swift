import XCTest
@testable import NexusCore

final class WireTests: XCTestCase {
    func testFrameBoundary() throws {
        let body = Data(repeating: 1, count: Wire.maxFrame)
        let frame = try Wire.frame(body)
        XCTAssertEqual(try Wire.size(of: frame.prefix(4)), body.count)
        XCTAssertEqual(frame.dropFirst(4), body)
        XCTAssertThrowsError(try Wire.frame(Data()))
        XCTAssertThrowsError(try Wire.size(of: Data([255, 255, 255, 255])))
    }

    func testIdentityAndCredential() throws {
        let identity = try TLSIdentity.ephemeral()
        XCTAssertNotNil(Wire.secret(identity.pin))
        let credential = try Wire.random(32)
        XCTAssertTrue(Wire.matches(credential, credential))
        XCTAssertFalse(Wire.matches(credential, try Wire.random(32)))
    }
}
