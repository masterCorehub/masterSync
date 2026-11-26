@testable import NexusMasterSync
import XCTest

final class ClipboardAutoStartTests: XCTestCase {
    func testAutoStartsOnlyWhenEverythingHolds() {
        let device = ADBWirelessDevice(address: "192.168.0.235:5555", service: nil, deviceID: "RQ", peerID: "phone")
        func check(_ enabled: Bool = true, _ device: ADBWirelessDevice? = device, _ peer: String? = "phone",
                   _ running: Bool = false, _ paused: Bool = false) -> Bool {
            ADBClipboard.shouldAutoStart(clipboardEnabled: enabled, device: device, connectedPeer: peer,
                                         running: running, paused: paused)
        }
        XCTAssertTrue(check())
        XCTAssertFalse(check(false))
        XCTAssertFalse(check(true, nil))
        XCTAssertFalse(check(true, device, nil))
        XCTAssertFalse(check(true, device, "outro"))
        XCTAssertFalse(check(true, device, "phone", true))
        XCTAssertFalse(check(true, device, "phone", false, true))
    }
}
