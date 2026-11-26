import AppKit
import NexusCore
@testable import NexusMasterSync
import XCTest

final class MediaCommandsTests: XCTestCase {
    func testCommandCarriesItsArguments() {
        let seek = MediaCommands.command("seek", positionMs: 5_000)
        XCTAssertEqual(seek.type, "mediaCommand")
        XCTAssertEqual(seek.message, "seek")
        XCTAssertEqual(seek.positionMs, 5_000)
        XCTAssertNil(seek.queueId)

        let item = MediaCommands.command("queueItem", queueId: 7)
        XCTAssertEqual(item.queueId, 7)
        XCTAssertNil(item.positionMs)
        XCTAssertEqual(MediaCommands.command("play").message, "play")
    }

    func testRequestsArtOnlyWhenMissing() {
        XCTAssertTrue(MediaCommands.shouldRequestArt(key: "new", cached: ["old"], pending: []))
        XCTAssertFalse(MediaCommands.shouldRequestArt(key: "old", cached: ["old"], pending: []))
        XCTAssertFalse(MediaCommands.shouldRequestArt(key: "new", cached: [], pending: ["new"]))
        XCTAssertFalse(MediaCommands.shouldRequestArt(key: nil, cached: [], pending: []))
        XCTAssertFalse(MediaCommands.shouldRequestArt(key: "", cached: [], pending: []))
    }

    func testArtRetriesAreBounded() {
        XCTAssertTrue(MediaCommands.shouldRequestArt(key: "k", cached: [], pending: [], attempts: 3))
        XCTAssertFalse(MediaCommands.shouldRequestArt(key: "k", cached: [], pending: [], attempts: 4))
    }

    func testQueueItemsOnlyGoToThePhoneTheyCameFrom() {
        XCTAssertTrue(MediaCommands.queueBelongs(queuePeer: "a", selected: "a"))
        XCTAssertFalse(MediaCommands.queueBelongs(queuePeer: "a", selected: "b"))
        XCTAssertFalse(MediaCommands.queueBelongs(queuePeer: nil, selected: "b"))
        XCTAssertFalse(MediaCommands.queueBelongs(queuePeer: "a", selected: nil))
    }

    private func pngBase64() throws -> String {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        return try XCTUnwrap(rep.representation(using: .png, properties: [:])).base64EncodedString()
    }

    func testStaleArtIsIgnored() throws {
        let data = try pngBase64()
        XCTAssertNil(MediaCommands.acceptsArt(key: "old", currentKey: "new", data: data))
        XCTAssertNil(MediaCommands.acceptsArt(key: nil, currentKey: "new", data: data))
        XCTAssertNotNil(MediaCommands.acceptsArt(key: "new", currentKey: "new", data: data))
    }

    func testInvalidArtIsRejected() {
        XCTAssertNil(MediaCommands.acceptsArt(key: "k", currentKey: "k", data: "não-base64"))
        XCTAssertNil(MediaCommands.acceptsArt(key: "k", currentKey: "k", data: Data((0..<64).map { UInt8($0) }).base64EncodedString()))
        XCTAssertNil(MediaCommands.acceptsArt(key: "k", currentKey: "k", data: Data(repeating: 0, count: 70 * 1024).base64EncodedString()))
    }

    func testQueueDecodes() throws {
        var message = Message("mediaQueue")
        message.queue = [MediaQueueItem(id: 3, title: "Primeira"), MediaQueueItem(id: 4, title: "Segunda")]
        message.queueId = 4
        let decoded = try JSONDecoder().decode(Message.self, from: JSONEncoder().encode(message))
        XCTAssertEqual(decoded.queue, message.queue)
        XCTAssertEqual(decoded.queueId, 4)
    }
}
