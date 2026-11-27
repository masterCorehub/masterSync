import Foundation
import Security
import CryptoKit

public struct KeychainVault {
    private let service: String

    public init(service: String = "com.nexus.mastersync") { self.service = service }

    private func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
    }

    public func read(_ account: String) throws -> Data? {
        var attributes = query(account)
        attributes[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw NexusError.security(status) }
        guard let data = result as? Data else { throw NexusError.identity }
        return data
    }

    public func save(_ data: Data, account: String) throws {
        let lookup = query(account)
        let values = [kSecValueData as String: data]
        var status = SecItemUpdate(lookup as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(lookup.merging(values) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw NexusError.security(status) }
    }
}

public struct TLSIdentity {
    public let identity: SecIdentity
    public let certificate: Data
    public var pin: String { Data(SHA256.hash(data: certificate)).base64EncodedString() }
    private struct Material: Codable { let key: Data; let certificate: Data }

    public static func load(from vault: KeychainVault) throws -> TLSIdentity {
        if let existing = try vault.read("tls-identity-v1") {
            return try create(JSONDecoder().decode(Material.self, from: existing))
        }
        let material = try generate()
        let identity = try create(material)
        try vault.save(JSONEncoder().encode(material), account: "tls-identity-v1")
        return identity
    }

    static func ephemeral() throws -> TLSIdentity { try create(generate()) }

    private static func create(_ material: Material) throws -> TLSIdentity {
        let options: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 256
        ]
        guard let key = SecKeyCreateWithData(material.key as CFData, options as CFDictionary, nil),
              let cert = SecCertificateCreateWithData(nil, material.certificate as CFData),
              let identity = SecIdentityBridge.create(cert, key) else { throw NexusError.identity }
        return TLSIdentity(identity: identity, certificate: material.certificate)
    }

    private static func generate() throws -> Material {
        let privateKey = P256.Signing.PrivateKey()
        let publicBytes = privateKey.publicKey.x963Representation
        // X.509 supplies the envelope. CryptoKit generates the key and signs the certificate.
        let signatureAlgorithm = DER.sequence(DER.field(0x06, Data([0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x02])))
        let publicAlgorithm = DER.sequence(
            DER.field(0x06, Data([0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01])),
            DER.field(0x06, Data([0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07]))
        )
        let name = DER.sequence(DER.field(0x31, DER.sequence(
            DER.field(0x06, Data([0x55, 0x04, 0x03])),
            DER.field(0x0c, Data("Nexus masterSync".utf8))
        )))
        let now = Date()
        let validity = DER.sequence(DER.time(now.addingTimeInterval(-86400)), DER.time(now.addingTimeInterval(10 * 365 * 86400)))
        let serial = try Wire.random(16)
        let certificateBody = DER.sequence(
            DER.field(0xa0, DER.field(0x02, Data([2]))),
            DER.field(0x02, Data([1]) + serial),
            signatureAlgorithm, name, validity, name,
            DER.sequence(publicAlgorithm, DER.bits(publicBytes))
        )
        let signature = try privateKey.signature(for: certificateBody).derRepresentation
        return Material(key: privateKey.x963Representation,
                        certificate: DER.sequence(certificateBody, signatureAlgorithm, DER.bits(signature)))
    }
}

/// `SecIdentityCreate` lives in Security.framework, but only the newest SDKs declare it. Looking it up by name works with
/// every SDK (the CI runner's is older than a developer's Mac).
private enum SecIdentityBridge {
    private typealias CreateFunction = @convention(c) (CFAllocator?, SecCertificate, SecKey) -> Unmanaged<SecIdentity>?

    static func create(_ certificate: SecCertificate, _ key: SecKey) -> SecIdentity? {
        // RTLD_DEFAULT is (void *)-2 on Darwin.
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "SecIdentityCreate") else { return nil }
        let function = unsafeBitCast(symbol, to: CreateFunction.self)
        return function(nil, certificate, key)?.takeRetainedValue()
    }
}

private enum DER {
    static func field(_ tag: UInt8, _ body: Data) -> Data {
        let count = body.count
        if count < 128 { return Data([tag, UInt8(count)]) + body }
        var length: [UInt8] = []
        var remaining = count
        while remaining > 0 {
            length.insert(UInt8(remaining & 255), at: 0)
            remaining >>= 8
        }
        return Data([tag, 0x80 | UInt8(length.count)] + length) + body
    }

    static func sequence(_ fields: Data...) -> Data { field(0x30, fields.reduce(Data(), +)) }
    static func bits(_ bytes: Data) -> Data { field(0x03, Data([0]) + bytes) }

    static func time(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmmss'Z'"
        let value = formatter.string(from: date)
        if let year = Int(value.prefix(4)), (1950...2049).contains(year) {
            return field(0x17, Data(value.dropFirst(2).utf8))
        }
        return field(0x18, Data(value.utf8))
    }
}
