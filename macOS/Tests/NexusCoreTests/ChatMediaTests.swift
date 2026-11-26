import AppKit
@testable import NexusMasterSync
import XCTest

final class ChatMediaTests: XCTestCase {
    func testIsImageUsesTheSharedMimeList() {
        for mime in ["image/png", "IMAGE/JPEG", "image/heic", "image/webp", "image/gif", "image/heif"] {
            XCTAssertTrue(ChatMedia.isImage(mime: mime), mime)
        }
        for mime in ["application/pdf", "text/plain", "", "image/svg+xml"] {
            XCTAssertFalse(ChatMedia.isImage(mime: mime), mime)
        }
    }

    func testBlankNamesFallBack() {
        XCTAssertEqual(ChatMedia.senderName(outgoing: true, local: " ", peer: "S23"), "Este Mac")
        XCTAssertEqual(ChatMedia.senderName(outgoing: false, local: "Air", peer: ""), "Celular")
        XCTAssertEqual(ChatMedia.senderName(outgoing: true, local: "Air", peer: "S23"), "Air")
        XCTAssertEqual(ChatMedia.senderName(outgoing: false, local: "Air", peer: "S23"), "S23")
    }

    func testThumbnailKeepsAspectAndLimitsSize() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 100, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)

        let pixels = try XCTUnwrap(ChatMedia.thumbnailPixels(url: url, maxPixel: 64))
        XCTAssertEqual(max(pixels.width, pixels.height), 64)
        XCTAssertEqual(Double(pixels.width) / Double(pixels.height), 2.0, accuracy: 0.1)
        XCTAssertNotNil(ChatMedia.thumbnail(url: url, maxPixel: 64))
    }

    func testThumbnailOfNonImageIsNil() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("isto não é uma imagem".utf8).write(to: url)
        XCTAssertNil(ChatMedia.thumbnail(url: url, maxPixel: 64))
    }
}
