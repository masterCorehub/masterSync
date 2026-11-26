import Foundation
import Network

final class FramedConnection {
    private let socket: NWConnection
    private var deadline: DispatchWorkItem?
    private var closed = false
    var onClose: (() -> Void)?
    var onMessage: ((Message) -> Void)?

    init(_ socket: NWConnection) { self.socket = socket }

    /// The IPv4 address the other side connected from, when it has one.
    var remoteHost: String? { Self.ipv4(from: socket.currentPath?.remoteEndpoint ?? socket.endpoint) }

    /// IPv4 only: a plain IPv4 host, or an IPv4 carried inside an IPv6 address. Anything else is not usable for ADB.
    static func ipv4(from endpoint: NWEndpoint?) -> String? {
        guard case let .hostPort(host, _)? = endpoint else { return nil }
        switch host {
        case .ipv4(let address): return "\(address)".split(separator: "%").first.map(String.init)
        case .ipv6(let address): return address.asIPv4.map { "\($0)".split(separator: "%").first.map(String.init) ?? "" }
        default: return nil
        }
    }

    func start() {
        expire(in: 12)
        socket.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.readHeader()
            case .failed, .cancelled: self?.close()
            case .waiting(.tls): self?.close()
            default: break
            }
        }
        socket.start(queue: .main)
    }

    func expire(in seconds: TimeInterval) {
        deadline?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.close() }
        deadline = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, seconds), execute: work)
    }

    func send(_ message: Message, completion: (() -> Void)? = nil) {
        guard !closed else { return }
        do {
            let data = try Wire.frame(JSONEncoder().encode(message))
            socket.send(content: data, completion: .contentProcessed { [weak self] error in
                if error != nil { self?.close() }
                else { completion?() }
            })
        } catch {
            close()
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        deadline?.cancel()
        socket.stateUpdateHandler = nil
        socket.cancel()
        onClose?()
        onClose = nil
        onMessage = nil
    }

    private func readHeader() {
        read(count: 4) { [weak self] data in
            guard let self, let size = try? Wire.size(of: data) else { self?.close(); return }
            self.read(count: size) { [weak self] payload in
                guard let self, let message = try? JSONDecoder().decode(Message.self, from: payload) else {
                    self?.close()
                    return
                }
                self.onMessage?(message)
                self.readHeader()
            }
        }
    }

    private func read(count: Int, completion: @escaping (Data) -> Void) {
        guard !closed else { return }
        socket.receive(minimumIncompleteLength: count, maximumLength: count) { [weak self] data, _, _, error in
            guard let self, !self.closed else { return }
            guard error == nil, let data, data.count == count else { self.close(); return }
            completion(data)
        }
    }
}
