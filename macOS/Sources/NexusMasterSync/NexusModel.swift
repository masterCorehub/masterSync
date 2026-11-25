import AppKit
import Combine
import Foundation
import NexusCore

enum Section: String, CaseIterable, Identifiable {
    case overview = "Visão geral"
    case clipboard = "Área de transferência"
    case documents = "Documentos"
    case gallery = "Galeria"
    case files = "Arquivos"
    case notifications = "Notificações"
    case remote = "Controle remoto"
    case devices = "Dispositivos"
    case settings = "Configurações"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: "rectangle.grid.1x2"
        case .clipboard: "document.on.clipboard"
        case .documents: "doc.viewfinder"
        case .gallery: "photo.on.rectangle.angled"
        case .files: "folder"
        case .notifications: "bell"
        case .remote: "cursorarrow.rays"
        case .devices: "iphone"
        case .settings: "gearshape"
        }
    }
}

@MainActor
final class NexusModel: ObservableObject {
    struct Event: Identifiable {
        var id = UUID()
        let title: String
        var date = Date.now
        let icon: String
    }

    @Published var section = Section.overview
    @Published private(set) var peers: [Peer] = []
    @Published private(set) var online: Set<String> = []
    @Published private(set) var deviceStatus: [String: DeviceStatus] = [:]
    @Published private(set) var pending: LocalServer.Pending?
    @Published private(set) var events: [Event] = []
    @Published private(set) var serviceReady = false
    @Published private(set) var connecting = false
    @Published private(set) var networkProblem: String?
    @Published private(set) var otherCopyRunning = false
    @Published var problem: String?
    @Published var invitation: Invitation?
    @Published private(set) var permissions: [String: Message] = [:]
    @Published var selectedID: String? {
        didSet {
            if oldValue != selectedID { screen.end() }
            advertiseCapabilities()
        }
    }
    @Published var clipboardEnabled: Bool { didSet { persist(clipboardEnabled, "clipboard"); advertiseCapabilities() } }
    @Published var historyEnabled: Bool {
        didSet { persist(historyEnabled, "history"); clipboard.recordHistory = historyEnabled }
    }
    @Published var filesEnabled: Bool { didSet { persist(filesEnabled, "files"); advertiseCapabilities() } }
    @Published var notificationsEnabled: Bool {
        didSet { persist(notificationsEnabled, "notifications"); updateNotifications(); advertiseCapabilities() }
    }
    @Published var hideNotices: Bool {
        didSet { persist(hideNotices, "hide-notices"); updateNotifications(); notifications.removeAll() }
    }
    @Published var quiet: Bool { didSet { persist(quiet, "quiet"); updateNotifications() } }
    @Published var blockedApps: Set<String> {
        didSet { preferences.set(Array(blockedApps), forKey: "blocked-apps"); updateNotifications(); notifications.removeAll() }
    }
    @Published var theme: String { didSet { preferences.set(theme, forKey: "theme") } }
    @Published var devicesShortcut: String { didSet { preferences.set(devicesShortcut, forKey: "shortcut-devices") } }
    @Published var filesShortcut: String { didSet { preferences.set(filesShortcut, forKey: "shortcut-files") } }
    @Published var galleryEnabled: Bool {
        didSet { persist(galleryEnabled, "gallery"); advertiseCapabilities() }
    }
    @Published var scanRequestFeedback: String?
    @Published var actionFeedback: String?

    let clipboard: ClipboardSync
    let adbClipboard = ADBClipboard()
    private let clipboardImages = ClipboardImages()
    private var clipboardImagePeer: String?
    let notifications = NotificationSync()
    let gallery = GalleryModel()
    let screen = ScreenMirror()
    let files: FileTransfers
    private let preferences = UserDefaults.standard
    private var server: LocalServer?
    private var timer: AnyCancellable?
    private var quitObserver: AnyCancellable?
    private var childObservers: [AnyCancellable] = []
    private let relay = Outbound()

    private final class Outbound {
        var forward: ((String, Message) -> Void)?
    }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nexus masterSync", isDirectory: true)
        clipboard = ClipboardSync(file: base.appendingPathComponent("clipboard.json"))
        let relay = relay
        files = FileTransfers(storage: base.appendingPathComponent("Inbox", isDirectory: true)) { peer, message in
            relay.forward?(peer, message)
        }
        clipboardEnabled = preferences.bool(forKey: "clipboard")
        historyEnabled = preferences.bool(forKey: "history")
        filesEnabled = preferences.bool(forKey: "files")
        notificationsEnabled = preferences.bool(forKey: "notifications")
        galleryEnabled = preferences.bool(forKey: "gallery")
        hideNotices = preferences.object(forKey: "hide-notices") as? Bool ?? true
        quiet = preferences.bool(forKey: "quiet")
        blockedApps = Set(preferences.stringArray(forKey: "blocked-apps") ?? [])
        theme = preferences.string(forKey: "theme") ?? "dark"
        devicesShortcut = preferences.string(forKey: "shortcut-devices") ?? "d"
        filesShortcut = preferences.string(forKey: "shortcut-files") ?? "f"
        relay.forward = { [weak self] in self?.server?.send($1, to: $0) }
        clipboard.recordHistory = historyEnabled
        adbClipboard.receive = { [weak self] event in self?.clipboard.receive(event) }
        screen.send = { [weak self] in self?.server?.send($1, to: $0) }
        gallery.send = { [weak self] in self?.server?.send($1, to: $0) }
        files.didReceive = { [weak self] file in self?.gallery.received(file) }
        files.didFail = { [weak self] id, peer, reason in self?.gallery.transferFailed(id, from: peer, reason: reason) }
        clipboard.forward = { [weak self] text in
            guard let self, let peer = selected, canClipboard(peer.id) else { return }
            clipboardImages.cancelOutgoing()
            var message = Message("clipboard")
            message.text = text
            server?.send(message, to: peer.id)
            addEvent("Texto enviado para \(peer.name)", "document.on.clipboard")
        }
        clipboard.forwardImage = { [weak self] bytes, mime, peer in
            guard let self, peer == clipboardImagePeer, canClipboard(peer) else { return }
            clipboardImages.offer(bytes, mime: mime)
        }
        clipboardImages.send = { [weak self] message in
            guard let self, let peer = clipboardImagePeer, canClipboard(peer) else { return }
            server?.send(message, to: peer)
        }
        clipboardImages.received = { [weak self] bytes, mime in
            self?.clipboard.applyImage(bytes, mime: mime)
            self?.addEvent("Imagem recebida", "photo")
        }
        notifications.send = { [weak self] in
            guard let self, self.notificationsEnabled, self.online.contains($0) else { return }
            self.server?.send($1, to: $0)
        }
        childObservers = [clipboard.objectWillChange, adbClipboard.objectWillChange, files.objectWillChange,
                          notifications.objectWillChange, gallery.objectWillChange, screen.objectWillChange].map {
            $0.sink { [weak self] _ in self?.objectWillChange.send() }
        }
        updateNotifications()
        timer = Timer.publish(every: 0.45, on: .main, in: .common).autoconnect().sink { [weak self] time in
            guard let self else { return }
            self.clipboard.tick(sync: self.clipboardEnabled, imagePeer: self.clipboardImagePeer)
            self.clipboardImages.expire()
            if let invitation = self.invitation, Int64(time.timeIntervalSince1970) >= invitation.expiresAt {
                self.invitation = nil
                self.problem = "O QR expirou. Gere um novo código."
            }
        }
    }

    var selected: Peer? { peers.first { $0.id == selectedID } ?? peers.first(where: { online.contains($0.id) }) ?? peers.first }
    var active: Bool { selected.map { online.contains($0.id) } ?? false }
    var selectedStatus: DeviceStatus? { selected.flatMap { deviceStatus[$0.id] } }
    var canSendFiles: Bool { selected.map { filesEnabled && online.contains($0.id) && permissions[$0.id]?.files == true } ?? false }
    var canPlayMedia: Bool { active && selected.map { permissions[$0.id]?.mediaControl == true } == true }
    var canFindPhone: Bool { active && selected.map { permissions[$0.id]?.findPhone == true } == true }
    var canMirror: Bool { active && selected.map { permissions[$0.id]?.mirror == true } == true }
    var canBrowseGallery: Bool { galleryEnabled && active && selected.map { permissions[$0.id]?.gallery == true } == true }
    var canRequestScan: Bool { selected.map { canSendFiles && permissions[$0.id]?.scanner == true } ?? false }

    func launch() {
        if quitObserver == nil {
            quitObserver = NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification).sink { [weak self] _ in
                self?.screen.end()
                self?.screen.stopUSB()
                self?.adbClipboard.stop()
                self?.server?.stop()
            }
        }
        notifications.activate()
        if preferences.bool(forKey: "network-consent") { enableNetwork() }
    }

    func enableNetwork() {
        guard !connecting, !serviceReady else { return }
        problem = nil
        otherCopyRunning = otherNexusCopy != nil
        if otherCopyRunning {
            networkProblem = "Outra cópia do Nexus está aberta. Encerre essa cópia com ⌘Q para ativar a rede aqui."
            return
        }
        networkProblem = nil
        connecting = true
        do {
            if server == nil {
                let server = try LocalServer()
                server.onUpdate = { [weak self] in self?.refresh() }
                server.onSession = { [weak self] peer in self?.resetSession(peer) }
                server.onMessage = { [weak self] peer, message in self?.receive(message, peer: peer) }
                self.server = server
            }
            preferences.set(true, forKey: "network-consent")
            server?.start()
            refresh()
        } catch {
            connecting = false
            problem = error.localizedDescription
        }
    }

    var networkPort: UInt16? { server?.port }

    func showOtherCopy() {
        if let otherNexusCopy { otherNexusCopy.activate() }
        else { enableNetwork() }
    }

    private var otherNexusCopy: NSRunningApplication? {
        guard let id = Bundle.main.bundleIdentifier else { return nil }
        let pid = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .first { $0.processIdentifier != pid && !$0.isTerminated }
    }

    func disableNetwork() {
        preferences.set(false, forKey: "network-consent")
        connecting = false
        invitation = nil
        server?.stop()
        problem = nil
    }

    func pair(usb: Bool = false) {
        do { invitation = try server?.invite(host: usb ? "127.0.0.1" : nil) }
        catch { problem = error.localizedDescription }
    }

    func cancelPair() {
        invitation = nil
        server?.cancelInvitation()
    }

    func confirm(_ peer: LocalServer.Pending, allow: Bool) {
        server?.confirm(peer.id, allow: allow)
        if allow, peers.contains(where: { $0.id == peer.id }) {
            selectedID = peer.id
            addEvent("\(peer.peer.name) autorizado", "checkmark.shield")
        }
        invitation = nil
    }

    func revoke(_ peer: Peer) {
        do {
            try server?.revoke(peer.id)
            files.disconnect(peer.id, discardOutgoing: true)
            notifications.removePeer(peer.id)
            if selectedID == peer.id { selectedID = nil }
            addEvent("\(peer.name) removido", "iphone.slash")
        } catch { problem = error.localizedDescription }
    }

    func sendFile(_ url: URL) {
        guard let peer = selected else { return }
        files.offer(url, to: peer.id)
    }

    func findPhone() {
        if canFindPhone, let peer = selected { server?.send(Message("ringPhone"), to: peer.id) }
    }

    func mediaControl(_ command: String) {
        guard canPlayMedia, let peer = selected else { return }
        var message = Message("mediaCommand")
        message.message = command
        server?.send(message, to: peer.id)
    }

    func requestMirror() {
        if canMirror, let peer = selected { screen.begin(peer.id) }
    }

    func requestScan() {
        guard let peer = selected, canRequestScan else { return }
        server?.send(Message("scanRequest"), to: peer.id)
        scanRequestFeedback = "Solicitação enviada. Confirme a abertura do scanner no celular."
    }

    private func persist(_ value: Bool, _ key: String) { preferences.set(value, forKey: key) }

    private func updateNotifications() {
        notifications.enabled = notificationsEnabled
        notifications.hideContent = hideNotices
        notifications.quiet = quiet
        notifications.blocked = blockedApps
        if !notificationsEnabled { notifications.removeAll() }
    }

    private func refresh() {
        guard let server else { return }
        peers = server.peers
        pending = server.pending
        deviceStatus = server.status
        serviceReady = server.port != nil
        if serviceReady || server.failure != nil { connecting = false }
        networkProblem = server.failure ?? server.announcementFailure
        let newlyOnline = server.online.subtracting(online)
        let disconnected = online.subtracting(server.online)
        online = server.online
        for id in disconnected {
            permissions[id] = nil
            screen.disconnect(id)
            files.disconnect(id)
            notifications.removePeer(id)
            if let peer = peers.first(where: { $0.id == id }) { addEvent("\(peer.name) desconectado", "wifi.slash") }
        }
        for id in newlyOnline {
            if let peer = peers.first(where: { $0.id == id }) { addEvent("\(peer.name) conectado", "wifi") }
        }
        advertiseCapabilities()
    }

    private func resetSession(_ peer: String) {
        permissions[peer] = nil
        updateClipboardImages()
        screen.disconnect(peer)
        updateGallery()
        files.disconnect(peer)
        sendCapabilities(peer)
    }

    private func receive(_ message: Message, peer: String) {
        switch message.type {
        case "capabilities":
            permissions[peer] = message
            updateClipboardImages()
            if message.notifications != true { notifications.removePeer(peer) }
            updateFilePermission(peer)
            updateGallery()
        case "clipboard":
            guard canClipboard(peer), message.sensitive != true else { return }
            clipboardImages.cancelIncoming()
            clipboard.receive(message)
            addEvent("Texto recebido", "document.on.clipboard")
        case let type where type.hasPrefix("clipboardImage"):
            if peer == clipboardImagePeer && canClipboard(peer) && message.sensitive != true {
                clipboardImages.receive(message)
            }
        case "notice", "noticeRemoved":
            if permissions[peer]?.notifications == true { notifications.handle(message, peer: peer) }
        case "actionStatus":
            actionFeedback = Wire.visible(message.message ?? "", limit: 130)
        case "scanStatus":
            scanRequestFeedback = Wire.visible(message.message ?? "", limit: 130)
        case let type where type.hasPrefix("screen"):
            screen.receive(message, from: peer)
        case let type where type.hasPrefix("gallery"):
            gallery.receive(message, from: peer)
        case let type where type.hasPrefix("file"):
            files.handle(message, peer: peer)
        default: break
        }
    }

    private func canClipboard(_ peer: String) -> Bool {
        clipboardEnabled && selected?.id == peer && online.contains(peer) && permissions[peer]?.clipboard == true
    }

    private func advertiseCapabilities() {
        updateClipboardImages()
        updateGallery()
        for peer in online {
            sendCapabilities(peer)
            updateFilePermission(peer)
        }
    }

    private func sendCapabilities(_ peer: String) {
        var state = Message("capabilities")
        state.clipboard = clipboardEnabled && selected?.id == peer
        state.clipboardImages = state.clipboard
        state.files = filesEnabled
        state.notifications = notificationsEnabled
        state.gallery = galleryEnabled && selected?.id == peer
        server?.send(state, to: peer)
    }

    private func updateGallery() {
        let peer = canBrowseGallery ? selected?.id : nil
        let capabilities = peer.flatMap { permissions[$0] }
        gallery.select(peer, advanced: (capabilities?.galleryRevision ?? 1) >= 2,
                       background: capabilities?.backgroundConnection == true)
    }

    private func updateClipboardImages() {
        let current = selected?.id
        let peer = current.flatMap { id in
            canClipboard(id) && permissions[id]?.clipboardImages == true ? id : nil
        }
        if clipboardImagePeer != peer {
            clipboardImages.reset()
            clipboardImagePeer = peer
        }
    }

    private func updateFilePermission(_ peer: String) {
        if filesEnabled && permissions[peer]?.files == true { files.allow(peer) }
        else { files.disconnect(peer) }
    }

    private func addEvent(_ title: String, _ icon: String) {
        events.insert(Event(title: title, icon: icon), at: 0)
        if events.count > 40 { events.removeLast() }
    }
}
