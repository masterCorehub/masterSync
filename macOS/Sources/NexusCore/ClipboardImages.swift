import CryptoKit
import Foundation

public final class ClipboardImages {
    public static let limit = 8 * 1024 * 1024
    public static let chunkSize = 128 * 1024
    public static let formats: Set<String> = ["image/png", "image/jpeg", "image/gif", "image/webp", "image/heic", "image/heif"]

    private struct Outgoing {
        let id: String
        let bytes: Data
        let mime: String
        var next = 0
        var deadline = Date.now.addingTimeInterval(20)
    }

    private final class Incoming {
        let id: String
        let size: Int
        let mime: String
        let hash: Data
        var bytes: Data
        var deadline = Date.now.addingTimeInterval(20)

        init(id: String, size: Int, mime: String, hash: Data) {
            self.id = id
            self.size = size
            self.mime = mime
            self.hash = hash
            bytes = Data(capacity: size)
        }
    }

    private var outgoing: Outgoing?
    private var incoming: Incoming?
    public var send: ((Message) -> Void)?
    public var received: ((Data, String) -> Void)?

    public init() {}

    public func offer(_ bytes: Data, mime: String) {
        guard (1...Self.limit).contains(bytes.count), Self.formats.contains(mime) else { return }
        let state = Outgoing(id: Wire.id(), bytes: bytes, mime: mime)
        outgoing = state
        var message = message("clipboardImageOffer", id: state.id)
        message.size = Int64(bytes.count)
        message.mime = mime
        message.hash = Data(SHA256.hash(data: bytes)).base64EncodedString()
        send?(message)
    }

    public func reset() {
        outgoing = nil
        incoming = nil
    }

    public func cancelOutgoing() { outgoing = nil }
    public func cancelIncoming() { incoming = nil }

    public func expire() {
        let now = Date()
        if let outgoing, outgoing.deadline < now { self.outgoing = nil }
        if let incoming, incoming.deadline < now { self.incoming = nil }
    }

    public func receive(_ message: Message) {
        expire()
        guard let id = message.id, Wire.validID(id) else { return }
        switch message.type {
        case "clipboardImageOffer":
            guard let size = message.size, (1...Int64(Self.limit)).contains(size),
                  let mime = message.mime, Self.formats.contains(mime), let hash = Wire.secret(message.hash) else { return }
            incoming = Incoming(id: id, size: Int(size), mime: mime, hash: hash)
            acknowledge(id, 0)
        case "clipboardImageAck":
            guard var current = outgoing, current.id == id, message.offset == Int64(current.next) else { return }
            if current.next == current.bytes.count {
                outgoing = nil
                send?(self.message("clipboardImageDone", id: id))
                return
            }
            let end = min(current.next + Self.chunkSize, current.bytes.count)
            var part = self.message("clipboardImagePart", id: id)
            part.offset = Int64(current.next)
            part.data = current.bytes[current.next..<end].base64EncodedString()
            // Advance before sending. Repeated acknowledgments cannot replay a block.
            current.next = end
            current.deadline = Date.now.addingTimeInterval(20)
            outgoing = current
            send?(part)
        case "clipboardImagePart":
            guard let current = incoming, current.id == id, message.offset == Int64(current.bytes.count),
                  let encoded = message.data, encoded.utf8.count <= (Self.chunkSize + 2) / 3 * 4,
                  let bytes = Data(base64Encoded: encoded), (1...Self.chunkSize).contains(bytes.count),
                  current.bytes.count + bytes.count <= current.size else { return }
            current.bytes.append(bytes)
            current.deadline = Date.now.addingTimeInterval(20)
            acknowledge(id, current.bytes.count)
        case "clipboardImageDone":
            guard let current = incoming, current.id == id else { return }
            incoming = nil
            guard current.bytes.count == current.size, Data(SHA256.hash(data: current.bytes)) == current.hash else { return }
            received?(current.bytes, current.mime)
        default: break
        }
    }

    private func acknowledge(_ id: String, _ offset: Int) {
        var ack = message("clipboardImageAck", id: id)
        ack.offset = Int64(offset)
        send?(ack)
    }

    private func message(_ type: String, id: String) -> Message {
        var message = Message(type)
        message.id = id
        return message
    }
}
