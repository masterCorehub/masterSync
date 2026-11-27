import AppKit
import Foundation
import NexusCore
import UniformTypeIdentifiers

struct ReceivedFile: Identifiable, Codable {
    let peerID: String
    let offer: FileOffer
    let url: URL
    let date: Date
    var id: String { peerID + offer.id }
}

@MainActor
final class FileTransfers: ObservableObject {
    struct Progress: Identifiable {
        let id: String
        let name: String
        let peer: String
        let sending: Bool
        let size: Int64
        var offset: Int64
        var verifying = false
        /// A page from the phone's document scanner, which the Mac announces with a pop-up.
        var scan = false

        var fraction: Double { size == 0 ? 0 : Double(offset) / Double(size) }
    }

    private struct Outgoing {
        let file: URL
        let offer: FileOffer
        var nextOffset: Int64?
    }

    private struct Incoming {
        let file: URL
        let destination: URL
        let offer: FileOffer
    }

    @Published private(set) var progress: [Progress] = []
    @Published private(set) var received: [ReceivedFile] = []
    @Published private(set) var sent: [ReceivedFile] = []
    private var sentHistoryURL: URL { storage.appendingPathComponent("sent-history.json") }
    @Published private(set) var feedback: String?
    var didReceive: ((ReceivedFile) -> Void)?
    var didFail: ((String, String, String) -> Void)?
    private var outgoing: [String: Outgoing] = [:]
    private var incoming: [String: Incoming] = [:]
    private var preparing: [String: UUID] = [:]
    @Published private(set) var queued: [String: [URL]] = [:]
    private var verifies: Set<String> = []
    private var allowed: Set<String> = []
    private let storage: URL
    private let send: (String, Message) -> Void

    init(storage: URL, send: @escaping (String, Message) -> Void) {
        self.storage = storage
        self.send = send
        refreshReceived()
        if let data = try? Data(contentsOf: sentHistoryURL),
           let history = try? JSONDecoder().decode([ReceivedFile].self, from: data) {
            sent = history
        }
    }

    func allow(_ peer: String) {
        guard allowed.insert(peer).inserted else { return }
        if let out = outgoing[peer] {
            update(out.offer, peer: peer, sending: true, offset: 0)
            send(peer, out.offer.message)
        } else {
            sendNext(to: peer)
        }
    }

    func disconnect(_ peer: String, discardOutgoing: Bool = false) {
        allowed.remove(peer)
        incoming[peer] = nil
        if discardOutgoing {
            outgoing[peer] = nil
            queued[peer] = nil
            preparing[peer] = nil
        }
        progress.removeAll { $0.peer == peer }
    }

    func offer(_ file: URL, to peer: String) {
        guard outgoing[peer] == nil, preparing[peer] == nil, queued[peer]?.isEmpty != false else {
            feedback = "Já existe um envio para este dispositivo."
            return
        }
        _ = offerBatch([file], to: peer)
    }

    func offerBatch(_ urls: [URL], to peer: String) -> Bool {
        guard allowed.contains(peer) else {
            feedback = "Ative arquivos nos dois dispositivos."
            return false
        }
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return false }
        queued[peer, default: []].append(contentsOf: files)
        sendNext(to: peer)
        return true
    }

    private func sendNext(to peer: String) {
        guard allowed.contains(peer), outgoing[peer] == nil, preparing[peer] == nil,
              var files = queued[peer], !files.isEmpty else { return }
        let file = files.removeFirst()
        queued[peer] = files.isEmpty ? nil : files
        // Keep the preparation bound to this peer, even if authorization is revoked mid-read.
        let attempt = UUID()
        preparing[peer] = attempt
        feedback = "Preparando \(file.lastPathComponent)…"
        Task {
            defer {
                if preparing[peer] == attempt {
                    preparing[peer] = nil
                    sendNext(to: peer)
                }
            }
            do {
                let offer = try await Task.detached(priority: .utility) {
                    let access = file.startAccessingSecurityScopedResource()
                    defer { if access { file.stopAccessingSecurityScopedResource() } }
                    let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentTypeKey])
                    guard values.isRegularFile == true, let bytes = values.fileSize, Int64(bytes) <= Wire.maxFileBytes else {
                        throw NexusError.transfer("Escolha um arquivo regular de até 4 GB.")
                    }
                    return FileOffer(id: Wire.id(), name: file.lastPathComponent,
                                     mime: values.contentType?.preferredMIMEType ?? "application/octet-stream",
                                     size: Int64(bytes), hash: try FileOffer.hash(file))
                }.value
                guard preparing[peer] == attempt else { return }
                outgoing[peer] = Outgoing(file: file, offer: offer)
                if allowed.contains(peer) {
                    update(offer, peer: peer, sending: true, offset: 0)
                    send(peer, offer.message)
                }
                feedback = nil
            } catch {
                if preparing[peer] == attempt { feedback = error.localizedDescription }
            }
        }
    }

    func handle(_ message: Message, peer: String) {
        guard let id = message.id, Wire.validID(id) else { return }
        do {
            switch message.type {
            case "fileOffer":
                guard allowed.contains(peer), let offer = FileOffer(message) else {
                    throw NexusError.transfer("Recebimento de arquivos desativado ou oferta inválida.")
                }
                try accept(offer, from: peer)
            case "fileOffset", "fileAck":
                guard allowed.contains(peer), var out = outgoing[peer], out.offer.id == id,
                      let offset = message.offset, (0...out.offer.size).contains(offset) else { return }
                if message.type == "fileAck", out.nextOffset != offset { return }
                try writeNext(&out, at: offset, peer: peer)
                outgoing[peer] = out
            case "fileData":
                guard allowed.contains(peer), let record = incoming[peer], record.offer.id == id else { return }
                try write(message, record: record, from: peer)
            case "fileDone":
                guard allowed.contains(peer), let record = incoming[peer], record.offer.id == id else { return }
                verify(record, peer: peer)
            case "fileComplete":
                guard let record = outgoing[peer], record.offer.id == id else { return }
                outgoing[peer] = nil
                defer { sendNext(to: peer) }
                removeProgress(id, peer)
                // Only the receiver's completion message confirms a successful send.
                sent.insert(ReceivedFile(peerID: peer, offer: record.offer, url: record.file, date: .now), at: 0)
                feedback = "\(record.offer.name) enviado."
                do {
                    try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true,
                                                            attributes: [.posixPermissions: 0o700])
                    try JSONEncoder().encode(sent).write(to: sentHistoryURL, options: .atomic)
                } catch {
                    feedback = "Arquivo enviado. Não foi possível salvar o histórico."
                }
            case "fileError":
                clear(id, peer)
                let reason = Wire.visible(message.message ?? "A transferência falhou.", limit: 150)
                feedback = reason
                didFail?(id, peer, reason)
                sendNext(to: peer)
            default: break
            }
        } catch {
            fail(error, id, peer)
        }
    }

    private func accept(_ offer: FileOffer, from peer: String) throws {
        if let existing = incoming[peer], existing.offer != offer {
            throw NexusError.transfer("Já existe um arquivo em recebimento.")
        }
        let folder = storage.appendingPathComponent(peer).appendingPathComponent(offer.id)
        let meta = folder.appendingPathComponent("offer.json")
        let partial = folder.appendingPathComponent("content.part")
        let payload = folder.appendingPathComponent("arquivo", isDirectory: true)
        let destination = payload.appendingPathComponent(offer.name)
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        if let existing = try? Data(contentsOf: meta) {
            guard try JSONDecoder().decode(FileOffer.self, from: existing) == offer else { throw NexusError.invalidFrame }
        } else {
            try JSONEncoder().encode(offer).write(to: meta, options: .atomic)
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            reportReceived(offer.id, peer: peer)
            send(peer, reply("fileComplete", offer.id))
            return
        }
        if !FileManager.default.fileExists(atPath: partial.path) {
            try Data().write(to: partial, options: .atomic)
        }
        let offset = try Self.currentLength(partial)
        guard offset <= offer.size else { throw NexusError.invalidFrame }
        if let available = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage, offer.size - offset > max(0, available - 128 * 1024 * 1024) {
            throw NexusError.transfer("Espaço insuficiente no Mac.")
        }
        incoming[peer] = Incoming(file: partial, destination: destination, offer: offer)
        update(offer, peer: peer, sending: false, offset: offset)
        send(peer, reply("fileOffset", offer.id, offset: offset))
    }

    private func writeNext(_ out: inout Outgoing, at offset: Int64, peer: String) throws {
        let offer = out.offer
        update(offer, peer: peer, sending: true, offset: offset)
        if offset == offer.size {
            send(peer, reply("fileDone", offer.id))
            return
        }
        let access = out.file.startAccessingSecurityScopedResource()
        defer { if access { out.file.stopAccessingSecurityScopedResource() } }
        let reader = try FileHandle(forReadingFrom: out.file)
        defer { try? reader.close() }
        try reader.seek(toOffset: UInt64(offset))
        let count = min(Wire.chunk, Int(offer.size - offset))
        guard let bytes = try reader.read(upToCount: count), bytes.count == count else {
            throw NexusError.transfer("O arquivo original mudou durante o envio.")
        }
        out.nextOffset = offset + Int64(bytes.count)
        var part = reply("fileData", offer.id, offset: offset)
        part.data = bytes.base64EncodedString()
        send(peer, part)
    }

    private func write(_ message: Message, record: Incoming, from peer: String) throws {
        let offer = record.offer
        guard let offset = message.offset, offset >= 0, let body = message.data, let bytes = Data(base64Encoded: body),
              (1...Wire.chunk).contains(bytes.count), offset == (try Self.currentLength(record.file)),
              offset + Int64(bytes.count) <= offer.size else { throw NexusError.invalidFrame }
        let writer = try FileHandle(forWritingTo: record.file)
        defer { try? writer.close() }
        try writer.seek(toOffset: UInt64(offset))
        try writer.write(contentsOf: bytes)
        let updated = offset + Int64(bytes.count)
        update(offer, peer: peer, sending: false, offset: updated)
        send(peer, reply("fileAck", offer.id, offset: updated))
    }

    private func verify(_ record: Incoming, peer: String) {
        let offer = record.offer
        guard (try? Self.currentLength(record.file)) == offer.size else {
            fail(NexusError.transfer("Arquivo incompleto."), offer.id, peer)
            return
        }
        let key = peer + offer.id
        guard verifies.insert(key).inserted else { return }
        update(offer, peer: peer, sending: false, offset: offer.size, verifying: true)
        Task {
            defer { verifies.remove(key) }
            do {
                let valid = try await Task.detached(priority: .utility) {
                    try FileOffer.hash(record.file) == offer.hash
                }.value
                guard valid, try Self.currentLength(record.file) == offer.size else {
                    try? FileManager.default.removeItem(at: record.file)
                    throw NexusError.transfer("O arquivo falhou na verificação de integridade.")
                }
                try FileManager.default.moveItem(at: record.file, to: record.destination)
                incoming[peer] = nil
                removeProgress(offer.id, peer)
                refreshReceived()
                reportReceived(offer.id, peer: peer)
                feedback = "\(offer.name) recebido."
                send(peer, reply("fileComplete", offer.id))
            } catch { fail(error, offer.id, peer) }
        }
    }

    private func reply(_ type: String, _ id: String, offset: Int64? = nil) -> Message {
        var message = Message(type)
        message.id = id
        message.offset = offset
        return message
    }

    /// Size on disk right now. URL resource values are cached per URL instance and would go stale while a file grows.
    nonisolated static func currentLength(_ url: URL) throws -> Int64 {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func update(_ offer: FileOffer, peer: String, sending: Bool, offset: Int64, verifying: Bool = false) {
        let record = Progress(id: offer.id, name: offer.name, peer: peer, sending: sending,
                              size: offer.size, offset: offset, verifying: verifying, scan: offer.isScanPage)
        if let index = progress.firstIndex(where: { $0.id == offer.id && $0.peer == peer }) { progress[index] = record }
        else { progress.append(record) }
    }

    private func removeProgress(_ id: String, _ peer: String) {
        progress.removeAll { $0.id == id && $0.peer == peer }
    }

    private func clear(_ id: String, _ peer: String) {
        if outgoing[peer]?.offer.id == id { outgoing[peer] = nil }
        if incoming[peer]?.offer.id == id { incoming[peer] = nil }
        removeProgress(id, peer)
    }

    private func fail(_ error: Error, _ id: String, _ peer: String) {
        let text = Wire.visible(error.localizedDescription, limit: 150)
        feedback = text
        clear(id, peer)
        didFail?(id, peer, text)
        var message = reply("fileError", id)
        message.message = text
        send(peer, message)
        sendNext(to: peer)
    }

    private func reportReceived(_ id: String, peer: String) {
        if let file = received.first(where: { $0.peerID == peer && $0.offer.id == id }) { didReceive?(file) }
    }

    /// Where received files are kept on this Mac.
    var receivedDirectory: URL { storage }

    private func saveSentHistory() {
        try? JSONEncoder().encode(sent).write(to: sentHistoryURL, options: .atomic)
    }

    /// Forgets one sent file in the list (the file on the phone and on the Mac stay where they are).
    func removeSent(_ id: String) {
        sent.removeAll { $0.id == id }
        saveSentHistory()
    }

    func clearSent() {
        sent = []
        saveSentHistory()
    }

    func trashReceived(_ id: String) {
        guard let item = received.first(where: { $0.id == id }) else { return }
        do {
            // Trash only the indexed payload, never the transfer directory.
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            refreshReceived()
            feedback = nil
        } catch {
            feedback = "Não foi possível mover o arquivo para o Lixo: \(error.localizedDescription)"
        }
    }

    private func refreshReceived() {
        let manager = FileManager.default
        func files(_ directory: URL) -> [URL] {
            (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        }
        received = files(storage).filter { Wire.validID($0.lastPathComponent) }.flatMap { peer in
            files(peer).compactMap { folder in
                guard let data = try? Data(contentsOf: folder.appendingPathComponent("offer.json")),
                      let offer = try? JSONDecoder().decode(FileOffer.self, from: data) else { return nil }
                let url = folder.appendingPathComponent("arquivo").appendingPathComponent(offer.name)
                guard manager.fileExists(atPath: url.path) else { return nil }
                let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return ReceivedFile(peerID: peer.lastPathComponent, offer: offer, url: url, date: date)
            }
        }.sorted { $0.date > $1.date }
    }
}
