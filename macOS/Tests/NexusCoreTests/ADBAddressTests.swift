@testable import NexusMasterSync
import XCTest

final class ADBAddressTests: XCTestCase {
    func testRebasedAddressMovesTheHostAndKeepsThePort() {
        XCTAssertEqual(ADBAddress.rebased("192.168.0.235:5555", onto: "192.168.3.31"), "192.168.3.31:5555")
        XCTAssertEqual(ADBAddress.rebased("10.0.0.2:33113", onto: "10.0.0.9"), "10.0.0.9:33113")
    }

    func testRebasedAddressRejectsHostsThatAreNeverTheTarget() {
        XCTAssertNil(ADBAddress.rebased("192.168.0.235:5555", onto: "127.0.0.1"))
        XCTAssertNil(ADBAddress.rebased("192.168.0.235:5555", onto: "169.254.10.2"))
        XCTAssertNil(ADBAddress.rebased("192.168.0.235:5555", onto: "0.0.0.0"))
    }

    func testCandidateAlternatesBetweenTheFreshAndTheSavedAddress() {
        let saved = "192.168.0.235:5555"
        XCTAssertEqual(ADBAddress.candidate(saved: saved, host: "192.168.3.31", attempt: 0), "192.168.3.31:5555")
        XCTAssertEqual(ADBAddress.candidate(saved: saved, host: "192.168.3.31", attempt: 1), saved)
        XCTAssertEqual(ADBAddress.candidate(saved: saved, host: "192.168.3.31", attempt: 2), "192.168.3.31:5555")
        // Nothing new to try: always the saved one.
        XCTAssertEqual(ADBAddress.candidate(saved: saved, host: nil, attempt: 0), saved)
        XCTAssertEqual(ADBAddress.candidate(saved: saved, host: "192.168.0.235", attempt: 3), saved)
        XCTAssertNil(ADBAddress.candidate(saved: nil, host: "192.168.3.31", attempt: 0))
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

    private func step(_ failures: Int, usb: String? = nil, hostKnown: Bool = true, address: String? = "192.168.3.31:5555",
                      repairedFor: String? = nil) -> ADBRecovery.Step {
        ADBRecovery.next(failures: failures, usbSerial: usb, hostKnown: hostKnown, address: address, repairedFor: repairedFor)
    }

    func testRecoveryStepsWithoutACable() {
        XCTAssertEqual(step(0), .retry(status: "Procurando o celular nesta rede…"))
        XCTAssertEqual(step(1), .retry(status: "Procurando o celular nesta rede…"))
        let wait = "Não achei o ADB do celular nesta rede. Conecte o cabo uma vez: o Mac reativa sozinho."
        XCTAssertEqual(step(2), .waitForCable(status: wait))
        XCTAssertEqual(step(9), .waitForCable(status: wait))
    }

    func testRepairHappensOncePerCableAndAddress() {
        let key = ADBRecovery.repairKey(serial: "RQ", address: "192.168.3.31:5555")
        XCTAssertEqual(step(2, usb: "RQ"), .repairOverUSB(status: "Reativando o ADB do celular pelo cabo…", key: key))
        XCTAssertEqual(step(1, usb: "RQ"), .retry(status: "Procurando o celular nesta rede…"))
        // Already repaired for this cable and address: do not restart the phone's ADB again.
        let tried = "O celular está no cabo, mas não respondeu pelo Wi-Fi. Confira se o celular e o Mac estão na mesma rede."
        XCTAssertEqual(step(5, usb: "RQ", repairedFor: key), .retry(status: tried))
        // A new address is a new situation.
        XCTAssertEqual(step(5, usb: "RQ", address: "10.0.0.9:5555", repairedFor: key),
                       .repairOverUSB(status: "Reativando o ADB do celular pelo cabo…",
                                      key: ADBRecovery.repairKey(serial: "RQ", address: "10.0.0.9:5555")))
    }

    func testNoRepairWhileThePhoneIsNotOnThisNetwork() {
        XCTAssertEqual(step(4, usb: "RQ", hostKnown: false),
                       .retry(status: "Abra o MasterSync no celular, conectado à mesma rede do Mac."))
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
