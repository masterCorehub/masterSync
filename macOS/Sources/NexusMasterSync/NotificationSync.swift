import AppKit
import Foundation
import NexusCore
import UserNotifications

@MainActor
final class NotificationSync: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    struct Notice: Identifiable {
        let id: String
        let peer: String
        let remoteID: String
        let app: String
        let group: String
        let title: String
        let body: String
        let date: Date
        let canReply: Bool
        let canDismiss: Bool
        let icon: NSImage?
    }

    private struct Snapshot {
        let id: String
        var nextOffset: Int64 = 0
        var entries: [String: Notice] = [:]
    }

    private var snapshots: [String: Snapshot] = [:]
    /// Fixed (non-clearable) notices hidden on this Mac, by notice id, with the content they had when hidden.
    private var hidden: [String: String] = [:]
    @Published private(set) var dnd: [String: Message] = [:]
    @Published private(set) var dismissErrors: [String: String] = [:]
    @Published private(set) var notices: [Notice] = []
    @Published private(set) var apps: [String: String] = [:]
    @Published private(set) var authorization: String?
    var enabled = false
    var hideContent = true
    var quiet = false
    var blocked: Set<String> = []
    var send: ((String, Message) -> Void)?
    private lazy var center: UNUserNotificationCenter? = Bundle.main.bundleURL.pathExtension == "app" ? .current() : nil

    func activate() {
        guard let center else { return }
        center.delegate = self
        let reply = UNTextInputNotificationAction(identifier: "reply", title: "Responder")
        let dismiss = UNNotificationAction(identifier: "dismiss", title: "Dispensar no Android")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "nexus.reply", actions: [reply, dismiss],
                                   intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: "nexus.notice", actions: [dismiss],
                                   intentIdentifiers: [], options: [])
        ])
    }

    func askPermission() {
        guard let center else {
            authorization = "Abra o aplicativo empacotado para ativar a Central de Notificações."
            return
        }
        Task {
            do {
                let allowed = try await center.requestAuthorization(options: [.alert, .badge])
                authorization = allowed ? "Central de Notificações autorizada." : "Autorize o Nexus nos Ajustes do Sistema."
            } catch { authorization = error.localizedDescription }
        }
    }

    func postBatteryAlert(title: String, detail: String, peer: String) {
        guard !quiet, let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = detail
        content.threadIdentifier = "mastersync.battery"
        center.add(UNNotificationRequest(identifier: "battery." + peer, content: content, trigger: nil))
    }

    func handle(_ message: Message, peer: String) {
        if message.type == "dndState" {
            dnd[peer] = message
            return
        }
        guard enabled else { return }
        if message.type == "noticeSnapshot" {
            applySnapshot(message, peer: peer)
            return
        }
        guard let remote = message.id, remote.utf8.count <= 128 else { return }
        let id = peer + "." + remote
        if message.type == "noticeRemoved" {
            hidden[id] = nil
            remove(id)
            return
        }
        if message.type == "noticeDismissFailed" {
            dismissErrors[peer] = Wire.visible(message.message ?? "O Android manteve essa notificação ativa.")
            return
        }
        guard let entry = makeEntry(message, peer: peer) else { return }
        announceCode(message, entry: entry)
        if let signature = hidden[id] {
            if signature == Self.signature(entry) || Self.isPlaceholder(entry) { return }
            // Hidden while Android redacted it: the first real content is what the user hid.
            if signature == Self.placeholderSignature {
                hidden[id] = Self.signature(entry)
                return
            }
            hidden[id] = nil
        }
        let change = notices.first(where: { $0.id == id }).map {
            $0.title != entry.title || $0.body != entry.body
        } ?? true
        notices.removeAll { $0.id == id }
        notices.append(entry)
        notices.sort(by: newestFirst)
        guard !quiet, change, let center else { return }
        let content = UNMutableNotificationContent()
        content.title = entry.app
        content.subtitle = entry.title
        content.body = entry.body
        content.threadIdentifier = entry.group
        content.categoryIdentifier = entry.canReply ? "nexus.reply" : (entry.canDismiss ? "nexus.notice" : "")
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    /// Called with a verification code (digits) and the app it came from, once per notice.
    var didFindCode: ((String, String) -> Void)?
    private var codeTracker = OtpCode.Tracker()

    /// The phone sends the code on its own when it hides the text (locked phone); otherwise it is read from the text.
    private func announceCode(_ message: Message, entry: Notice) {
        let sent = message.code.flatMap { OtpCode.isValid($0) ? $0 : nil }
        let text = [message.name, message.text].compactMap { $0 }.joined(separator: " ")
        guard message.type == "notice", let code = sent ?? OtpCode.find(in: text), OtpCode.isFresh(entry.date),
              codeTracker.shouldHandle(id: entry.id, code: code) else { return }
        didFindCode?(code, entry.app)
    }

    private func makeEntry(_ message: Message, peer: String) -> Notice? {
        guard message.type == "notice", let remote = message.id, remote.utf8.count <= 128,
              let app = message.app, let group = message.group else { return nil }
        let label = Wire.visible(app)
        if apps[group] != label { apps[group] = label }
        guard !blocked.contains(group) else { return nil }
        return Notice(id: peer + "." + remote, peer: peer, remoteID: remote, app: label,
                      group: Wire.visible(group),
                      title: hideContent ? "Notificação recebida" : Wire.visible(message.name ?? app, limit: 120),
                      body: hideContent ? "" : Wire.visible(message.text ?? "", limit: 600),
                      date: message.at.map { Date(timeIntervalSince1970: Double($0) / 1000) } ?? .now,
                      canReply: message.canReply == true && !hideContent, canDismiss: message.canDismiss != false,
                      icon: message.data.flatMap { GalleryModel.image($0, size: 36) })
    }

    private func applySnapshot(_ message: Message, peer: String) {
        guard let id = message.id, Wire.validID(id), let offset = message.offset,
              let batch = message.notices, batch.count <= 12 else { return }
        // An incomplete snapshot stays offscreen until all ordered batches arrive.
        if offset == 0 { snapshots[peer] = Snapshot(id: id) }
        guard var snapshot = snapshots.removeValue(forKey: peer),
              snapshot.id == id, snapshot.nextOffset == offset else { return }
        for item in batch {
            if let entry = makeEntry(item, peer: peer) { snapshot.entries[entry.id] = entry }
        }
        if message.more == true {
            snapshot.nextOffset += 1
            snapshots[peer] = snapshot
            return
        }

        for (id, signature) in hidden where id.hasPrefix(peer + ".") {
            if let entry = snapshot.entries[id], Self.signature(entry) == signature || Self.isPlaceholder(entry)
                || signature == Self.placeholderSignature {
                if signature == Self.placeholderSignature, !Self.isPlaceholder(entry) { hidden[id] = Self.signature(entry) }
                snapshot.entries[id] = nil
            } else {
                hidden[id] = nil
            }
        }
        let removed = notices.filter { $0.peer == peer && snapshot.entries[$0.id] == nil }.map(\.id)
        center?.removeDeliveredNotifications(withIdentifiers: removed)
        notices = (notices.filter { $0.peer != peer } + Array(snapshot.entries.values)).sorted(by: newestFirst)
    }

    private func newestFirst(_ lhs: Notice, _ rhs: Notice) -> Bool {
        lhs.date == rhs.date ? lhs.id < rhs.id : lhs.date > rhs.date
    }

    func clearDnd(_ peer: String) { dnd[peer] = nil }

    func dismiss(_ entry: Notice) {
        guard entry.canDismiss else { return }
        dismissErrors[entry.peer] = nil
        var message = Message("noticeDismiss")
        message.id = entry.remoteID
        send?(entry.peer, message)
    }

    /// Hides a notice on this Mac only. It comes back if its content changes, and is forgotten when Android removes it.
    func hide(_ entry: Notice) {
        hidden[entry.id] = Self.signature(entry)
        remove(entry.id)
    }

    /// Removes one notice: dismissed on Android when it allows, otherwise hidden on this Mac only.
    func discard(_ entry: Notice) {
        if entry.canDismiss { dismiss(entry) } else { hide(entry) }
    }

    /// Dismisses on Android every notice it allows, and hides the fixed ones on this Mac.
    func clearAll(peer: String) {
        for entry in notices where entry.peer == peer {
            if entry.canDismiss { dismiss(entry) } else { hide(entry) }
        }
    }

    private static func signature(_ entry: Notice) -> String { entry.title + "\u{0}" + entry.body }

    /// Android redacts content while the phone is locked; a redacted repost says nothing about a change.
    private static func isPlaceholder(_ entry: Notice) -> Bool { entry.title == "Notificação recebida" && entry.body.isEmpty }
    private static let placeholderSignature = "Notificação recebida\u{0}"

    func reply(to entry: Notice, text: String) {
        guard entry.canReply, !text.isEmpty, text.utf8.count <= 1024 else { return }
        var message = Message("noticeReply")
        message.id = entry.remoteID
        message.text = text
        send?(entry.peer, message)
    }

    func removeAll() {
        snapshots.removeAll()
        hidden.removeAll()
        dismissErrors.removeAll()
        center?.removeDeliveredNotifications(withIdentifiers: notices.map(\.id))
        notices.removeAll()
    }

    func removePeer(_ peer: String) {
        snapshots[peer] = nil
        dismissErrors[peer] = nil
        notices.filter { $0.peer == peer }.forEach { remove($0.id) }
    }

    private func remove(_ id: String) {
        center?.removeDeliveredNotifications(withIdentifiers: [id])
        notices.removeAll { $0.id == id }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.identifier
        let action = response.actionIdentifier
        let text = (response as? UNTextInputNotificationResponse)?.userText
        await MainActor.run {
            guard let entry = notices.first(where: { $0.id == id }) else { return }
            if action == "reply", let text { reply(to: entry, text: text) }
            if action == "dismiss" { dismiss(entry) }
        }
    }
}
