import AppKit
import ImageIO
import XCTest
@testable import NexusMasterSync

final class USBClipboardTests: XCTestCase {
    func testWirelessEndpointAndPairingValidation() {
        XCTAssertEqual(ADBEndpoint(" 192.168.1.20:43123 ")?.address, "192.168.1.20:43123")
        XCTAssertEqual(ADBEndpoint("[fe80::1]:43123")?.address, "[fe80::1]:43123")
        XCTAssertNil(ADBEndpoint("192.168.1.20:0"))
        XCTAssertNil(ADBEndpoint("host.local:43123"))
        XCTAssertNil(ADBPairing(address: "192.168.1.20:43123", code: "12a456"))
        XCTAssertEqual(ADBPairing(address: "192.168.1.20:43123", code: "012345")?.code, "012345")
    }

    @MainActor
    func testUSBClipboardWithStandardKeyboardAndAndroidAppClosed() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let adb = env["NEXUS_TEST_ANDROID_ADB"],
              let serial = env["NEXUS_TEST_ANDROID_SERIAL"], serial.hasPrefix("emulator-"),
              let helper = env["NEXUS_TEST_USB_CLIPBOARD_HELPER"] else {
            throw XCTSkip("Defina NEXUS_TEST_USB_CLIPBOARD_HELPER e selecione um emulador.")
        }

        let session = ADBClipboardSession(adb: adb)
        try await exercise(session: session, adb: adb, serial: serial, helper: helper)
    }

    @MainActor
    func testWirelessPairingAndClipboardWithAndroidAppClosed() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let adb = env["NEXUS_TEST_ANDROID_ADB"],
              let helper = env["NEXUS_TEST_USB_CLIPBOARD_HELPER"],
              let address = env["NEXUS_TEST_WIFI_ADDRESS"], address.hasPrefix("127.0.0.1:"),
              let pairingAddress = env["NEXUS_TEST_WIFI_PAIR_ADDRESS"], pairingAddress.hasPrefix("127.0.0.1:"),
              let code = env["NEXUS_TEST_WIFI_CODE"],
              let pairing = ADBPairing(address: pairingAddress, code: code) else {
            throw XCTSkip("Encaminhe as duas portas da Depuração sem fio do emulador para localhost.")
        }

        let session = ADBClipboardSession(adb: adb)
        defer { session.cancel() }
        let service = try XCTUnwrap(session.pair(pairing))
        let device = ADBWirelessDevice(address: address, service: service, deviceID: nil)
        let serial = try await session.wirelessSerial(for: device)
        XCTAssertEqual(serial, address)
        XCTAssertNotNil(try session.hardwareID(serial: serial))
        try await exercise(session: session, adb: adb, serial: serial, helper: helper)
    }

    @MainActor
    private func exercise(session: ADBClipboardSession, adb: String, serial: String, helper: String) async throws {

        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let clipboard = ClipboardSync(file: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                                      board: board)
        let ready = expectation(description: "leitor ADB iniciado")
        let copiedText = expectation(description: "texto na área de transferência do Mac")
        let copiedImage = expectation(description: "imagem na área de transferência do Mac")
        let fixtureFinished = expectation(description: "Android emitiu as cópias de teste")
        let listener = Task.detached {
            try await session.listen(serial: serial, helper: URL(fileURLWithPath: helper), onReady: {
                ready.fulfill()
            }, onEvent: { event in
                await MainActor.run {
                    clipboard.receive(event)
                    switch event {
                    case .text(let text):
                        XCTAssertEqual(text, "Cópia USB de teste")
                        XCTAssertEqual(board.string(forType: .string), text)
                        copiedText.fulfill()
                    case .image(let bytes, let mime):
                        XCTAssertEqual(mime, "image/png")
                        XCTAssertEqual(board.data(forType: .png), bytes)
                        XCTAssertNotNil(CGImageSourceCreateWithData(bytes as CFData, nil))
                        copiedImage.fulfill()
                    }
                }
            })
        }
        defer { session.cancel(); listener.cancel() }
        await fulfillment(of: [ready], timeout: 12)

        let fixture = Process()
        let output = Pipe()
        fixture.executableURL = URL(fileURLWithPath: adb)
        fixture.arguments = ["-s", serial, "shell", "am", "instrument", "-w", "-e", "class",
                             "com.nexus.mastersync.ADBClipboardSourceTest", "-e", "nexusUsbClipboard", "1",
                             "com.nexus.mastersync.test/androidx.test.runner.AndroidJUnitRunner"]
        fixture.standardOutput = output
        fixture.standardError = output
        fixture.terminationHandler = { _ in fixtureFinished.fulfill() }
        try fixture.run()
        defer { if fixture.isRunning { fixture.terminate() } }
        await fulfillment(of: [copiedText, copiedImage, fixtureFinished], timeout: 20, enforceOrder: true)
        if !fixture.isRunning {
            let log = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTAssertTrue(log.contains("OK (1 test)") && fixture.terminationStatus == 0, log)
        }
        session.cancel()
        try await listener.value
    }
}
