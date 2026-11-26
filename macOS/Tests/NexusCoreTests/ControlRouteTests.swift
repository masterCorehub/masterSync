@testable import NexusMasterSync
import XCTest

final class ControlRouteTests: XCTestCase {
    func testScrcpyOnlyWithWirelessAndScrcpy() {
        XCTAssertEqual(ScreenMirror.controlRoute(hasWirelessADB: true, scrcpyInstalled: true), .scrcpy)
        XCTAssertEqual(ScreenMirror.controlRoute(hasWirelessADB: true, scrcpyInstalled: false), .mirror)
        XCTAssertEqual(ScreenMirror.controlRoute(hasWirelessADB: false, scrcpyInstalled: true), .mirror)
        XCTAssertEqual(ScreenMirror.controlRoute(hasWirelessADB: false, scrcpyInstalled: false), .mirror)
    }
}
