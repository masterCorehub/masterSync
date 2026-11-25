import CryptoKit
import Foundation

public struct FileOffer: Codable, Equatable {
    public let id: String
    public let name: String
    public let mime: String
    public let size: Int64
    public let hash: String
    public let scanPage: Bool?

    public init(id: String, name: String, mime: String, size: Int64, hash: String, scanPage: Bool? = nil) {
        self.id = id
        self.name = Self.safeFilename(name)
        self.mime = Wire.visible(mime, limit: 120)
        self.size = size
        self.hash = hash
        self.scanPage = scanPage == true && self.mime == "image/jpeg" ? true : nil
    }

    public var isScanPage: Bool { scanPage == true && mime == "image/jpeg" }

    public init?(_ message: Message) {
        guard let id = message.id, Wire.validID(id), let name = message.name, let size = message.size,
              (0...Wire.maxFileBytes).contains(size), let hash = message.hash, Wire.secret(hash) != nil else { return nil }
        self.init(id: id, name: name, mime: message.mime ?? "application/octet-stream", size: size,
                  hash: hash, scanPage: message.scanPage)
    }

    public var message: Message {
        var message = Message("fileOffer")
        message.id = id
        message.name = name
        message.mime = mime
        message.size = size
        message.hash = hash
        // Older peers can ignore this optional field and still receive the JPEG.
        message.scanPage = scanPage
        return message
    }

    public static func safeFilename(_ name: String) -> String {
        let sanitized = Wire.visible(name, limit: 120)
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = String(sanitized.drop(while: { $0 == "." }))
        var result = ""
        for character in visible {
            if result.utf8.count + String(character).utf8.count > 200 { break }
            result.append(character)
        }
        return result.isEmpty ? "Arquivo recebido" : result
    }

    public static func hash(_ url: URL) throws -> String {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var hasher = SHA256()
        while let bytes = try input.read(upToCount: 256 * 1024), !bytes.isEmpty { hasher.update(data: bytes) }
        return Data(hasher.finalize()).base64EncodedString()
    }
}
