@testable import NexusMasterSync
import XCTest

final class ScrcpyStreamTests: XCTestCase {
    private func be32(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8((value >> UInt32(24 - 8 * $0)) & 0xFF) } }
    private func be64(_ value: UInt64) -> [UInt8] { (0..<8).map { UInt8((value >> UInt64(56 - 8 * $0)) & 0xFF) } }

    private func name(_ text: String) -> [UInt8] {
        var bytes = Array(text.utf8.prefix(63))
        bytes += [UInt8](repeating: 0, count: 64 - bytes.count)
        return bytes
    }

    private func session(_ width: UInt32, _ height: UInt32) -> [UInt8] { [0x80, 0, 0, 0] + be32(width) + be32(height) }

    private func packet(config: Bool = false, key: Bool = false, pts: UInt64 = 0, payload: [UInt8]) -> [UInt8] {
        let flags: UInt64 = config ? 1 << 62 : (pts | (key ? 1 << 61 : 0))
        return be64(flags) + be32(UInt32(payload.count)) + payload
    }

    private var sample: [UInt8] {
        [0x00] + name("SM_S916B") + [0x68, 0x32, 0x36, 0x34] + session(1080, 2340)
            + packet(config: true, payload: [0, 0, 0, 1, 0x67, 1, 2, 0, 0, 0, 1, 0x68, 3])
            + packet(key: true, pts: 1_000, payload: [0, 0, 0, 1, 0x65, 9, 9, 9])
            + packet(pts: 17_000, payload: [0, 0, 0, 1, 0x41, 7])
    }

    private var expected: [ScrcpyEvent] {
        [.deviceName("SM_S916B"), .session(width: 1080, height: 2340),
         .config(Data([0, 0, 0, 1, 0x67, 1, 2, 0, 0, 0, 1, 0x68, 3])),
         .frame(Data([0, 0, 0, 1, 0x65, 9, 9, 9]), keyFrame: true, ptsMicros: 1_000),
         .frame(Data([0, 0, 0, 1, 0x41, 7]), keyFrame: false, ptsMicros: 17_000)]
    }

    func testParsesTheHandshakeAndPackets() throws {
        var parser = ScrcpyStreamParser()
        XCTAssertEqual(try parser.feed(Data(sample)), expected)
    }

    func testParserIsIndependentOfHowBytesAreSplit() throws {
        for chunk in [1, 7, 13] {
            var parser = ScrcpyStreamParser()
            var events: [ScrcpyEvent] = []
            for start in stride(from: 0, to: sample.count, by: chunk) {
                events += try parser.feed(Data(sample[start..<min(start + chunk, sample.count)]))
            }
            XCTAssertEqual(events, expected, "chunk \(chunk)")
        }
    }

    func testSessionPacketResetsTheFormat() throws {
        var parser = ScrcpyStreamParser()
        _ = try parser.feed(Data(sample))
        let rotated = try parser.feed(Data(session(2340, 1080) + packet(config: true, payload: [0, 0, 0, 1, 0x67, 5])))
        XCTAssertEqual(rotated, [.session(width: 2340, height: 1080), .config(Data([0, 0, 0, 1, 0x67, 5]))])
    }

    func testParserRejectsHostileSizes() {
        var big = ScrcpyStreamParser(expectDummyByte: false)
        XCTAssertThrowsError(try big.feed(Data(name("x") + [0x68, 0x32, 0x36, 0x34] + session(10, 10)
                                               + be64(0) + be32(0x7FFF_FFFF)))) {
            XCTAssertEqual($0 as? ScrcpyStreamError, .packetTooLarge(0x7FFF_FFFF))
        }
        var codec = ScrcpyStreamParser(expectDummyByte: false)
        XCTAssertThrowsError(try codec.feed(Data(name("x") + [0x00, 0x61, 0x76, 0x31]))) {
            XCTAssertEqual($0 as? ScrcpyStreamError, .unsupportedCodec(0x0061_7631))
        }
        var empty = ScrcpyStreamParser(expectDummyByte: false)
        XCTAssertThrowsError(try empty.feed(Data(name("x") + [0x68, 0x32, 0x36, 0x34] + session(0, 0)))) {
            XCTAssertEqual($0 as? ScrcpyStreamError, .invalidSession)
        }
    }

    func testWithoutDummyByte() throws {
        var parser = ScrcpyStreamParser(expectDummyByte: false)
        let events = try parser.feed(Data(name("Pixel") + [0x68, 0x32, 0x36, 0x34] + session(720, 1280)))
        XCTAssertEqual(events, [.deviceName("Pixel"), .session(width: 720, height: 1280)])
    }
}
