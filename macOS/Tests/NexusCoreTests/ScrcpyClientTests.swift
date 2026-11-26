import Darwin
import Foundation
import NexusCore
@testable import NexusMasterSync
import XCTest

final class ScrcpyClientTests: XCTestCase {
    /// A pretend scrcpy install: `bin/scrcpy` printing a version and a server file next to it.
    private func fakeInstall(version: String = "scrcpy 5.0.1 <https://example>") throws -> (root: URL, scrcpy: String) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("share/scrcpy"), withIntermediateDirectories: true)
        let script = root.appendingPathComponent("bin/scrcpy")
        try "#!/bin/sh\necho '\(version)'\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        try Data("jar".utf8).write(to: root.appendingPathComponent("share/scrcpy/scrcpy-server"))
        return (root, script.path)
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func bump() { lock.lock(); value += 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    }

    func testAFailedStartThrowsWithAReasonAndReportsNoEnd() throws {
        let (root, scrcpy) = try fakeInstall()
        defer { try? FileManager.default.removeItem(at: root) }
        let client = ScrcpyClient(adb: "/usr/bin/false", scrcpyExecutable: scrcpy)
        let ended = Counter()
        client.onEnded = { _ in ended.bump() }
        XCTAssertThrowsError(try client.start(serial: "ABC")) { error in
            XCTAssertTrue(error.localizedDescription.contains("servidor"), error.localizedDescription)
        }
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(ended.count, 0, "uma falha ao iniciar não é um encerramento")
    }

    func testAnUnsupportedScrcpyVersionIsRefusedBeforeTouchingThePhone() throws {
        let (root, scrcpy) = try fakeInstall(version: "scrcpy 3.3.1 <https://example>")
        defer { try? FileManager.default.removeItem(at: root) }
        let client = ScrcpyClient(adb: "/usr/bin/false", scrcpyExecutable: scrcpy)
        XCTAssertThrowsError(try client.start(serial: "ABC")) { error in
            XCTAssertTrue(error.localizedDescription.contains("3.3.1"), error.localizedDescription)
        }
    }

    func testAMissingServerFileIsReported() throws {
        let (root, scrcpy) = try fakeInstall()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: root.appendingPathComponent("share/scrcpy/scrcpy-server"))
        let client = ScrcpyClient(adb: "/usr/bin/false", scrcpyExecutable: scrcpy)
        XCTAssertThrowsError(try client.start(serial: "ABC")) { error in
            XCTAssertTrue(error.localizedDescription.contains("não foi encontrado"), error.localizedDescription)
        }
    }

    // MARK: SocketHandle

    private func pair() -> (Int32, Int32) {
        var fds: [Int32] = [0, 0]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds), 0)
        return (fds[0], fds[1])
    }

    func testAClosedHandleRefusesNewUsers() {
        let (a, b) = pair()
        defer { close(b) }
        let handle = SocketHandle(a)
        XCTAssertEqual(handle.use { _ in 7 }, 7)
        handle.shutdownAndRelease()
        XCTAssertNil(handle.use { _ in 7 })
    }

    func testTheSocketIsClosedOnlyAfterTheLastUserFinishes() {
        let (a, b) = pair()
        defer { close(b) }
        let handle = SocketHandle(a)
        let reading = DispatchSemaphore(value: 0), finished = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            _ = handle.use { fd in
                var byte: UInt8 = 0
                reading.signal()
                _ = read(fd, &byte, 1)          // blocks until shutdown
            }
            finished.signal()
        }
        reading.wait()
        handle.shutdownAndRelease()
        XCTAssertEqual(finished.wait(timeout: .now() + 3), .success, "shutdown must wake the reader")
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertEqual(fcntl(a, F_GETFD), -1, "o descritor deveria ter sido fechado")
        XCTAssertEqual(errno, EBADF)
    }

    func testShutdownAndReleaseCanBeCalledTwice() {
        let (a, b) = pair()
        defer { close(b) }
        let handle = SocketHandle(a)
        handle.shutdownAndRelease()
        handle.shutdownAndRelease()
        XCTAssertEqual(fcntl(a, F_GETFD), -1)
    }
}
