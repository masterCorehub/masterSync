import Foundation

/// Annex B (start-code) H.264 as scrcpy sends it, and the length-prefixed form VideoToolbox expects.
enum H264 {
    /// Each NAL unit without its start code (00 00 01 or 00 00 00 01). Trailing zero bytes belong to the next start code.
    nonisolated static func nalUnits(in annexB: Data) -> [Data] {
        let bytes = [UInt8](annexB)
        var starts: [(code: Int, payload: Int)] = []
        var i = 0
        while i + 2 < bytes.count {
            if bytes[i] == 0, bytes[i + 1] == 0, bytes[i + 2] == 1 {
                starts.append((i, i + 3))
                i += 3
            } else { i += 1 }
        }
        return starts.enumerated().compactMap { index, start in
            var end = index + 1 < starts.count ? starts[index + 1].code : bytes.count
            while end > start.payload, index + 1 < starts.count, bytes[end - 1] == 0 { end -= 1 }
            return end > start.payload ? Data(bytes[start.payload..<end]) : nil
        }
    }

    nonisolated static func lengthPrefixed(fromAnnexB data: Data) -> Data {
        var output = Data()
        for unit in nalUnits(in: data) {
            let size = UInt32(unit.count)
            output.append(contentsOf: [UInt8(size >> 24 & 0xFF), UInt8(size >> 16 & 0xFF), UInt8(size >> 8 & 0xFF), UInt8(size & 0xFF)])
            output.append(unit)
        }
        return output
    }

    /// The SPS (NAL type 7) and PPS (type 8) of a configuration packet; nil unless both are there.
    nonisolated static func parameterSets(fromConfig data: Data) -> (sps: Data, pps: Data)? {
        let units = nalUnits(in: data)
        guard let sps = units.first(where: { $0.first.map { $0 & 0x1F } == 7 }),
              let pps = units.first(where: { $0.first.map { $0 & 0x1F } == 8 }) else { return nil }
        return (sps, pps)
    }
}
