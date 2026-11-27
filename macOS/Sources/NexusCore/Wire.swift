import Foundation
import Security
import CryptoKit

public enum Wire {
    public static let version = 1
    public static let service = "_nexus-sync._tcp"
    public static let maxFrame = 256 * 1024
    public static let chunk = 64 * 1024
    public static let maxFileBytes: Int64 = 4 * 1024 * 1024 * 1024

    public static func id() -> String { UUID().uuidString.lowercased() }

    public static func validID(_ id: String?) -> Bool {
        guard let id, let uuid = UUID(uuidString: id) else { return false }
        return uuid.uuidString.lowercased() == id
    }

    public static func random(_ count: Int) throws -> Data {
        var bytes = Data(count: count)
        let status = bytes.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!)
        }
        guard status == errSecSuccess else { throw NexusError.security(status) }
        return bytes
    }

    public static func secret(_ base64: String?) -> Data? {
        guard let base64, let bytes = Data(base64Encoded: base64), bytes.count == 32 else { return nil }
        return bytes
    }

    // CryptoKit verifies the authentication code without an early-exit byte comparison.
    public static func matches(_ candidate: Data, _ secret: Data) -> Bool {
        let context = Data("nexus-auth-v1".utf8)
        let code = HMAC<SHA256>.authenticationCode(for: context, using: SymmetricKey(data: candidate))
        return HMAC<SHA256>.isValidAuthenticationCode(code, authenticating: context, using: SymmetricKey(data: secret))
    }

    public static func frame(_ body: Data) throws -> Data {
        guard (1...maxFrame).contains(body.count) else { throw NexusError.invalidFrame }
        var size = UInt32(body.count).bigEndian
        var data = Data(bytes: &size, count: 4)
        data.append(body)
        return data
    }

    public static func size(of header: Data) throws -> Int {
        guard header.count == 4 else { throw NexusError.invalidFrame }
        let size = header.reduce(0) { ($0 << 8) | Int($1) }
        guard (1...maxFrame).contains(size) else { throw NexusError.invalidFrame }
        return size
    }

    public static func visible(_ string: String, limit: Int = 80) -> String {
        String(string.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(limit))
    }
}

public enum NexusError: LocalizedError {
    case invalidFrame
    case identity
    case security(OSStatus)
    case transfer(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFrame: "A mensagem excede o limite ou está incompleta."
        case .identity: "Não foi possível carregar a identidade TLS do Mac."
        case let .security(status): "O Keychain retornou o código \(status)."
        case let .transfer(message): message
        }
    }
}

public struct Message: Codable {
    public var type: String
    public var version: Int?
    public var serverId: String?
    public var id: String?
    public var name: String?
    public var model: String?
    public var token: String?
    public var credential: String?
    public var message: String?
    public var battery: Int?
    public var charging: Bool?
    public var text: String?
    public var mime: String?
    public var data: String?
    public var size: Int64?
    public var offset: Int64?
    public var hash: String?
    public var scanPage: Bool?
    public var sensitive: Bool?
    public var app: String?
    public var at: Int64?
    public var canReply: Bool?
    public var canDismiss: Bool?
    public var noticeSync: Bool?
    public var notices: [Message]?
    public var dndAllowed: Bool?
    public var dndEnabled: Bool?
    public var group: String?
    public var clipboard: Bool?
    public var files: Bool?
    public var notifications: Bool?
    public var scanner: Bool?
    public var scanPaste: Bool?
    public var instantCamera: Bool?
    public var gallery: Bool?
    public var galleryRevision: Int?
    public var backgroundConnection: Bool?
    public var clipboardImages: Bool?
    public var media: [MediaEntry]?
    public var mediaId: String?
    public var transferId: String?
    public var album: String?
    public var albums: [MediaAlbum]?
    public var more: Bool?
    public var query: String?
    public var addedFrom: Int64?
    public var addedBefore: Int64?
    public var order: String?
    public var chat: Bool?
    public var adbProof: Bool?
    public var launcher: Bool?
    public var launcherApps: [AndroidApp]?
    public var launcherIcons: [AndroidAppIcon]?
    public var artist: String?
    public var albumName: String?
    public var year: Int?
    public var trackNumber: Int?
    public var trackCount: Int?
    public var durationMs: Int64?
    public var positionMs: Int64?
    public var speed: Double?
    public var artKey: String?
    public var canSeek: Bool?
    public var canLike: Bool?
    public var liked: Bool?
    public var hasQueue: Bool?
    public var queue: [MediaQueueItem]?
    public var queueId: Int64?
    public var components: [String]?
    public var screenWidth: Int?
    public var screenHeight: Int?
    public var mirror: Bool?
    public var findPhone: Bool?
    public var deviceControls: Bool?
    public var control: String?
    public var enabled: Bool?
    public var torch: Bool?
    public var torchAvailable: Bool?
    public var ringer: String?
    public var ringerAllowed: Bool?
    public var mediaControl: Bool?
    public var playing: Bool?
    public var rate: Int?
    public var quality: Int?

    public init(_ type: String) { self.type = type }
}

public struct MediaQueueItem: Codable, Identifiable, Equatable {
    public let id: Int64
    public let title: String

    public init(id: Int64, title: String) {
        self.id = id
        self.title = title
    }
}

public struct AndroidAppIcon: Codable {
    public let component: String
    public let data: String

    public init(component: String, data: String) {
        self.component = component
        self.data = data
    }
}

public struct AndroidApp: Codable, Identifiable {
    public let component: String
    public let label: String
    public var id: String { component }

    public init(component: String, label: String) {
        self.component = component
        self.label = label
    }

    public var validComponent: Bool {
        component.utf8.count <= 220
            && component.range(of: #"\A[A-Za-z0-9_.]+/[A-Za-z0-9_.$]+\z"#, options: .regularExpression) != nil
    }
}

public struct MediaEntry: Codable, Identifiable {
    public let id: String
    public let name: String
    public let mime: String
    public let album: String
    public let at: Int64
    public let size: Int64
}

public struct MediaAlbum: Codable, Identifiable {
    public let id: String
    public let name: String
}

public struct Invitation: Codable {
    public let version: Int
    public let serverId: String
    public let host: String
    public let port: UInt16
    public let pin: String
    public let token: String
    public let expiresAt: Int64
}

public struct Peer: Codable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let model: String
    public let credential: Data

    public init(id: String, name: String, model: String, credential: Data) {
        self.id = id
        self.name = name
        self.model = model
        self.credential = credential
    }
}
