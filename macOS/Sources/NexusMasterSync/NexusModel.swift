import AppKit
import Combine
import Foundation
import NexusCore

enum Section: String, CaseIterable, Identifiable {
    case overview = "Celular"
    case conversation = "Conversa"
    case clipboard = "Área de transferência"
    case documents = "Documentos"
    case gallery = "Galeria"
    case files = "Arquivos"
    case notifications = "Notificações"
    case remote = "Controle remoto"
    case apps = "Apps"
    case calls = "Chamadas"
    case sms = "SMS e RCS"
    case webcam = "Webcam"
    case devices = "Dispositivos"
    case settings = "Configurações"

    var id: String { rawValue }

    /// Chamadas, SMS e Webcam have a place in the menu but no feature behind them yet.
    var isComingSoon: Bool { self == .calls || self == .sms || self == .webcam }

    var title: String {
        switch self {
        case .overview: "Visão geral"
        case .gallery: "Fotos"
        default: rawValue
        }
    }

    var subtitle: String {
        switch self {
        case .overview: "Tudo do seu celular, num só lugar"
        case .conversation: "Conversa e arquivos com o celular"
        case .clipboard: "O que você copia, nos dois aparelhos"
        case .documents: "Digitalizações do celular"
        case .gallery: "Fotos e vídeos do celular"
        case .files: "Enviados e recebidos"
        case .notifications: "Espelhadas em tempo real"
        case .remote: "Controle o celular pelo Mac"
        case .apps: "Abra os apps do celular no Mac"
        case .calls: "Atenda e ligue pelo Mac"
        case .sms: "Mensagens do celular no Mac"
        case .webcam: "A câmera do celular como webcam"
        case .devices: "Celulares conectados e pareamento"
        case .settings: "Aparência, atalhos e conexão"
        }
    }

    var icon: String {
        switch self {
        case .apps: "square.grid.2x2"
        case .calls: "phone"
        case .sms: "message"
        case .webcam: "video"
        case .overview: "iphone"
        case .conversation: "bubble.left.and.bubble.right"
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

    struct ChatEntry: Identifiable, Codable {
        let id: String
        let peer: String
        let text: String
        let outgoing: Bool
        let date: Date
        var confirmed: Bool
    }

    @Published private(set) var messages: [ChatEntry] = []
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
    @Published private(set) var keychainUnavailable = false
    @Published private(set) var temporaryNetwork = false
    @Published var invitation: Invitation?
    @Published private(set) var permissions: [String: Message] = [:]
    @Published var selectedID: String? {
        didSet {
            if oldValue != selectedID { screen.endAll(); screen.stopUSB() }
            advertiseCapabilities()
        }
    }
    @Published var clipboardEnabled: Bool {
        didSet { persist(clipboardEnabled, "clipboard"); advertiseCapabilities(); autoStartClipboardSync() }
    }
    @Published var historyEnabled: Bool {
        didSet { persist(historyEnabled, "history"); clipboard.recordHistory = historyEnabled }
    }
    @Published var filesEnabled: Bool { didSet { persist(filesEnabled, "files"); advertiseCapabilities() } }
    @Published var notificationsEnabled: Bool {
        didSet { persist(notificationsEnabled, "notifications"); updateNotifications(); advertiseCapabilities() }
    }
    @Published var hideNotices: Bool {
        didSet { persist(hideNotices, "hide-notices"); updateNotifications(); notifications.removeAll(); refreshNotices() }
    }
    @Published var quiet: Bool { didSet { persist(quiet, "quiet"); updateNotifications() } }
    @Published var blockedApps: Set<String> {
        didSet { preferences.set(Array(blockedApps), forKey: "blocked-apps"); updateNotifications(); notifications.removeAll(); refreshNotices() }
    }
    @Published var theme: String { didSet { preferences.set(theme, forKey: "theme") } }
    @Published var devicesShortcut: String { didSet { preferences.set(devicesShortcut, forKey: "shortcut-devices") } }
    @Published var filesShortcut: String { didSet { preferences.set(filesShortcut, forKey: "shortcut-files") } }
    @Published var galleryEnabled: Bool {
        didSet { persist(galleryEnabled, "gallery"); advertiseCapabilities() }
    }
    @Published var scanRequestFeedback: String?
    @Published var scanPasteEnabled = UserDefaults.standard.bool(forKey: "global-scan-paste") {
        didSet {
            preferences.set(scanPasteEnabled, forKey: "global-scan-paste")
            if scanPasteEnabled { registerScanPaste() }
            else {
                scanPasteShortcut.unregister()
                scanPasteRequest = nil
                scanPasteFeedback = nil
            }
        }
    }
    @Published private(set) var scanPasteFeedback: String?
    /// The global scan-and-paste shortcut; a combination macOS refuses keeps the previous one.
    @Published private(set) var scanShortcut: KeyCombo = UserDefaults.standard.data(forKey: "shortcut-scan")
        .flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) } ?? .scanDefault

    @discardableResult
    func setScanShortcut(_ combo: KeyCombo) -> Bool {
        let previous = scanShortcut
        scanShortcut = combo
        guard scanPasteEnabled else {
            preferences.set(try? JSONEncoder().encode(combo), forKey: "shortcut-scan")
            return true
        }
        if scanPasteShortcut.register(combo) {
            preferences.set(try? JSONEncoder().encode(combo), forKey: "shortcut-scan")
            scanPasteFeedback = nil
            return true
        }
        scanShortcut = previous
        _ = scanPasteShortcut.register(previous)
        scanPasteFeedback = "\(combo.label) está em uso por outro app. O atalho continua \(previous.label)."
        return false
    }
    private let scanPasteShortcut = ScanPasteShortcut()
    private var scanPasteRequest: (peer: String, id: String, target: ScanPasteShortcut.Target?)?
    @Published private(set) var cameraFeedback: String?
    @Published private(set) var latestInstantPhoto: ReceivedFile?
    @Published private(set) var cameraPending = false
    private var cameraRequest: (peer: String, id: String)?
    @Published var batteryAlertsEnabled = UserDefaults.standard.bool(forKey: "battery-alerts") {
        didSet {
            preferences.set(batteryAlertsEnabled, forKey: "battery-alerts")
            resetBatteryAlerts()
        }
    }
    @Published var lowBatteryLimit = UserDefaults.standard.object(forKey: "battery-low") as? Int ?? 20 {
        didSet {
            preferences.set(lowBatteryLimit, forKey: "battery-low")
            resetBatteryAlerts()
        }
    }
    @Published var chargedBatteryLimit = UserDefaults.standard.object(forKey: "battery-charged") as? Int ?? 80 {
        didSet {
            preferences.set(chargedBatteryLimit, forKey: "battery-charged")
            resetBatteryAlerts()
        }
    }
    @Published private(set) var batteryMessages: [String: String] = [:]
    private enum BatteryCondition { case normal, low, charged }
    private var batteryConditions: [String: BatteryCondition] = [:]

    @Published var actionFeedback: String?
    @Published private(set) var mediaStatuses: [String: Message] = [:]
    private var mediaReceivedAt: [String: Date] = [:]
    /// Covers by track key, and the keys already asked for, so each cover is requested once.
    @Published private(set) var mediaArt: [String: NSImage] = [:]
    private var pendingMediaArt: Set<String> = []
    private var mediaArtAttempts: [String: Int] = [:]
    private var mediaQueuePeer: String?
    @Published private(set) var mediaQueue: [MediaQueueItem] = []
    @Published private(set) var mediaQueueActive: Int64?

    let clipboard: ClipboardSync
    let adbClipboard = ADBClipboard()
    private let clipboardImages = ClipboardImages()
    private var clipboardImagePeer: String?
    let notifications = NotificationSync()
    let gallery = GalleryModel()
    let screen = ScreenMirror()
    let files: FileTransfers
    private var scanPopup: ScanPopupController?
    private let preferences = UserDefaults.standard
    private let shareService = AndroidShareService()
    private var presentingShareFailure = false
    private let shareInbox = ShareInbox.directory
    private var lastShareDestination: ShareInbox.Destination?
    private var publishedShareDestination = false
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
        if let saved = preferences.data(forKey: "chat-history"),
           let history = try? JSONDecoder().decode([ChatEntry].self, from: saved) {
            messages = history
        }
        clipboardEnabled = preferences.bool(forKey: "clipboard")
        historyEnabled = preferences.bool(forKey: "history")
        filesEnabled = preferences.bool(forKey: "files")
        notificationsEnabled = preferences.bool(forKey: "notifications")
        galleryEnabled = preferences.object(forKey: "gallery") as? Bool ?? true
        hideNotices = preferences.object(forKey: "hide-notices") as? Bool ?? true
        quiet = preferences.bool(forKey: "quiet")
        blockedApps = Set(preferences.stringArray(forKey: "blocked-apps") ?? [])
        theme = preferences.string(forKey: "theme") ?? "dark"
        devicesShortcut = preferences.string(forKey: "shortcut-devices") ?? "d"
        filesShortcut = preferences.string(forKey: "shortcut-files") ?? "f"
        relay.forward = { [weak self] in self?.server?.send($1, to: $0) }
        clipboard.recordHistory = historyEnabled
        adbClipboard.receive = { [weak self] event in self?.clipboard.receive(event) }
        adbClipboard.hostProvider = { [weak self] device in
            device.peerID.flatMap { self?.server?.host(of: $0) }
        }
        adbClipboard.onEnded = { [weak self] in
            self?.clipboardRetry.schedule(after: .seconds(15)) { [weak self] in self?.autoStartClipboardSync() }
        }
        screen.send = { [weak self] in self?.server?.send($1, to: $0) }
        gallery.send = { [weak self] in self?.server?.send($1, to: $0) }
        files.didReceive = { [weak self] file in
            self?.gallery.received(file)
            self?.receiveInstantPhoto(file)
            self?.receiveScanPaste(file)
        }
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
            self.drainShareInbox()
            if let invitation = self.invitation, Int64(time.timeIntervalSince1970) >= invitation.expiresAt {
                self.invitation = nil
                self.problem = "O QR expirou. Gere um novo código."
            }
        }
    }

    var selected: Peer? { peers.first { $0.id == selectedID } ?? peers.first(where: { online.contains($0.id) }) ?? peers.first }
    var active: Bool { selected.map { online.contains($0.id) } ?? false }
    /// True while the clipboard syncs, by the app's own channel or by ADB over Wi-Fi/USB.
    var clipboardSyncActive: Bool { clipboardEnabled || adbClipboard.transport != nil }

    /// The one switch for clipboard sync: turning it off also stops ADB sync; turning it on resumes Wi-Fi sync when a device is known.
    func setClipboardSync(_ on: Bool) {
        clipboardEnabled = on
        if !on {
            adbClipboard.stop()
        } else if let device = adbClipboard.wirelessDevice {
            adbClipboard.startWiFi(device: device)
        }
    }

    var selectedStatus: DeviceStatus? { selected.flatMap { deviceStatus[$0.id] } }
    var canSendFiles: Bool { selected.map { filesEnabled && online.contains($0.id) && permissions[$0.id]?.files == true } ?? false }
    var canPlayMedia: Bool { active && selected.map { permissions[$0.id]?.mediaControl == true } == true }
    var canFindPhone: Bool { active && selected.map { permissions[$0.id]?.findPhone == true } == true }
    var canMirror: Bool { active && selected.map { permissions[$0.id]?.mirror == true } == true }
    var canBrowseGallery: Bool { galleryEnabled && active && selected.map { permissions[$0.id]?.gallery == true } == true }
    var canRequestScan: Bool { selected.map { canSendFiles && permissions[$0.id]?.scanner == true } ?? false }

    func launch() {
        if scanPopup == nil { scanPopup = ScanPopupController(files: files) }
        if quitObserver == nil {
            quitObserver = NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification).sink { [weak self] _ in
                self?.clearShareDestination()
                self?.screen.endAll(wait: true)
                self?.screen.stopUSB()
                self?.adbClipboard.stop()
                self?.server?.stop()
            }
        }
        shareService.send = { [weak self] files, text in
            guard let self else { return "Abra o MasterSync e selecione um Android." }
            return self.sendSharedContent(files: files, text: text)
        }
        shareService.reportFailure = { [weak self] message in
            // Reply to Finder before presenting the alert in the MasterSync process.
            Task { @MainActor in self?.showShareFailure(message) }
        }
        NSApp.servicesProvider = shareService
        NSUpdateDynamicServices()
        notifications.activate()
        if scanPasteEnabled { registerScanPaste() }
        if preferences.bool(forKey: "network-consent") { enableNetwork() }
    }

    private var adbProofResponse: (peer: String, nonce: String)?

    func wirelessControlDevice(for peer: String?) -> ADBWirelessDevice? {
        guard let peer, let device = adbClipboard.wirelessDevice, device.peerID == peer else { return nil }
        return device
    }

    func configureWirelessControl(_ device: ADBWirelessDevice, pairing: ADBPairing?, peer: String) {
        adbClipboard.configureWireless(device, pairing: pairing, peer: peer) { [weak self] session, serial, peer in
            guard let self, self.online.contains(peer), self.permissions[peer]?.adbProof == true else {
                throw NexusError.transfer("Atualize o MasterSync no Android e mantenha o app conectado para verificar o aparelho.")
            }
            let nonce = Wire.id()
            var message = Message("adbProof")
            message.id = nonce
            self.server?.send(message, to: peer)
            for _ in 0..<30 {
                if self.adbProofResponse?.peer == peer, self.adbProofResponse?.nonce == nonce {
                    let matches = try await Task.detached { try session.verifyPeer(serial: serial, nonce: nonce) }.value
                    guard matches, self.online.contains(peer) else {
                        throw NexusError.transfer("O ADB não confirmou que este é o mesmo Android selecionado no MasterSync.")
                    }
                    return
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            throw NexusError.transfer("O MasterSync do Android não respondeu à verificação. Abra o app no celular e tente novamente.")
        }
    }

    func startTemporaryNetwork() {
        guard keychainUnavailable, server == nil else { return }
        enableNetwork(temporary: true)
    }

    func enableNetwork() { enableNetwork(temporary: temporaryNetwork) }

    private func enableNetwork(temporary: Bool) {
        guard !connecting, !serviceReady else { return }
        problem = nil
        keychainUnavailable = false
        otherCopyRunning = otherNexusCopy != nil
        if otherCopyRunning {
            networkProblem = "Outra cópia do Nexus está aberta. Encerre essa cópia com ⌘Q para ativar a rede aqui."
            return
        }
        networkProblem = nil
        connecting = true
        do {
            if server == nil {
                let server = try temporary ? LocalServer.temporary() : LocalServer()
                temporaryNetwork = temporary
                server.onUpdate = { [weak self] in self?.refresh() }
                server.onSession = { [weak self] peer in self?.resetSession(peer) }
                server.onMessage = { [weak self] peer, message in self?.receive(message, peer: peer) }
                self.server = server
            }
            if !temporaryNetwork { preferences.set(true, forKey: "network-consent") }
            server?.start()
            refresh()
        } catch NexusError.security(-60008) {
            connecting = false
            keychainUnavailable = true
            problem = "O macOS não autorizou o acesso à identidade de pareamento no Keychain."
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
            notifications.clearDnd(peer.id)
            if selectedID == peer.id { selectedID = nil }
            addEvent("\(peer.name) removido", "iphone.slash")
        } catch { problem = error.localizedDescription }
    }

    var canChat: Bool {
        active && selected.map { permissions[$0.id]?.chat == true } == true
    }

    @discardableResult
    func sendChat(_ draft: String) -> Bool {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canChat, let peer = selected?.id, !text.isEmpty, text.utf8.count <= 2048 else { return false }
        let id = Wire.id()
        saveMessage(ChatEntry(id: id, peer: peer, text: text, outgoing: true, date: .now, confirmed: false))
        var message = Message("chat")
        message.id = id
        message.text = text
        server?.send(message, to: peer)
        return true
    }

    private func saveMessage(_ entry: ChatEntry) {
        messages.append(entry)
        if messages.count > 400 { messages.removeFirst(messages.count - 400) }
        persistMessages()
    }

    private func persistMessages() {
        if let data = try? JSONEncoder().encode(messages) { preferences.set(data, forKey: "chat-history") }
    }

    private func receiveChat(_ message: Message, peer: String) {
        guard online.contains(peer), permissions[peer]?.chat == true,
              let id = message.id, Wire.validID(id) else { return }
        if message.type == "chatAck" {
            if let index = messages.firstIndex(where: { $0.peer == peer && $0.id == id && $0.outgoing }) {
                messages[index].confirmed = true
                persistMessages()
            }
        } else if let text = message.text, !text.isEmpty, text.utf8.count <= 2048 {
            if !messages.contains(where: { $0.peer == peer && $0.id == id }) {
                saveMessage(ChatEntry(id: id, peer: peer, text: text, outgoing: false, date: .now, confirmed: true))
            }
            var reply = Message("chatAck")
            reply.id = id
            server?.send(reply, to: peer)
        }
    }

    func sendFile(_ url: URL) {
        guard let peer = selected else { return }
        files.offer(url, to: peer.id)
    }

    private func showShareFailure(_ message: String) {
        guard !presentingShareFailure else { return }
        presentingShareFailure = true
        defer { presentingShareFailure = false }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Não foi possível enviar ao Android"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func sendSharedContent(files urls: [URL], text: String?) -> String? {
        guard let selected else { return "Pareie um celular em Celular → Conectar Android antes de enviar." }
        guard active else {
            return "\(selected.name) está desconectado. Abra o MasterSync no Android e conecte-o na mesma rede Wi-Fi."
        }
        let peer = selected.id
        let message = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !urls.isEmpty, !canSendFiles { return "Ative Arquivos nos dois aparelhos para enviar." }
        if !message.isEmpty && (!canChat || message.utf8.count > 2048) {
            return "Para enviar este texto, ative a Conversa e use até 2.048 bytes."
        }
        guard !urls.isEmpty || !message.isEmpty else { return "Selecione um arquivo, link ou texto para enviar." }
        if !urls.isEmpty, !files.offerBatch(urls, to: peer) { return "Não foi possível colocar o arquivo na fila." }
        if !message.isEmpty, !sendChat(message) { return "Não foi possível enviar o texto." }
        return nil
    }

    private func clearShareDestination() {
        if let shareInbox {
            try? FileManager.default.removeItem(at: shareInbox.appendingPathComponent("destination.json"))
        }
    }

    private func drainShareInbox() {
        guard let shareInbox else { return }
        let manager = FileManager.default
        let destination = active && (canChat || canSendFiles) ? selected.map {
            ShareInbox.Destination(peer: $0.id, name: $0.name)
        } : nil
        if !publishedShareDestination || lastShareDestination != destination {
            do {
                if let destination {
                    try manager.createDirectory(at: shareInbox, withIntermediateDirectories: true)
                    try JSONEncoder().encode(destination)
                        .write(to: shareInbox.appendingPathComponent("destination.json"), options: .atomic)
                } else { clearShareDestination() }
                lastShareDestination = destination
                publishedShareDestination = true
            } catch { return }
        }
        guard let destination else { return }
        for pending in ShareInbox.children(of: shareInbox) where UUID(uuidString: pending.lastPathComponent) != nil {
            guard let data = try? Data(contentsOf: pending.appendingPathComponent("request.json")),
                  let request = try? JSONDecoder().decode(ShareInbox.Request.self, from: data),
                  request.peer == destination.peer, request.text.count <= 11 else { continue }
            let message = request.text.joined(separator: "\n")
            let urls = ShareInbox.items(in: pending)
            guard (urls.isEmpty || canSendFiles), (message.isEmpty || canChat) else { continue }
            if message.utf8.count > 2048 {
                try? manager.removeItem(at: pending)
                problem = "O texto compartilhado excede o tamanho máximo da Conversa."
                continue
            }
            do {
                if urls.isEmpty {
                    if sendSharedContent(files: [], text: message) == nil { try manager.removeItem(at: pending) }
                } else {
                    let support = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
                    let outbox = support.appendingPathComponent("Nexus masterSync/Shared Files", isDirectory: true)
                    try manager.createDirectory(at: outbox, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
                    let retained = outbox.appendingPathComponent(pending.lastPathComponent)
                    // Keep the payload available for queued delivery and opening sent attachments in the conversation.
                    try manager.moveItem(at: pending, to: retained)
                    if let error = sendSharedContent(files: ShareInbox.items(in: retained), text: message) {
                        try manager.moveItem(at: retained, to: pending)
                        problem = error
                    }
                }
            } catch { problem = error.localizedDescription }
        }
    }

    func sendDroppedFiles(_ urls: [URL]) -> Bool {
        guard canSendFiles, let peer = selected?.id, files.offerBatch(urls, to: peer) else { return false }
        section = .conversation
        return true
    }

    func findPhone() {
        if canFindPhone, let peer = selected { server?.send(Message("ringPhone"), to: peer.id) }
    }

    var currentMedia: Message? {
        guard canPlayMedia, let peer = selected?.id else { return nil }
        return mediaStatuses[peer]
    }

    func refreshMedia() {
        if canPlayMedia, let peer = selected { server?.send(Message("mediaStatusRequest"), to: peer.id) }
    }

    func mediaControl(_ command: String) {
        guard canPlayMedia, let peer = selected else { return }
        server?.send(MediaCommands.command(command), to: peer.id)
    }

    /// The selected phone's media state, or nil when nothing is playing there.
    var currentMediaState: MediaPlayerState? {
        guard let message = currentMedia, let peer = selected?.id else { return nil }
        let state = MediaPlayerState(message: message, receivedAt: mediaReceivedAt[peer] ?? .now)
        return state.isEmpty ? nil : state
    }

    func mediaSeek(toFraction fraction: Double) {
        guard canPlayMedia, let peer = selected, let state = currentMediaState, state.canSeek,
              let duration = state.durationMs else { return }
        server?.send(MediaCommands.command("seek", positionMs: MediaPlayerState.seekTarget(fraction: fraction, durationMs: duration)),
                     to: peer.id)
    }

    func mediaLike(_ on: Bool) {
        guard canPlayMedia, let peer = selected, currentMediaState?.canLike == true else { return }
        server?.send(MediaCommands.command(on ? "like" : "unlike"), to: peer.id)
    }

    func mediaQueueRefresh() {
        guard canPlayMedia, let peer = selected, currentMediaState?.hasQueue == true else { return }
        // Never show a previous list (or another phone's) while the new one is on its way.
        mediaQueue = []
        mediaQueueActive = nil
        mediaQueuePeer = nil
        server?.send(Message("mediaQueueRequest"), to: peer.id)
    }

    func mediaPlay(queueItem item: MediaQueueItem) {
        guard canPlayMedia, let peer = selected,
              MediaCommands.queueBelongs(queuePeer: mediaQueuePeer, selected: peer.id) else { return }
        server?.send(MediaCommands.command("queueItem", queueId: item.id), to: peer.id)
    }

    private func requestMediaArtIfNeeded(for message: Message, peer: String) {
        let key = MediaPlayerState(message: message, receivedAt: .now).artKey
        guard MediaCommands.shouldRequestArt(key: key, cached: Set(mediaArt.keys), pending: pendingMediaArt,
                                             attempts: mediaArtAttempts[key ?? ""] ?? 0), let key else { return }
        pendingMediaArt.insert(key)
        mediaArtAttempts[key, default: 0] += 1
        var request = Message("mediaArtRequest")
        request.artKey = key
        server?.send(request, to: peer)
    }

    @Published private(set) var launcherLists: [String: [AndroidApp]] = [:]
    /// Icons of pinned Android apps, by component, kept across launches.
    @Published private(set) var launcherIcons: [String: NSImage] = NexusModel.loadLauncherIcons()
    private var requestedIcons: Set<String> = []
    private var lastIconRequest: (pins: [String], components: [String])?

    nonisolated static let maxIconRequest = 24

    /// Valid pinned components without a cached icon, in pin order, without repeats, at most 24.
    nonisolated static func missingIcons(pins: [String], cached: Set<String>) -> [String] {
        var seen = Set<String>()
        return pins.filter { pin in
            AndroidApp(component: pin, label: "").validComponent && !cached.contains(pin) && seen.insert(pin).inserted
        }.prefix(maxIconRequest).map { $0 }
    }

    /// Icon bytes only when they are small and decode as an image.
    nonisolated static func acceptedIcon(_ base64: String) -> Data? {
        guard base64.utf8.count <= 96 * 1024, let data = Data(base64Encoded: base64), data.count <= 64 * 1024,
              NSImage(data: data)?.isValid == true else { return nil }
        return data
    }

    private static func loadLauncherIcons() -> [String: NSImage] {
        guard let stored = UserDefaults.standard.data(forKey: "launcher-icons"),
              let decoded = try? JSONDecoder().decode([String: Data].self, from: stored) else { return [:] }
        return decoded.compactMapValues { NSImage(data: $0) }
    }

    func requestLauncherIcons(for pins: [String]) {
        // Wait for the app list: icons are only accepted for components it contains.
        guard launcherAvailable, let peer = selected?.id, let apps = launcherLists[peer] else { return }
        let listed = Set(apps.map(\.id))
        let missing = Self.missingIcons(pins: pins.filter(listed.contains), cached: Set(launcherIcons.keys).union(requestedIcons))
        guard !missing.isEmpty else { return }
        requestedIcons.formUnion(missing)
        lastIconRequest = (pins, missing)
        var message = Message("launcherIconsRequest")
        message.components = missing
        server?.send(message, to: peer)
    }

    private func receiveLauncherIcons(_ icons: [AndroidAppIcon], peer: String, message: Message) {
        let known = Set((launcherLists[peer] ?? []).map(\.id))
        var stored = (UserDefaults.standard.data(forKey: "launcher-icons"))
            .flatMap { try? JSONDecoder().decode([String: Data].self, from: $0) } ?? [:]
        for icon in icons.prefix(Self.maxIconRequest) where known.contains(icon.component) {
            guard let data = Self.acceptedIcon(icon.data), let image = NSImage(data: data) else { continue }
            launcherIcons[icon.component] = image
            stored[icon.component] = data
        }
        UserDefaults.standard.set(try? JSONEncoder().encode(stored), forKey: "launcher-icons")
        // Android stops before the frame limit and says so; ask again for the ones it left out.
        if message.more == true, !icons.isEmpty, let last = lastIconRequest {
            let answered = Set(icons.map(\.component))
            requestedIcons.subtract(last.components.filter { !answered.contains($0) })
            requestLauncherIcons(for: last.pins)
        }
    }

    var launcherAvailable: Bool {
        active && selected.map { permissions[$0.id]?.launcher == true } == true
    }

    func refreshLauncher() {
        guard launcherAvailable, let peer = selected?.id else { return }
        server?.send(Message("launcherAppsRequest"), to: peer)
    }

    func launchAndroidApp(_ app: AndroidApp) {
        guard canMirror || screen.inAppAvailable, let peer = selected?.id, let target = wirelessControlDevice(for: peer),
              launcherLists[peer]?.contains(where: { $0.id == app.id }) == true else { return }
        switch ScreenMirror.controlRoute(hasWirelessADB: true, scrcpyInstalled: screen.scrcpyInstalled,
                                         inAppAvailable: screen.inAppAvailable) {
        case .inApp: screen.openAppWithInAppControl(app, wireless: target)
        case .scrcpy: screen.openAppWithScrcpy(app, wireless: target)
        case .mirror: screen.beginControl(peer, wireless: target, open: app)
        }
    }

    func requestMirror() {
        if canMirror, let peer = selected { screen.begin(peer.id) }
    }

    var canRequestPhoto: Bool {
        canSendFiles && selected.map { permissions[$0.id]?.instantCamera == true } == true
    }

    func requestInstantPhoto() {
        guard canRequestPhoto, !cameraPending, let peer = selected?.id else { return }
        let id = Wire.id()
        cameraRequest = (peer, id)
        cameraPending = true
        cameraFeedback = "Abra o MasterSync e confirme a câmera no Android."
        var message = Message("cameraRequest")
        message.id = id
        server?.send(message, to: peer)
        Task {
            try? await Task.sleep(for: .seconds(120))
            if cameraRequest?.id == id {
                cameraPending = false
                cameraFeedback = "A foto ainda não chegou. Você pode solicitar outra."
            }
        }
    }

    private func receiveInstantPhoto(_ file: ReceivedFile) {
        guard file.peerID == cameraRequest?.peer, file.offer.id == cameraRequest?.id,
              file.offer.mime == "image/jpeg" else { return }
        cameraRequest = nil
        cameraPending = false
        cameraFeedback = "Foto salva no Mac."
        latestInstantPhoto = file
    }

    private func registerScanPaste() {
        scanPasteShortcut.action = { [weak self] in self?.requestScanPaste() }
        if !scanPasteShortcut.register(scanShortcut) {
            scanPasteFeedback = "O atalho \(scanShortcut.label) está em uso por outro app. Escolha outro em Atalhos."
        }
    }

    func requestScanPaste() {
        guard scanPasteEnabled, scanPasteRequest == nil else { return }
        guard canRequestScan, let peer = selected?.id, permissions[peer]?.scanPaste == true else {
            scanPasteFeedback = "Para usar o atalho, atualize o Android e autorize a digitalização e os arquivos."
            return
        }
        let id = Wire.id()
        scanPasteRequest = (peer, id, ScanPasteShortcut.Target())
        scanPasteFeedback = "Confirme a digitalização no Android."
        var message = Message("scanRequest")
        message.id = id
        server?.send(message, to: peer)
        openScanCameraOverADB(peer: peer, id: id) { [weak self] opened in
            if opened, self?.scanPasteRequest?.id == id { self?.scanPasteFeedback = "Abrindo a câmera no Android…" }
        }
        Task {
            try? await Task.sleep(for: .seconds(180))
            if scanPasteRequest?.id == id {
                scanPasteRequest = nil
                scanPasteFeedback = "O atalho expirou. A digitalização ainda pode chegar em Documentos."
            }
        }
    }

    private func receiveScanPaste(_ file: ReceivedFile) {
        guard let request = scanPasteRequest, request.peer == file.peerID, request.id == file.offer.id,
              file.offer.isScanPage else { return }
        scanPasteRequest = nil
        Task {
            let bytes = await Task.detached(priority: .utility) {
                guard file.offer.size <= 64 * 1024 * 1024 else { return nil as Data? }
                return try? Data(contentsOf: file.url)
            }.value
            guard scanPasteEnabled, let bytes, clipboard.applyImage(bytes, mime: "image/jpeg") else {
                if scanPasteEnabled { scanPasteFeedback = "A imagem está em Documentos, mas não foi possível copiá-la." }
                return
            }
            if request.target?.pasteIfStillFocused() == true {
                scanPasteFeedback = "Imagem copiada e enviada ao campo original."
            } else {
                scanPasteFeedback = "Imagem copiada. Use Command + V no campo desejado."
            }
        }
    }

    func requestScan() {
        guard let peer = selected, canRequestScan else { return }
        var message = Message("scanRequest")
        message.id = Wire.id()
        server?.send(message, to: peer.id)
        scanRequestFeedback = "Solicitação enviada. Confirme a abertura do scanner no celular."
        if let id = message.id {
            openScanCameraOverADB(peer: peer.id, id: id) { [weak self] opened in
                if opened { self?.scanRequestFeedback = "Abrindo a câmera no Android…" }
            }
        }
    }

    /// With ADB over Wi-Fi, opens the camera on the phone directly instead of waiting for a tap there.
    private func openScanCameraOverADB(peer: String, id: String, done: @escaping (Bool) -> Void) {
        guard let device = wirelessControlDevice(for: peer), let adb = ADBClipboard.adbExecutable else { return }
        Task {
            let opened = await Task.detached {
                let session = ADBClipboardSession(adb: adb)
                guard let serial = try? await session.wirelessSerial(for: device) else { return false }
                return (try? session.openScanCamera(serial: serial, requestID: id)) != nil
            }.value
            done(opened)
        }
    }

    private func persist(_ value: Bool, _ key: String) { preferences.set(value, forKey: key) }

    private func updateNotifications() {
        notifications.enabled = notificationsEnabled
        notifications.hideContent = hideNotices
        notifications.quiet = quiet
        notifications.blocked = blockedApps
        if !notificationsEnabled { notifications.removeAll() }
    }

    private func resetBatteryAlerts() {
        batteryConditions.removeAll()
        batteryMessages.removeAll()
        evaluateBatteryAlerts()
    }

    private func evaluateBatteryAlerts() {
        guard batteryAlertsEnabled else { return }
        for peer in peers where online.contains(peer.id) {
            guard let status = deviceStatus[peer.id], let percent = status.battery else { continue }
            let condition: BatteryCondition
            if status.charging {
                condition = percent >= chargedBatteryLimit ? .charged : .normal
            } else {
                condition = percent <= lowBatteryLimit ? .low : .normal
            }
            // Repeated packets and reconnection with the same battery state share the same alert.
            guard batteryConditions[peer.id] != condition else { continue }
            batteryConditions[peer.id] = condition
            guard condition != .normal else {
                batteryMessages[peer.id] = nil
                continue
            }
            let title = condition == .low ? "Bateria baixa" : "Limite de carga atingido"
            let detail = "\(peer.name) está com \(percent)% de bateria."
            batteryMessages[peer.id] = "\(title) · \(percent)%"
            notifications.postBatteryAlert(title: title, detail: detail, peer: peer.id)
        }
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
        evaluateBatteryAlerts()
        for id in disconnected {
            permissions[id] = nil
            mediaStatuses[id] = nil
            mediaReceivedAt[id] = nil
            if id == selected?.id {
                mediaQueue = []
                mediaQueueActive = nil
                mediaQueuePeer = nil
                pendingMediaArt = []
                mediaArtAttempts = [:]
            }
            screen.disconnect(id)
            files.disconnect(id)
            notifications.removePeer(id)
            notifications.clearDnd(id)
            if let peer = peers.first(where: { $0.id == id }) { addEvent("\(peer.name) desconectado", "wifi.slash") }
        }
        for id in newlyOnline {
            if let peer = peers.first(where: { $0.id == id }) { addEvent("\(peer.name) conectado", "wifi") }
        }
        advertiseCapabilities()
    }

    /// Starts Android → Mac clipboard sync over Wi-Fi ADB by itself, so copies arrive with any keyboard and app.
    func autoStartClipboardSync() {
        let connected = active ? selected?.id : nil
        guard ADBClipboard.shouldAutoStart(clipboardEnabled: clipboardEnabled, device: adbClipboard.wirelessDevice,
                                           connectedPeer: connected, running: adbClipboard.transport != nil,
                                           paused: adbClipboard.paused),
              let device = adbClipboard.wirelessDevice else { return }
        clipboardRetry.cancel()
        adbClipboard.startWiFi(device: device)
    }
    private let clipboardRetry = SingleRetry()

    private func resetSession(_ peer: String) {
        permissions[peer] = nil
        notifications.removePeer(peer)
        notifications.clearDnd(peer)
        updateClipboardImages()
        screen.disconnect(peer)
        updateGallery()
        files.disconnect(peer)
        sendCapabilities(peer)
    }

    private func receive(_ message: Message, peer: String) {
        switch message.type {
        case "capabilities":
            let shouldRefresh = message.noticeSync == true &&
                (permissions[peer]?.noticeSync != true ||
                    (message.notifications == true && permissions[peer]?.notifications != true))
            permissions[peer] = message
            autoStartClipboardSync()
            if shouldRefresh { server?.send(Message("noticeRefresh"), to: peer) }
            updateClipboardImages()
            if message.notifications != true { notifications.removePeer(peer) }
            if message.noticeSync != true { notifications.clearDnd(peer) }
            updateFilePermission(peer)
            updateGallery()
        case "launcherApps":
            if permissions[peer]?.launcher == true, let apps = message.launcherApps {
                var seen = Set<String>()
                launcherLists[peer] = apps.prefix(200).filter { $0.validComponent && seen.insert($0.id).inserted }
                    .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
            }
        case "launcherIcons":
            if permissions[peer]?.launcher == true, let icons = message.launcherIcons {
                receiveLauncherIcons(icons, peer: peer, message: message)
            }
        case "adbProofReady":
            if online.contains(peer), let nonce = message.id, Wire.validID(nonce) {
                adbProofResponse = (peer, nonce)
            }
        case "chat", "chatAck": receiveChat(message, peer: peer)
        case "clipboard":
            guard canClipboard(peer), message.sensitive != true else { return }
            clipboardImages.cancelIncoming()
            clipboard.receive(message)
            addEvent("Texto recebido", "document.on.clipboard")
        case let type where type.hasPrefix("clipboardImage"):
            if peer == clipboardImagePeer && canClipboard(peer) && message.sensitive != true {
                clipboardImages.receive(message)
            }
        case "deviceControlsState":
            if permissions[peer]?.deviceControls == true { deviceControlStates[peer] = message }
        case "dndState":
            if permissions[peer]?.noticeSync == true { notifications.handle(message, peer: peer) }
        case "notice", "noticeRemoved", "noticeSnapshot", "noticeDismissFailed":
            if permissions[peer]?.notifications == true { notifications.handle(message, peer: peer) }
        case "mediaStatus":
            if permissions[peer]?.mediaControl == true {
                mediaStatuses[peer] = message
                mediaReceivedAt[peer] = .now
                requestMediaArtIfNeeded(for: message, peer: peer)
            }
        case "mediaArt":
            if permissions[peer]?.mediaControl == true, let key = message.artKey {
                let current = currentMedia.flatMap { MediaPlayerState(message: $0, receivedAt: .now).artKey }
                pendingMediaArt.remove(key)
                if let data = MediaCommands.acceptsArt(key: key, currentKey: current, data: message.data ?? ""),
                   let image = NSImage(data: data) {
                    if mediaArt.count >= 20 { mediaArt.removeAll() }
                    mediaArt[key] = image
                    mediaArtAttempts[key] = nil
                }
            }
        case "mediaQueue":
            if permissions[peer]?.mediaControl == true, peer == selected?.id {
                mediaQueue = Array((message.queue ?? []).prefix(30))
                mediaQueueActive = message.queueId
                mediaQueuePeer = peer
            }
        case "actionStatus":
            actionFeedback = Wire.visible(message.message ?? "", limit: 130)
        case "cameraStatus":
            if peer == cameraRequest?.peer, message.id == cameraRequest?.id {
                cameraFeedback = Wire.visible(message.message ?? "", limit: 140)
                if message.more != true {
                    cameraRequest = nil
                    cameraPending = false
                }
            }
        case "scanStatus":
            if peer == scanPasteRequest?.peer, message.id == scanPasteRequest?.id {
                scanPasteFeedback = Wire.visible(message.message ?? "", limit: 130)
                if message.more != true { scanPasteRequest = nil }
                return
            }
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

    var androidDnd: Message? { selected.flatMap { notifications.dnd[$0.id] } }

    // MARK: Quick controls (torch, ringer, lock, hotspot)

    @Published private(set) var deviceControlStates: [String: Message] = [:]

    var deviceControlsAvailable: Bool { selected.map { permissions[$0.id]?.deviceControls == true } ?? false }

    var quickControlInputs: QuickControls.Inputs {
        let peer = selected?.id ?? ""
        let state = deviceControlStates[peer]
        return QuickControls.Inputs(
            phoneName: selected?.name ?? "", online: active, dndAllowed: androidDnd?.dndAllowed, dndEnabled: androidDnd?.dndEnabled == true,
            canFind: canFindPhone, controlsAvailable: deviceControlsAvailable, torch: state?.torch, torchAvailable: state?.torchAvailable,
            ringer: state?.ringer, hasADB: wirelessControlDevice(for: selected?.id) != nil && ADBClipboard.adbExecutable != nil)
    }

    func refreshDeviceControls() {
        if deviceControlsAvailable, let peer = selected { server?.send(Message("deviceControlsRequest"), to: peer.id) }
    }

    private func sendDeviceControl(_ control: String, enabled: Bool) {
        guard deviceControlsAvailable, let peer = selected else { return }
        var message = Message("deviceControl")
        message.control = control
        message.enabled = enabled
        server?.send(message, to: peer.id)
    }

    /// Runs one ADB shell action on the selected phone over Wi-Fi and reports a failure the way other actions do.
    private func runOnPhone(_ action: @escaping @Sendable (ADBClipboardSession, String) throws -> Void) {
        guard let device = wirelessControlDevice(for: selected?.id), let adb = ADBClipboard.adbExecutable else {
            actionFeedback = "Configure o controle por Wi-Fi para usar este botão."
            return
        }
        Task {
            do {
                try await Task.detached {
                    let session = ADBClipboardSession(adb: adb)
                    let serial = try await session.wirelessSerial(for: device)
                    try action(session, serial)
                }.value
            } catch {
                actionFeedback = error.localizedDescription
            }
        }
    }

    func pressQuickControl(_ kind: QuickControl.Kind) {
        let inputs = quickControlInputs
        switch kind {
        case .dnd: setAndroidDnd(!inputs.dndEnabled)
        case .ringer: sendDeviceControl("ringer", enabled: inputs.ringer != "silent")
        case .find: findPhone()
        case .torch: sendDeviceControl("torch", enabled: inputs.torch != true)
        case .lock: runOnPhone { session, serial in try session.lockScreen(serial: serial) }
        case .hotspot: runOnPhone { session, serial in try session.openHotspotSettings(serial: serial) }
        }
    }

    func setAndroidDnd(_ enabled: Bool) {
        guard let peer = selected?.id, online.contains(peer), androidDnd?.dndAllowed == true else { return }
        var message = Message("dndSet")
        message.dndEnabled = enabled
        server?.send(message, to: peer)
    }

    func refreshNotices() {
        for peer in online where permissions[peer]?.noticeSync == true {
            server?.send(Message("noticeRefresh"), to: peer)
        }
    }

    var canRefreshNotices: Bool {
        active && selected.flatMap { permissions[$0.id]?.noticeSync } == true
    }

    private func sendCapabilities(_ peer: String) {
        var state = Message("capabilities")
        state.clipboard = clipboardEnabled && selected?.id == peer
        state.clipboardImages = state.clipboard
        state.chat = true
        state.files = filesEnabled
        state.notifications = notificationsEnabled
        state.noticeSync = true
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
