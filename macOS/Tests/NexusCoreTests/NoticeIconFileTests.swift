import AppKit
@testable import NexusMasterSync
import XCTest

final class NoticeIconFileTests: XCTestCase {
    private func image() -> NSImage {
        let image = NSImage(size: NSSize(width: 48, height: 48))
        image.lockFocus(); NSColor.systemGreen.setFill(); NSRect(x: 0, y: 0, width: 48, height: 48).fill(); image.unlockFocus()
        return image
    }

    func testWritesAReadablePNGForAnAppGroup() throws {
        let url = try XCTUnwrap(NoticeIconFile.url(for: image(), group: "com.whatsapp"))
        XCTAssertEqual(url.pathExtension, "png")
        let data = try Data(contentsOf: url)
        XCTAssertNotNil(NSImage(data: data))
    }

    func testSameGroupReusesTheSameFileAndDifferentGroupsDiffer() throws {
        let a = try XCTUnwrap(NoticeIconFile.url(for: image(), group: "com.whatsapp"))
        let b = try XCTUnwrap(NoticeIconFile.url(for: image(), group: "com.whatsapp"))
        let c = try XCTUnwrap(NoticeIconFile.url(for: image(), group: "com.spotify.music"))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testGroupNamesWithPathCharactersStayInsideTheFolder() throws {
        let url = try XCTUnwrap(NoticeIconFile.url(for: image(), group: "../../etc/passwd"))
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "NexusNoticeIcons")
    }
}
