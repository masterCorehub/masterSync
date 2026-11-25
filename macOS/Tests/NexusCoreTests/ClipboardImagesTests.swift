import Foundation
import XCTest
@testable import NexusCore

final class ClipboardImagesTests: XCTestCase {
    func testClipboardImageUsesMultipleBlocksAndValidatesHash() throws {
        let source = Data((0..<(ClipboardImages.chunkSize * 2 + 83)).map { UInt8($0 % 251) })
        let sender = ClipboardImages()
        let receiver = ClipboardImages()
        var blocks = 0
        var corrupt = false
        var captured: Data?
        sender.send = { [weak receiver] packet in
            var packet = packet
            if packet.type == "clipboardImagePart" {
                if (try? Wire.frame(JSONEncoder().encode(packet))) == nil {
                    XCTFail("O bloco da imagem excede o limite do enquadramento.")
                }
                blocks += 1
                if corrupt && packet.offset == 0, let encoded = packet.data, var bytes = Data(base64Encoded: encoded) {
                    bytes[0] = 42
                    packet.data = bytes.base64EncodedString()
                }
            }
            receiver?.receive(packet)
        }
        receiver.send = { [weak sender] in sender?.receive($0) }
        receiver.received = { bytes, mime in captured = bytes; XCTAssertEqual(mime, "image/png") }

        sender.offer(source, mime: "image/png")
        XCTAssertEqual(blocks, 3)
        XCTAssertEqual(captured, source)
        captured = nil
        corrupt = true
        sender.offer(source, mime: "image/png")
        XCTAssertNil(captured)
    }
}
