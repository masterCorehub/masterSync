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
        let icon: NSImage?
    }

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
                                   intentIdentifiers: [], options: [.customDismissAction]),
            UNNotificationCategory(identifier: "nexus.notice", actions: [dismiss],
                                   intentIdentifiers: [], options: [.customDismissAction])
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

    func handle(_ message: Message, peer: String) {
        guard enabled, let remote = message.id, remote.utf8.count <= 128 else { return }
        let id = peer + "." + remote
        if message.type == "noticeRemoved" {
            remove(id)
            return
        }
        guard message.type == "notice", let app = message.app, let group = message.group else { return }
        apps[group] = Wire.visible(app)
        guard !blocked.contains(group) else { return }
        let canReply = message.canReply == true && !hideContent
        let entry = Notice(id: id, peer: peer, remoteID: remote, app: Wire.visible(app), group: Wire.visible(group),
                           title: hideContent ? "Notificação recebida" : Wire.visible(message.name ?? app, limit: 120),
                           body: hideContent ? "" : Wire.visible(message.text ?? "", limit: 600),
                           date: message.at.map { Date(timeIntervalSince1970: Double($0) / 1000) } ?? .now,
                           canReply: canReply, icon: message.data.flatMap { GalleryModel.image($0, size: 36) })
        let change = notices.first(where: { $0.id == id }).map {
            $0.title != entry.title || $0.body != entry.body
        } ?? true
        notices.removeAll { $0.id == id }
        notices.insert(entry, at: 0)
        if notices.count > 100 { notices.removeLast() }
        guard !quiet, change, let center else { return }
        let content = UNMutableNotificationContent()
        content.title = entry.app
        content.subtitle = entry.title
        content.body = entry.body
        content.threadIdentifier = entry.group
        content.categoryIdentifier = canReply ? "nexus.reply" : "nexus.notice"
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    func dismiss(_ entry: Notice) {
        var message = Message("noticeDismiss")
        message.id = entry.remoteID
        send?(entry.peer, message)
        remove(entry.id)
    }

    func reply(to entry: Notice, text: String) {
        guard entry.canReply, !text.isEmpty, text.utf8.count <= 1024 else { return }
        var message = Message("noticeReply")
        message.id = entry.remoteID
        message.text = text
        send?(entry.peer, message)
    }

    func removeAll() {
        center?.removeDeliveredNotifications(withIdentifiers: notices.map(\.id))
        notices.removeAll()
    }

    func removePeer(_ peer: String) {
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
            if action == "dismiss" || action == UNNotificationDismissActionIdentifier { dismiss(entry) }
        }
    }
}
