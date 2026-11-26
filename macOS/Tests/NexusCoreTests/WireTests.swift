import XCTest
@testable import NexusCore

final class WireTests: XCTestCase {
    func testFrameBoundary() throws {
        let body = Data(repeating: 1, count: Wire.maxFrame)
        let frame = try Wire.frame(body)
        XCTAssertEqual(try Wire.size(of: frame.prefix(4)), body.count)
        XCTAssertEqual(frame.dropFirst(4), body)
        XCTAssertThrowsError(try Wire.frame(Data()))
        XCTAssertThrowsError(try Wire.size(of: Data([255, 255, 255, 255])))
    }

    func testLauncherOnlyAcceptsAndroidComponentNames() {
        XCTAssertTrue(AndroidApp(component: "com.example.app/com.example.Main$Alias", label: "Example").validComponent)
        XCTAssertTrue(AndroidApp(component: "com.example.app/.MainActivity", label: "Example").validComponent)
        for invalid in ["com.example.app", "com.example/.Main; echo", "com.example/.Main'", "com.example/.Main\n"] {
            XCTAssertFalse(AndroidApp(component: invalid, label: "Example").validComponent)
        }
    }

    func testIdentityAndCredential() throws {
        let identity = try TLSIdentity.ephemeral()
        XCTAssertNotNil(Wire.secret(identity.pin))
        let credential = try Wire.random(32)
        XCTAssertTrue(Wire.matches(credential, credential))
        XCTAssertFalse(Wire.matches(credential, try Wire.random(32)))
    }

    func testLauncherIconsRoundTrip() throws {
        var message = Message("launcherIcons")
        message.launcherIcons = [AndroidAppIcon(component: "a.b/.Main", data: "iVBORw0KGgo=")]
        message.components = ["a.b/.Main"]
        let decoded = try JSONDecoder().decode(Message.self, from: JSONEncoder().encode(message))
        XCTAssertEqual(decoded.launcherIcons?.first?.component, "a.b/.Main")
        XCTAssertEqual(decoded.launcherIcons?.first?.data, "iVBORw0KGgo=")
        XCTAssertEqual(decoded.components, ["a.b/.Main"])
    }
}
