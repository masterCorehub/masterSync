import AppKit
import Foundation
import ImageIO
import NexusCore

@MainActor
final class GalleryModel: ObservableObject {
    struct Filters: Equatable {
        enum Period: String, CaseIterable {
            case any = "Qualquer data"
            case week = "Últimos 7 dias"
            case month = "Últimos 30 dias"
            case year = "Este ano"
            case custom = "Intervalo…"
        }

        enum Order: String, CaseIterable {
            case newest, oldest, name

            var title: String {
                switch self {
                case .newest: "Mais recentes"
                case .oldest: "Mais antigos"
                case .name: "Nome"
                }
            }
        }

        var name = ""
        var album = ""
        var mediaType = ""
        var period = Period.any
        var order = Order.newest
        var start = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .now
        var end = Date.now

        func apply(to message: inout Message, advanced: Bool, now: Date = .now, calendar: Calendar = .current) {
            if !album.isEmpty { message.album = album }
            if !mediaType.isEmpty { message.mime = mediaType }
            guard advanced else { return }
            if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { message.query = String(name.prefix(120)) }
            message.order = order.rawValue
            let today = calendar.startOfDay(for: now)
            switch period {
            case .any: break
            case .week:
                message.addedFrom = calendar.date(byAdding: .day, value: -6, to: today).map(seconds)
            case .month:
                message.addedFrom = calendar.date(byAdding: .day, value: -29, to: today).map(seconds)
            case .year:
                message.addedFrom = calendar.dateInterval(of: .year, for: now).map { seconds($0.start) }
            case .custom:
                let first = calendar.startOfDay(for: min(start, end))
                let last = calendar.startOfDay(for: max(start, end))
                message.addedFrom = seconds(first)
                // The sender queries an exclusive upper bound, so the entire last day is included.
                message.addedBefore = calendar.date(byAdding: .day, value: 1, to: last).map(seconds)
            }
        }

        private func seconds(_ date: Date) -> Int64 { Int64(date.timeIntervalSince1970) }
    }

    struct Preview: Identifiable {
        enum Content {
            case loading, image(NSImage), original(URL), failed(String)
        }

        let id: String
        let item: MediaEntry
        let fromTransfer: Bool
        var content: Content = .loading
    }

    @Published private(set) var items: [MediaEntry] = []
    @Published private(set) var albums: [MediaAlbum] = []
    @Published private(set) var thumbnails: [String: NSImage] = [:]
    @Published private(set) var more = false
    @Published private(set) var loading = false
    @Published private(set) var feedback: String?
    @Published private(set) var advanced = false
    @Published private(set) var backgroundConnection = false
    @Published var filters = Filters()
    @Published var preview: Preview?

    private var peer: String?
    private var libraryPeer: String?
    private var request: String?
    private var asked: Set<String> = []
    private var offset: Int64 = 0
    private var hasLoaded = false
    private var reload: Task<Void, Never>?
    private var originalRequests: [String: String] = [:]
    private var originals: [String: URL] = [:]
    var send: ((String, Message) -> Void)?

    func select(_ peer: String?, advanced: Bool, background: Bool) {
        if self.advanced != advanced { self.advanced = advanced }
        if backgroundConnection != background { backgroundConnection = background }
        guard self.peer != peer else { return }
        self.peer = peer
        reload?.cancel()
        albums = []
        items = []
        thumbnails = [:]
        asked = []
        loading = false
        more = false
        offset = 0
        request = nil
        feedback = nil
        preview = nil
        hasLoaded = false
        originalRequests = [:]
        originals = [:]
        if let peer, libraryPeer != peer {
            libraryPeer = peer
            filters = Filters()
        }
    }

    /// Fills the gallery without a phone, for snapshot tests.
    func loadForSnapshot(items: [MediaEntry], albums: [MediaAlbum], thumbnails: [String: NSImage], more: Bool = false) {
        self.items = items
        self.albums = albums
        self.thumbnails = thumbnails
        self.more = more
        loading = false
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        refresh()
    }

    func refresh() {
        guard let peer else { return }
        hasLoaded = true
        send?(peer, Message("galleryAlbums"))
        restartPage()
    }

    func filtersChanged() {
        // Invalidate the old response before waiting for the user to finish typing.
        request = nil
        reload?.cancel()
        loading = true
        more = false
        reload = Task {
            do { try await Task.sleep(for: .milliseconds(260)) } catch { return }
            restartPage()
        }
    }

    private func restartPage() {
        reload?.cancel()
        items = []
        offset = 0
        more = false
        page()
    }

    func page() {
        guard let peer else { loading = false; return }
        var message = Message("galleryList")
        let id = Wire.id()
        request = id
        message.id = id
        filters.apply(to: &message, advanced: advanced)
        message.offset = offset
        loading = true
        feedback = nil
        send?(peer, message)
        Task {
            try? await Task.sleep(for: .seconds(12))
            if request == id {
                request = nil
                loading = false
                feedback = "A galeria não respondeu. Confira a conexão do Android."
            }
        }
    }

    func thumbnail(_ id: String) {
        guard let peer, thumbnails[id] == nil, asked.insert(id).inserted else { return }
        var message = Message("galleryThumb")
        message.id = id
        send?(peer, message)
    }

    func open(_ item: MediaEntry) {
        guard advanced, let peer else { return }
        if let file = originals[item.id], FileManager.default.fileExists(atPath: file.path) {
            preview = Preview(id: Wire.id(), item: item, fromTransfer: true, content: .original(file))
        } else if item.mime.hasPrefix("image/") {
            let id = Wire.id()
            preview = Preview(id: id, item: item, fromTransfer: false)
            var message = Message("galleryPreview")
            message.id = id
            message.mediaId = item.id
            send?(peer, message)
            Task {
                try? await Task.sleep(for: .seconds(15))
                if preview?.id == id, case .loading = preview?.content {
                    preview?.content = .failed("A prévia não chegou. Tente atualizar a galeria.")
                }
            }
        } else {
            download(item, open: true)
        }
    }

    func download(_ item: MediaEntry, open: Bool = false) {
        guard let peer else { return }
        let existing = originalRequests.first { $0.value == item.id }?.key
        let transfer = existing ?? Wire.id()
        if open { preview = Preview(id: transfer, item: item, fromTransfer: true) }
        if existing != nil { return }
        var message = Message("galleryFetch")
        message.id = item.id
        if advanced {
            message.transferId = transfer
            originalRequests[transfer] = item.id
        }
        send?(peer, message)
        feedback = "Solicitando o arquivo original…"
    }

    func hasOriginal(_ item: MediaEntry) -> Bool {
        originals[item.id].map { FileManager.default.fileExists(atPath: $0.path) } == true
    }

    func received(_ file: ReceivedFile) {
        guard file.peerID == peer, let itemID = originalRequests.removeValue(forKey: file.offer.id) else { return }
        originals[itemID] = file.url
        feedback = "\(file.offer.name) recebido."
        if preview?.id == file.offer.id { preview?.content = .original(file.url) }
    }

    func transferFailed(_ id: String, from peer: String, reason: String) {
        guard self.peer == peer, originalRequests.removeValue(forKey: id) != nil else { return }
        feedback = reason
        if preview?.id == id { preview?.content = .failed(reason) }
    }

    func receive(_ message: Message, from peer: String) {
        guard self.peer == peer else { return }
        switch message.type {
        case "galleryPage":
            guard let request, request == message.id, let media = message.media, media.count <= 24 else { return }
            self.request = nil
            loading = false
            var known = Set(items.map(\.id))
            items.append(contentsOf: media.filter { Int64($0.id) != nil && known.insert($0.id).inserted })
            offset += Int64(media.count)
            more = !media.isEmpty && message.more == true
        case "galleryAlbumList":
            albums = Array((message.albums ?? []).prefix(128))
        case "galleryImage":
            guard let id = message.id, asked.remove(id) != nil, let value = message.data,
                  let image = Self.image(value, size: 224) else { return }
            thumbnails[id] = image
        case "galleryPreviewImage":
            guard let id = message.id, id == preview?.id,
                  preview?.item.id == message.mediaId, let value = message.data,
                  let image = Self.image(value, size: 1440, encodedLimit: 192_000) else { return }
            preview?.content = .image(image)
        case "galleryQueued":
            if let id = message.transferId, originalRequests[id] != nil { feedback = message.message }
        case "galleryStatus":
            let reason = Wire.visible(message.message ?? "O item está indisponível.", limit: 150)
            if let transfer = message.transferId {
                transferFailed(transfer, from: peer, reason: reason)
            } else if let id = message.id, id == preview?.id {
                preview?.content = .failed(reason)
            } else if let id = message.id, asked.remove(id) != nil {
                return
            } else if request != nil && message.id == request {
                request = nil
                loading = false
                feedback = reason
            } else if !advanced {
                feedback = reason
            }
        default: break
        }
    }

    static func image(_ base64: String, size: Int, encodedLimit: Int = 120_000) -> NSImage? {
        guard base64.utf8.count <= encodedLimit,
              let bytes = Data(base64Encoded: base64),
              let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: size,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: thumb, size: NSSize(width: thumb.width, height: thumb.height))
    }
}
