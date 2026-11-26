import AppKit
import NexusCore
@testable import NexusMasterSync
import XCTest

final class LauncherIconCacheTests: XCTestCase {
    func testMissingIconsSkipsCachedInvalidAndCaps() {
        var pins = (0..<27).map { "app.n\($0)/.Main" }
        pins.append("sem componente")
        pins.append("app.n0/.Main")
        let cached: Set<String> = ["app.n1/.Main", "app.n2/.Main"]
        let missing = NexusModel.missingIcons(pins: pins, cached: cached)
        XCTAssertEqual(missing.count, 24)
        XCTAssertEqual(missing.first, "app.n0/.Main")
        XCTAssertFalse(missing.contains("app.n1/.Main"))
        XCTAssertFalse(missing.contains("sem componente"))
        XCTAssertEqual(Set(missing).count, missing.count)
    }

    func testLauncherIconsRejectInvalidData() throws {
        XCTAssertNil(NexusModel.acceptedIcon("não-base64"))
        XCTAssertNil(NexusModel.acceptedIcon(Data((0..<64).map { UInt8($0) }).base64EncodedString()))
        XCTAssertNil(NexusModel.acceptedIcon(Data(repeating: 0, count: 70 * 1024).base64EncodedString()))

        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 1, height: 1).fill(); image.unlockFocus()
        let png = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))?
            .representation(using: .png, properties: [:]))
        XCTAssertNotNil(NexusModel.acceptedIcon(png.base64EncodedString()))
    }
}
