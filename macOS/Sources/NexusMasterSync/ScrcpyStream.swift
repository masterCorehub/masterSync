import Foundation

enum ScrcpyEvent: Equatable {
    case deviceName(String)
    case session(width: Int, height: Int)
    /// SPS and PPS in Annex B form.
    case config(Data)
    case frame(Data, keyFrame: Bool, ptsMicros: UInt64)
}

enum ScrcpyStreamError: Error, Equatable {
    case unsupportedCodec(UInt32)
    case packetTooLarge(Int)
    case invalidSession
}

/// Reads the video socket of a scrcpy 5.0.1 server (forward tunnel): the dummy byte, the 64-byte device name, the codec id,
/// then 12-byte headers followed by their payloads. Bytes may arrive cut anywhere.
struct ScrcpyStreamParser {
    static let h264: UInt32 = 0x6832_3634
    static let maxPacket = 16 * 1024 * 1024
    private static let maxDimension = 16_384

    private enum State {
        case dummy, name, codec, header
        case payload(config: Bool, key: Bool, pts: UInt64, size: Int)
    }

    private var buffer: [UInt8] = []
    private var head = 0
    private var state: State

    init(expectDummyByte: Bool = true) { state = expectDummyByte ? .dummy : .name }

    private var available: Int { buffer.count - head }

    /// The next [count] bytes, copied out first so that compacting the buffer never has to copy it all again.
    private mutating func take(_ count: Int) -> [UInt8] {
        let bytes = Array(buffer[head..<head + count])
        head += count
        // Drop what was consumed once it is a meaningful part of the buffer.
        if head == buffer.count { buffer.removeAll(keepingCapacity: true); head = 0 }
        else if head > 1 << 20 { buffer.removeFirst(head); head = 0 }
        return bytes
    }

    private static func be32(_ bytes: some Sequence<UInt8>) -> UInt32 { bytes.reduce(0) { $0 << 8 | UInt32($1) } }
    private static func be64(_ bytes: some Sequence<UInt8>) -> UInt64 { bytes.reduce(0) { $0 << 8 | UInt64($1) } }

    mutating func feed(_ data: Data) throws -> [ScrcpyEvent] {
        buffer.append(contentsOf: data)
        var events: [ScrcpyEvent] = []
        while true {
            switch state {
            case .dummy:
                guard available >= 1 else { return events }
                _ = take(1)
                state = .name
            case .name:
                guard available >= 64 else { return events }
                let field = take(64)
                let end = field.firstIndex(of: 0) ?? field.count
                events.append(.deviceName(String(decoding: field[..<end], as: UTF8.self)))
                state = .codec
            case .codec:
                guard available >= 4 else { return events }
                let codec = Self.be32(take(4))
                guard codec == Self.h264 else { throw ScrcpyStreamError.unsupportedCodec(codec) }
                state = .header
            case .header:
                guard available >= 12 else { return events }
                let header = take(12)
                if header[0] & 0x80 != 0 {
                    let width = Int(Self.be32(header[4..<8])), height = Int(Self.be32(header[8..<12]))
                    guard (1...Self.maxDimension).contains(width), (1...Self.maxDimension).contains(height) else {
                        throw ScrcpyStreamError.invalidSession
                    }
                    events.append(.session(width: width, height: height))
                } else {
                    let flags = Self.be64(header[0..<8])
                    let size = Int(Self.be32(header[8..<12]))
                    guard size <= Self.maxPacket else { throw ScrcpyStreamError.packetTooLarge(size) }
                    if size > 0 {
                        state = .payload(config: flags & (1 << 62) != 0, key: flags & (1 << 61) != 0,
                                         pts: flags & ((1 << 61) - 1), size: size)
                    }
                }
            case let .payload(config, key, pts, size):
                guard available >= size else { return events }
                let payload = Data(take(size))
                events.append(config ? .config(payload) : .frame(payload, keyFrame: key, ptsMicros: pts))
                state = .header
            }
        }
    }
}
