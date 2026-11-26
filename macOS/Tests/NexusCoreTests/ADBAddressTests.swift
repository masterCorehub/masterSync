@testable import NexusMasterSync
import XCTest

final class ADBAddressTests: XCTestCase {
    func testRebasedAddressMovesTheHostAndKeepsThePort() {
        XCTAssertEqual(ADBAddress.rebased("192.168.0.235:5555", onto: "192.168.3.31"), "192.168.3.31:5555")
        XCTAssertEqual(ADBAddress.rebased("10.0.0.2:33113", onto: "10.0.0.9"), "10.0.0.9:33113")
    }

    func testRebasedAddressIgnoresTheSameHost() {
        XCTAssertNil(ADBAddress.rebased("192.168.3.31:5555", onto: "192.168.3.31"))
    }

    func testRebasedAddressRejectsUnusableInput() {
        for saved in [nil, "lixo", "[::1]:5555", "1.2.3.4", "1.2.3.4:0", ""] as [String?] {
            XCTAssertNil(ADBAddress.rebased(saved, onto: "192.168.3.31"), saved ?? "nil")
        }
        for host in [nil, "fe80::1", "celular", "", "999.1.1.1"] as [String?] {
            XCTAssertNil(ADBAddress.rebased("192.168.0.235:5555", onto: host), host ?? "nil")
        }
    }

    func testPortOfAddress() {
        XCTAssertEqual(ADBAddress.port(of: "192.168.0.235:5555"), 5555)
        XCTAssertNil(ADBAddress.port(of: "sem porta"))
        XCTAssertNil(ADBAddress.port(of: nil))
    }

    func testUSBSerialsKeepsOnlyAuthorizedDevices() {
        let output = """
        List of devices attached
        RQCW308WKPA            device usb:1048576X product:dm2qxxx model:SM_S916B device:dm2q transport_id:38
        192.168.0.235:5555     offline product:dm2qxxx model:SM_S916B device:dm2q transport_id:15
        192.168.3.31:5555      device product:dm2qxxx model:SM_S916B device:dm2q transport_id:16
        ABC123                 unauthorized usb:1
        XYZ789                 offline
        PIXEL01\tdevice

        """
        XCTAssertEqual(ADBAddress.usbSerials(from: output), ["RQCW308WKPA", "PIXEL01"])
        XCTAssertEqual(ADBAddress.usbSerials(from: ""), [])
    }

    func testRecoverySteps() {
        XCTAssertEqual(ADBRecovery.next(failures: 0, usbDeviceAttached: false), .retry(status: "Procurando o celular nesta rede…"))
        XCTAssertEqual(ADBRecovery.next(failures: 1, usbDeviceAttached: true), .retry(status: "Procurando o celular nesta rede…"))
        XCTAssertEqual(ADBRecovery.next(failures: 2, usbDeviceAttached: true), .repairOverUSB(status: "Reativando o ADB do celular pelo cabo…"))
        let wait = "Não achei o ADB do celular nesta rede. Conecte o cabo uma vez: o Mac reativa sozinho."
        XCTAssertEqual(ADBRecovery.next(failures: 2, usbDeviceAttached: false), .waitForCable(status: wait))
        XCTAssertEqual(ADBRecovery.next(failures: 9, usbDeviceAttached: false), .waitForCable(status: wait))
    }

    func testTCPIPArgumentsAreValidated() {
        XCTAssertEqual(ADBClipboardSession.tcpipArguments(serial: "RQCW308WKPA", port: 5555), ["-s", "RQCW308WKPA", "tcpip", "5555"])
        XCTAssertNil(ADBClipboardSession.tcpipArguments(serial: "a b", port: 5555))
        XCTAssertNil(ADBClipboardSession.tcpipArguments(serial: "x;y", port: 5555))
        XCTAssertNil(ADBClipboardSession.tcpipArguments(serial: "", port: 5555))
        XCTAssertNil(ADBClipboardSession.tcpipArguments(serial: "ok", port: 80))
        XCTAssertNil(ADBClipboardSession.tcpipArguments(serial: "ok", port: 70000))
    }
}
