import Foundation
@testable import NexusMasterSync
import XCTest

/// Runs the whole chain against a real phone. Off unless NEXUS_SCRCPY_SERIAL names an authorized device,
/// for example NEXUS_SCRCPY_SERIAL=192.168.3.31:5555.
final class ScrcpyDeviceTests: XCTestCase {
    private let adb = "/opt/homebrew/bin/adb"
    private let scrcpy = "/opt/homebrew/bin/scrcpy"

    private func serialOrSkip() throws -> String {
        guard let serial = ProcessInfo.processInfo.environment["NEXUS_SCRCPY_SERIAL"] else {
            throw XCTSkip("Defina NEXUS_SCRCPY_SERIAL para testar com um celular.")
        }
        return serial
    }

    private func adbOutput(_ arguments: [String]) -> String {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: adb)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [ScrcpyEvent] = []
        func add(_ event: ScrcpyEvent) { lock.lock(); items.append(event); lock.unlock() }
        var events: [ScrcpyEvent] { lock.lock(); defer { lock.unlock() }; return items }
    }

    private func waitForFrame(_ collector: Collector, timeout: TimeInterval = 12) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if collector.events.contains(where: { if case .frame(_, true, _) = $0 { true } else { false } }) { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    private func screenshot(_ serial: String, _ name: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "\(adb) -s \(serial) exec-out screencap -p > /private/tmp/claude-501/\(name).png"]
        try? process.run()
        process.waitUntilExit()
    }

    func testStartAndStopLeaveNothingBehind() throws {
        let serial = try serialOrSkip()
        let client = ScrcpyClient(adb: adb, scrcpyExecutable: scrcpy)
        let collector = Collector()
        client.onEvent = { collector.add($0) }
        try client.start(serial: serial)
        XCTAssertTrue(waitForFrame(collector), "nenhum quadro-chave chegou")

        let session = collector.events.compactMap { event -> (Int, Int)? in
            if case let .session(width, height) = event { (width, height) } else { nil }
        }.first
        XCTAssertGreaterThan(session?.0 ?? 0, 100)
        XCTAssertGreaterThan(session?.1 ?? 0, 100)
        XCTAssertTrue(collector.events.contains { if case .config = $0 { true } else { false } })

        client.send(ScrcpyControl.collapsePanels)
        client.stop(wait: true)

        XCTAssertFalse(adbOutput(["forward", "--list"]).contains("scrcpy_"), "o túnel ficou aberto")
        XCTAssertFalse(adbOutput(["-s", serial, "shell", "ps -A | grep -c com.genymobile.scrcpy.Server"]).contains("1"),
                       "o servidor ficou rodando no celular")
    }

    func testTouchAndPanelMessagesReachThePhone() throws {
        let serial = try serialOrSkip()
        let client = ScrcpyClient(adb: adb, scrcpyExecutable: scrcpy)
        let collector = Collector()
        client.onEvent = { collector.add($0) }
        try client.start(serial: serial)
        defer { client.stop(wait: true) }
        XCTAssertTrue(waitForFrame(collector))
        guard case let .session(width, height)? = collector.events.first(where: { if case .session = $0 { true } else { false } }) else {
            return XCTFail("sem pacote de sessão")
        }

        // On the home screen a swipe up in the middle opens the app drawer: it proves the touch bytes are right.
        client.send(ScrcpyControl.keycode(action: ScrcpyControl.Action.down, keycode: ScrcpyControl.Key.home))
        client.send(ScrcpyControl.keycode(action: ScrcpyControl.Action.up, keycode: ScrcpyControl.Key.home))
        Thread.sleep(forTimeInterval: 1.2)
        screenshot(serial, "scrcpy-before")
        let w = UInt16(width), h = UInt16(height)
        let startY = Int32(height * 3 / 4), endY = Int32(height / 4)
        client.send(ScrcpyControl.touch(action: ScrcpyControl.Action.down, x: Int32(width / 2), y: startY, width: w, height: h, pressed: true))
        for step in 1...12 {
            Thread.sleep(forTimeInterval: 0.02)
            client.send(ScrcpyControl.touch(action: ScrcpyControl.Action.move, x: Int32(width / 2),
                                            y: startY + (endY - startY) * Int32(step) / 12, width: w, height: h, pressed: true))
        }
        client.send(ScrcpyControl.touch(action: ScrcpyControl.Action.up, x: Int32(width / 2), y: endY, width: w, height: h, pressed: false))
        Thread.sleep(forTimeInterval: 1.2)
        screenshot(serial, "scrcpy-after-swipe")

        client.send(ScrcpyControl.keycode(action: ScrcpyControl.Action.down, keycode: ScrcpyControl.Key.home))
        client.send(ScrcpyControl.keycode(action: ScrcpyControl.Action.up, keycode: ScrcpyControl.Key.home))
        Thread.sleep(forTimeInterval: 0.8)
        screenshot(serial, "scrcpy-after-collapse")
    }

    /// Messages with a plain, visible effect: if these work the control channel is right and only a touch detail is off.
    func testSimpleControlMessagesHavePhoneEffects() throws {
        let serial = try serialOrSkip()
        let client = ScrcpyClient(adb: adb, scrcpyExecutable: scrcpy)
        let collector = Collector()
        client.onEvent = { collector.add($0) }
        try client.start(serial: serial)
        defer { client.stop(wait: true) }
        XCTAssertTrue(waitForFrame(collector))

        client.send(ScrcpyControl.expandNotifications)
        Thread.sleep(forTimeInterval: 1.2)
        screenshot(serial, "scrcpy-expanded")
        client.send(ScrcpyControl.collapsePanels)
        Thread.sleep(forTimeInterval: 0.8)

        client.send(ScrcpyControl.keycode(action: ScrcpyControl.Action.down, keycode: ScrcpyControl.Key.home))
        client.send(ScrcpyControl.keycode(action: ScrcpyControl.Action.up, keycode: ScrcpyControl.Key.home))
        Thread.sleep(forTimeInterval: 1.2)
        screenshot(serial, "scrcpy-home")
    }
}
