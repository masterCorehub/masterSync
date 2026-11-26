import NexusCore
@testable import NexusMasterSync
import XCTest

final class ScanCameraCommandTests: XCTestCase {
    func testScanCameraArgumentsQuoteComponentAndId() throws {
        let id = Wire.id()
        let arguments = try XCTUnwrap(ADBClipboardSession.scanCameraArguments(serial: "s", package: "com.nexus.mastersync", id: id))
        XCTAssertEqual(arguments.prefix(2), ["-s", "s"])
        XCTAssertTrue(arguments.contains("'com.nexus.mastersync/com.nexus.mastersync.MainActivity'"))
        let extra = try XCTUnwrap(arguments.firstIndex(of: "--es"))
        XCTAssertEqual(Array(arguments[extra...extra + 2]), ["--es", "accept-scan", "'\(id)'"])
    }

    func testScanCameraRejectsInvalidIdAndPackage() {
        XCTAssertNil(ADBClipboardSession.scanCameraArguments(serial: "s", package: "com.nexus.mastersync", id: "a b"))
        XCTAssertNil(ADBClipboardSession.scanCameraArguments(serial: "s", package: "evil;rm", id: Wire.id()))
    }
}
