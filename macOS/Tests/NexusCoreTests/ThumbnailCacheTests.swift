import AppKit
@testable import NexusMasterSync
import XCTest

final class ThumbnailCacheTests: XCTestCase {
    private func writePNG(to url: URL) throws {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 50, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
    }

    func testSecondLookupComesFromTheCacheEvenAfterTheFileIsGone() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try writePNG(to: url)
        let first = try XCTUnwrap(ThumbnailCache.image(url: url, maxPixel: 64))
        try FileManager.default.removeItem(at: url)

        XCTAssertTrue(ThumbnailCache.cached(url: url, maxPixel: 64) === first)
        XCTAssertTrue(ThumbnailCache.image(url: url, maxPixel: 64) === first)
    }

    func testFailuresAreNotCached() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("ainda não é imagem".utf8).write(to: url)
        XCTAssertNil(ThumbnailCache.image(url: url, maxPixel: 64))

        try writePNG(to: url)
        XCTAssertNotNil(ThumbnailCache.image(url: url, maxPixel: 64))
    }

    func testDifferentSizesAreCachedSeparately() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try writePNG(to: url)
        let small = try XCTUnwrap(ThumbnailCache.image(url: url, maxPixel: 32))
        let large = try XCTUnwrap(ThumbnailCache.image(url: url, maxPixel: 64))
        XCTAssertFalse(small === large)
    }
}
