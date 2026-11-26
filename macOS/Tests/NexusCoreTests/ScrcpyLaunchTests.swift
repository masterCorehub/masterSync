@testable import NexusMasterSync
import XCTest

final class ScrcpyLaunchTests: XCTestCase {
    func testSocketNameIsEightLowercaseHexDigits() {
        XCTAssertEqual(ScrcpyLaunch.socketName(scid: 0xABCDEF), "scrcpy_00abcdef")
        XCTAssertEqual(ScrcpyLaunch.socketName(scid: 0x7FFFFFFF), "scrcpy_7fffffff")
    }

    func testServerArgumentsMatchTheProtocol() throws {
        let arguments = try XCTUnwrap(ScrcpyLaunch.serverArguments(version: "5.0.1", scid: 0x1234ABCD, maxSize: 1600, maxFPS: 60, bitRate: 8_000_000))
        XCTAssertEqual(arguments, [
            "CLASSPATH=/data/local/tmp/scrcpy-server-1234abcd.jar", "app_process", "/", "com.genymobile.scrcpy.Server", "5.0.1",
            "scid=1234abcd", "log_level=info", "tunnel_forward=true", "audio=false", "control=true", "video_codec=h264",
            "max_size=1600", "max_fps=60", "video_bit_rate=8000000", "clipboard_autosync=false", "cleanup=true"])
        XCTAssertNil(ScrcpyLaunch.serverArguments(version: "5.0.1; rm -rf /", scid: 1, maxSize: 1, maxFPS: 1, bitRate: 1))
        XCTAssertNil(ScrcpyLaunch.serverArguments(version: "", scid: 1, maxSize: 1, maxFPS: 1, bitRate: 1))
        XCTAssertNil(ScrcpyLaunch.serverArguments(version: "5..", scid: 1, maxSize: 1, maxFPS: 1, bitRate: 1))
    }

    func testEachSessionHasItsOwnJarPath() {
        XCTAssertEqual(ScrcpyLaunch.jarPath(scid: 0xABC), "/data/local/tmp/scrcpy-server-00000abc.jar")
        XCTAssertNotEqual(ScrcpyLaunch.jarPath(scid: 1), ScrcpyLaunch.jarPath(scid: 2))
    }

    func testOnlyTheProtocolWeKnowIsSupported() {
        XCTAssertTrue(ScrcpyLaunch.isSupported(version: "5.0.1"))
        XCTAssertTrue(ScrcpyLaunch.isSupported(version: "5.0"))
        XCTAssertTrue(ScrcpyLaunch.isSupported(version: "5.0.12"))
        for version in ["4.0", "3.3.1", "5.1.0", "6.0.0", "5", "", "5.0.1; rm", "50.0.1", "5.00.1"] {
            XCTAssertFalse(ScrcpyLaunch.isSupported(version: version), version)
        }
    }

    func testServerURLFollowsTheInstallLayout() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try Data("#!/bin/sh".utf8).write(to: root.appendingPathComponent("bin/scrcpy"))
        XCTAssertNil(ScrcpyLaunch.serverURL(forScrcpy: root.appendingPathComponent("bin/scrcpy").path))

        try FileManager.default.createDirectory(at: root.appendingPathComponent("share/scrcpy"), withIntermediateDirectories: true)
        try Data("jar".utf8).write(to: root.appendingPathComponent("share/scrcpy/scrcpy-server"))
        let found = try XCTUnwrap(ScrcpyLaunch.serverURL(forScrcpy: root.appendingPathComponent("bin/scrcpy").path))
        XCTAssertEqual(found.resolvingSymlinksInPath().path, root.appendingPathComponent("share/scrcpy/scrcpy-server").resolvingSymlinksInPath().path)
    }

    func testDevicePointInsideAndOnTheEdges() throws {
        let view = CGSize(width: 400, height: 400), video = CGSize(width: 1080, height: 2340)
        let scale = 400.0 / 2340.0
        let left = (400 - 1080 * scale) / 2
        let center = try XCTUnwrap(ScrcpyLaunch.devicePoint(viewPoint: CGPoint(x: 200, y: 200), viewSize: view, videoSize: video))
        XCTAssertEqual(Int(center.x), 540, accuracy: 1)
        XCTAssertEqual(Int(center.y), 1170, accuracy: 1)
        let topLeft = try XCTUnwrap(ScrcpyLaunch.devicePoint(viewPoint: CGPoint(x: left, y: 0), viewSize: view, videoSize: video))
        XCTAssertEqual(topLeft.x, 0); XCTAssertEqual(topLeft.y, 0)
        let bottomRight = try XCTUnwrap(ScrcpyLaunch.devicePoint(viewPoint: CGPoint(x: 400 - left, y: 400), viewSize: view, videoSize: video))
        XCTAssertEqual(bottomRight.x, 1079); XCTAssertEqual(bottomRight.y, 2339)
    }

    func testClicksOutsideTheVideoAreIgnored() {
        let view = CGSize(width: 400, height: 400), video = CGSize(width: 1080, height: 2340)
        XCTAssertNil(ScrcpyLaunch.devicePoint(viewPoint: CGPoint(x: 50, y: 200), viewSize: view, videoSize: video))
        XCTAssertNil(ScrcpyLaunch.devicePoint(viewPoint: CGPoint(x: 350, y: 200), viewSize: view, videoSize: video))
        XCTAssertNil(ScrcpyLaunch.devicePoint(viewPoint: CGPoint(x: 200, y: -5), viewSize: view, videoSize: video))
        XCTAssertNil(ScrcpyLaunch.devicePoint(viewPoint: CGPoint(x: 200, y: 200), viewSize: .zero, videoSize: video))
        XCTAssertNil(ScrcpyLaunch.devicePoint(viewPoint: CGPoint(x: 200, y: 200), viewSize: view, videoSize: .zero))
    }
}
