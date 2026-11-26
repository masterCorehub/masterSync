@testable import NexusMasterSync
import XCTest

final class ControlRouteTests: XCTestCase {
    func testScrcpyOnlyWithWirelessAndScrcpy() {
        XCTAssertEqual(ScreenMirror.controlRoute(hasWirelessADB: true, scrcpyInstalled: true), .scrcpy)
        XCTAssertEqual(ScreenMirror.controlRoute(hasWirelessADB: true, scrcpyInstalled: false), .mirror)
        XCTAssertEqual(ScreenMirror.controlRoute(hasWirelessADB: false, scrcpyInstalled: true), .mirror)
        XCTAssertEqual(ScreenMirror.controlRoute(hasWirelessADB: false, scrcpyInstalled: false), .mirror)
    }

    func testInAppControlWinsWhenTheServerIsAvailable() {
        XCTAssertEqual(ScreenMirror.controlRoute(hasWirelessADB: true, scrcpyInstalled: true, inAppAvailable: true), .inApp)
        XCTAssertEqual(ScreenMirror.controlRoute(hasWirelessADB: true, scrcpyInstalled: false, inAppAvailable: true), .inApp)
        // Without ADB over Wi-Fi nothing here can work: the phone's own screen sharing is the way.
        XCTAssertEqual(ScreenMirror.controlRoute(hasWirelessADB: false, scrcpyInstalled: true, inAppAvailable: true), .mirror)
        // No server file: the old choices stand.
        XCTAssertEqual(ScreenMirror.controlRoute(hasWirelessADB: true, scrcpyInstalled: true, inAppAvailable: false), .scrcpy)
        XCTAssertEqual(ScreenMirror.controlRoute(hasWirelessADB: true, scrcpyInstalled: false, inAppAvailable: false), .mirror)
    }
}
