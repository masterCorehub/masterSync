import Darwin
import Foundation
import Network
import Security

public struct DeviceStatus: Equatable {
    public let battery: Int?
    public let charging: Bool
}

public final class LocalServer {
    public static let preferredPort: UInt16 = 47525

    public struct Pending: Identifiable {
        public var id: String { peer.id }
        public let peer: Peer
        public let expires: Date
    }

    public private(set) var peers: [Peer] = []
    public private(set) var online: Set<String> = []
    public private(set) var status: [String: DeviceStatus] = [:]
    public private(set) var pending: Pending?
    public private(set) var port: UInt16?
    public private(set) var failure: String?
    public private(set) var announcementFailure: String?
    public let id: String
    public let name: String
    public var onUpdate: (() -> Void)?
    public var onSession: ((String) -> Void)?
    public var onMessage: ((String, Message) -> Void)?

    private let identity: TLSIdentity
    private let savePeers: ([Peer]) throws -> Void
    private var listener: NWListener?
    private var connections: [UUID: FramedConnection] = [:]
    private var sessions: [String: UUID] = [:]
    private var request: (connection: UUID, expires: Date)?
    private var invitation: (token: Data, expires: Date)?
    private var requested: Bool { request != nil }

    // The listener, frames, and UI callbacks all run on the main queue.
    public convenience init(vault: KeychainVault = KeychainVault()) throws {
        let macID: String
        if let bytes = try vault.read("id-v1"), let id = String(data: bytes, encoding: .utf8), Wire.validID(id) {
            macID = id
        } else {
            macID = Wire.id()
            try vault.save(Data(macID.utf8), account: "id-v1")
        }
        let peers = try vault.read("peers-v1").map { try JSONDecoder().decode([Peer].self, from: $0) } ?? []
        try self.init(identity: TLSIdentity.load(from: vault), id: macID,
                      name: Wire.visible(Host.current().localizedName ?? "Mac"), peers: peers) {
            try vault.save(JSONEncoder().encode($0), account: "peers-v1")
        }
    }

    public static func temporary() throws -> LocalServer {
        // An independent TLS identity and peer list live only for this process.
        try LocalServer(identity: TLSIdentity.ephemeral(), id: Wire.id(),
                        name: Wire.visible(Host.current().localizedName ?? "Mac"), peers: []) { _ in }
    }

    init(identity: TLSIdentity, id: String, name: String, peers: [Peer], savePeers: @escaping ([Peer]) throws -> Void) {
        self.identity = identity
        self.id = id
        self.name = name
        self.peers = peers
        self.savePeers = savePeers
    }

    public func start(port portNumber: UInt16 = LocalServer.preferredPort, advertise: Bool = true) {
        guard listener == nil else { return }
        failure = nil
        announcementFailure = nil
        openListener(port: portNumber, advertise: advertise)
    }

    private func openListener(port portNumber: UInt16, advertise: Bool) {
        do {
            guard let local = sec_identity_create(identity.identity) else { throw NexusError.identity }
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv13)
            sec_protocol_options_set_local_identity(tls.securityProtocolOptions, local)
            let tcp = NWProtocolTCP.Options()
            tcp.noDelay = true
            let parameters = NWParameters(tls: tls, tcp: tcp)
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: portNumber) ?? .any)
            if advertise {
                listener.service = .init(name: id, type: Wire.service, domain: "local.")
                listener.serviceRegistrationUpdateHandler = { [weak self, weak listener] change in
                    guard let self, let listener, listener === self.listener else { return }
                    if case let .add(endpoint) = change,
                       case let .service(name, _, _, _) = endpoint {
                        self.announcementFailure = name == self.id ? nil : "O nome Bonjour mudou. Use o endereço alternativo do QR."
                    }
                    self.onUpdate?()
                }
            }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self, let listener, listener === self.listener else { return }
                switch state {
                case .waiting(let error), .failed(let error):
                    if case .posix(.EADDRINUSE) = error, portNumber != 0, self.port == nil {
                        // Cancel the old listener before asking the system to pick a free port.
                        self.listener = nil
                        self.announcementFailure = nil
                        listener.cancel()
                        self.openListener(port: 0, advertise: advertise)
                        return
                    }
                    if case .failed = state {
                        self.stop()
                        self.failure = "Falha ao abrir o serviço local. \(error.localizedDescription)"
                    } else {
                        self.failure = "A rede local está indisponível. \(error.localizedDescription)"
                    }
                case .ready:
                    self.port = listener.port?.rawValue
                    self.failure = nil
                default: break
                }
                self.onUpdate?()
            }
            listener.newConnectionHandler = { [weak self, weak listener] connection in
                guard let self, let listener, listener === self.listener else {
                    connection.cancel()
                    return
                }
                self.accept(connection)
            }
            self.listener = listener
            listener.start(queue: .main)
        } catch NWError.posix(.EADDRINUSE) where portNumber != 0 {
            openListener(port: 0, advertise: advertise)
        } catch {
            failure = error.localizedDescription
            onUpdate?()
        }
    }

    public func stop() {
        let previous = listener
        listener = nil
        port = nil
        failure = nil
        announcementFailure = nil
        invitation = nil
        previous?.cancel()
        Array(connections.values).forEach { $0.close() }
        onUpdate?()
    }

    public func invite(host: String? = nil) throws -> Invitation {
        guard let port else { throw NexusError.transfer("Ative a rede local antes de gerar o QR.") }
        guard !requested else { throw NexusError.transfer("Conclua a solicitação de pareamento atual.") }
        let token = try Wire.random(32)
        let expiry = Date().addingTimeInterval(180)
        invitation = (token, expiry)
        return Invitation(version: Wire.version, serverId: id, host: host ?? Self.localIPv4() ?? "",
                          port: port, pin: identity.pin, token: token.base64EncodedString(),
                          expiresAt: Int64(expiry.timeIntervalSince1970))
    }

    public func cancelInvitation() {
        invitation = nil
        if let pending { confirm(pending.id, allow: false) }
    }

    public func confirm(_ peerID: String, allow: Bool) {
        guard let pending, pending.id == peerID, let request, let link = connections[request.connection] else { return }
        self.pending = nil
        self.request = nil
        defer { onUpdate?() }
        guard allow, request.expires > Date() else {
            reject(link, "Pareamento recusado ou expirado.")
            return
        }
        let updated = peers.filter { $0.id != peerID } + [pending.peer]
        do {
            try savePeers(updated)
            peers = updated
            establish(link, connectionID: request.connection, peer: pending.peer)
        } catch {
            failure = error.localizedDescription
            reject(link, "O Mac não conseguiu salvar a autorização.")
        }
    }

    public func revoke(_ id: String) throws {
        let updated = peers.filter { $0.id != id }
        try savePeers(updated)
        peers = updated
        if let session = sessions[id], let link = connections[session] {
            // Remove routing immediately. The final message only reports the revocation.
            sessions[id] = nil
            online.remove(id)
            status[id] = nil
            reject(link, "O Mac revogou este dispositivo.")
        }
        onUpdate?()
    }

    public func send(_ message: Message, to peerID: String) {
        if let id = sessions[peerID] { connections[id]?.send(message) }
    }

    private func accept(_ socket: NWConnection) {
        guard connections.count < 16 else { socket.cancel(); return }
        let id = UUID()
        let link = FramedConnection(socket)
        connections[id] = link
        link.onMessage = { [weak self, weak link] message in
            guard let self, let link else { return }
            self.authenticate(message, link: link, connectionID: id)
        }
        link.onClose = { [weak self] in self?.disconnected(id) }
        link.start()
    }

    private func authenticate(_ message: Message, link: FramedConnection, connectionID: UUID) {
        guard message.version == Wire.version, message.serverId == id else {
            reject(link, "A versão ou o identificador do Mac não corresponde.")
            return
        }
        guard let peerID = message.id, Wire.validID(peerID), let credential = Wire.secret(message.credential) else {
            reject(link, "Credencial inválida.")
            return
        }
        switch message.type {
        case "resume":
            guard let peer = peers.first(where: { $0.id == peerID }), Wire.matches(credential, peer.credential) else {
                reject(link, "Dispositivo não autorizado. Gere um novo QR no Mac.")
                return
            }
            establish(link, connectionID: connectionID, peer: peer)
        case "pair":
            guard !requested,
                  peers.first(where: { $0.id == peerID }) != nil || peers.count < 12,
                  let invitation, invitation.expires > Date(),
                  let token = Wire.secret(message.token), Wire.matches(token, invitation.token),
                  let name = message.name, !name.isEmpty, let model = message.model else {
                reject(link, "QR inválido, expirado ou ocupado.")
                return
            }
            let peer = Peer(id: peerID, name: Wire.visible(name), model: Wire.visible(model), credential: credential)
            self.invitation = nil
            pending = Pending(peer: peer, expires: invitation.expires)
            request = (connectionID, invitation.expires)
            link.onMessage = { [weak link] _ in link?.close() }
            link.expire(in: invitation.expires.timeIntervalSinceNow)
            onUpdate?()
        default:
            reject(link, "Autenticação necessária.")
        }
    }

    private func establish(_ link: FramedConnection, connectionID: UUID, peer: Peer) {
        let previous = sessions[peer.id]
        sessions[peer.id] = connectionID
        if let previous, previous != connectionID { connections[previous]?.close() }
        online.insert(peer.id)
        status[peer.id] = nil
        link.expire(in: 35)
        link.onMessage = { [weak self, weak link] message in
            guard let self, let link, self.sessions[peer.id] == connectionID else { return }
            link.expire(in: 35)
            switch message.type {
            case "ping":
                link.send(Message("pong"))
            case "status":
                let level = message.battery.flatMap { (0...100).contains($0) ? $0 : nil }
                self.status[peer.id] = DeviceStatus(battery: level, charging: message.charging ?? false)
                self.onUpdate?()
            default:
                self.onMessage?(peer.id, message)
            }
        }
        var response = Message("accepted")
        response.version = Wire.version
        response.serverId = id
        response.name = name
        link.send(response)
        onUpdate?()
        onSession?(peer.id)
    }

    private func reject(_ link: FramedConnection, _ description: String) {
        link.onMessage = nil
        link.expire(in: 2)
        var message = Message("reject")
        message.message = description
        link.send(message) { [weak link] in link?.close() }
    }

    private func disconnected(_ id: UUID) {
        connections[id] = nil
        if request?.connection == id { pending = nil; request = nil }
        if let peerID = sessions.first(where: { $0.value == id })?.key {
            sessions[peerID] = nil
            online.remove(peerID)
            status[peerID] = nil
        }
        onUpdate?()
    }

    static func localIPv4() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let list else { return nil }
        defer { freeifaddrs(list) }
        var choices: [String: String] = [:]
        var current: UnsafeMutablePointer<ifaddrs>? = list
        while let pointer = current {
            let value = pointer.pointee
            current = value.ifa_next
            guard let address = value.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  value.ifa_flags & UInt32(IFF_UP) != 0, value.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            let name = String(cString: value.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                choices[name] = String(cString: buffer)
            }
        }
        return choices.keys.sorted().compactMap { choices[$0] }.first
    }
}
