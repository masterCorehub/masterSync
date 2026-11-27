import AppKit
import SwiftUI

/// Which kind of banner an Android notification gets on the Mac.
enum NoticeStyle: String, CaseIterable {
    case system, custom

    init(stored: String?) { self = stored.flatMap(NoticeStyle.init(rawValue:)) ?? .system }

    var title: String {
        switch self {
        case .system: "Padrão do macOS"
        case .custom: "Personalizado"
        }
    }
}

/// The notices showing in the corner card: newest first, at most `limit`, one entry per id.
struct NoticeBannerQueue {
    let limit: Int
    private(set) var ids: [String] = []
    /// The card whose reply field is open: it stays until the reply is sent or cancelled.
    private(set) var replyingID: String?

    init(limit: Int) { self.limit = limit }

    var isEmpty: Bool { ids.isEmpty }

    mutating func add(_ id: String) {
        ids.removeAll { $0 == id }
        ids.insert(id, at: 0)
        if ids.count > limit { ids.removeLast(ids.count - limit) }
    }

    mutating func remove(_ id: String) {
        ids.removeAll { $0 == id }
        if replyingID == id { replyingID = nil }
    }

    mutating func beginReply(_ id: String) { replyingID = id }
    mutating func endReply() { replyingID = nil }
    func shouldExpire(_ id: String) -> Bool { replyingID != id }
}

enum NoticeReplyDraft {
    /// The phone accepts replies of up to 1024 bytes.
    static func canSend(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf8.count <= 1024
    }
}

@MainActor
private final class NoticeBannerState: ObservableObject {
    @Published var items: [NotificationSync.Notice] = []
    @Published var replying: String?
    @Published var draft = ""
    var open: () -> Void = {}
    var close: (String) -> Void = { _ in }
    var beginReply: (String) -> Void = { _ in }
    var cancelReply: () -> Void = {}
    var send: (NotificationSync.Notice, String) -> Void = { _, _ in }
}

private struct NoticeBannerView: View {
    @ObservedObject var state: NoticeBannerState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = NexusPalette(scheme: scheme)
        VStack(spacing: 8) {
            ForEach(state.items) { notice in
                HStack(alignment: .top, spacing: 12) {
                    Group {
                        if let icon = notice.icon {
                            Image(nsImage: icon).resizable().scaledToFit().padding(4)
                        } else {
                            Text(String(notice.app.prefix(1)).uppercased()).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        }
                    }
                    .frame(width: 42, height: 42)
                    .background(notice.icon == nil ? NexusPalette.hueColor(NexusPalette.stableHue(notice.group)) : palette.panel2,
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(notice.app).font(.system(size: 11.5)).foregroundStyle(palette.muted).lineLimit(1)
                        Text(notice.title).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                        if !notice.body.isEmpty {
                            Text(notice.body).font(.system(size: 12.5)).foregroundStyle(palette.muted).lineLimit(2)
                        }
                        if notice.canReply { replyArea(notice, palette) }
                    }
                    Spacer(minLength: 0)
                    Button { state.cancelReply(); state.close(notice.id) } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.muted)
                            .frame(width: 22, height: 22).background(palette.panel2, in: Circle())
                    }
                    .buttonStyle(.plain).accessibilityLabel("Fechar aviso de \(notice.app)")
                }
                .padding(12)
                .frame(width: 360, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .background(palette.windowTint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(palette.edge) }
                .contentShape(Rectangle())
                .onTapGesture { if state.replying == nil { state.open(); state.close(notice.id) } }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(notice.app): \(notice.title). \(notice.body)")
            }
        }
        .foregroundStyle(palette.ink)
        .padding(6)
    }

    @ViewBuilder private func replyArea(_ notice: NotificationSync.Notice, _ palette: NexusPalette) -> some View {
        if state.replying == notice.id {
            HStack(spacing: 6) {
                TextField("Responder…", text: $state.draft)
                    .textFieldStyle(.plain).font(.system(size: 12.5))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(palette.input, in: Capsule())
                    .overlay { Capsule().strokeBorder(palette.line) }
                    .onSubmit { submit(notice) }
                Button("Enviar") { submit(notice) }
                    .buttonStyle(NexusPillStyle(prominent: true, compact: true))
                    .disabled(!NoticeReplyDraft.canSend(state.draft))
                Button("Cancelar") { state.cancelReply() }
                    .buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(palette.muted)
            }
            .padding(.top, 4)
        } else {
            Button("Responder") { state.draft = ""; state.beginReply(notice.id) }
                .buttonStyle(NexusPillStyle(compact: true)).padding(.top, 4)
        }
    }

    private func submit(_ notice: NotificationSync.Notice) {
        guard NoticeReplyDraft.canSend(state.draft) else { return }
        state.send(notice, state.draft)
    }
}

/// A panel that never activates the app but can take the keyboard, so the reply field can be typed in.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Android notifications as cards in the corner of the screen, above every app: the phone app's own icon, no macOS banner.
@MainActor
final class NoticeBannerController {
    private let state = NoticeBannerState()
    private var queue = NoticeBannerQueue(limit: 3)
    private var shown: [String: NotificationSync.Notice] = [:]
    private var timers: [String: Task<Void, Never>] = [:]
    private var panel: NSPanel?
    /// How long a card stays before it goes away by itself.
    var seconds: Double = 7

    init(open: @escaping () -> Void, reply: @escaping (NotificationSync.Notice, String) -> Void) {
        state.open = open
        state.close = { [weak self] id in self?.close(id) }
        state.beginReply = { [weak self] id in
            guard let self else { return }
            queue.beginReply(id)
            state.replying = id
            panel?.makeKey()
        }
        state.cancelReply = { [weak self] in self?.endReply() }
        state.send = { [weak self] notice, text in
            reply(notice, text)
            self?.close(notice.id)
        }
    }

    private func endReply() {
        let id = queue.replyingID
        queue.endReply()
        state.replying = nil
        state.draft = ""
        if let id, shown[id] != nil { startTimer(id) }
    }

    func show(_ notice: NotificationSync.Notice) {
        queue.add(notice.id)
        shown[notice.id] = notice
        startTimer(notice.id)
        refresh()
    }

    private func startTimer(_ id: String) {
        timers[id]?.cancel()
        timers[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.seconds ?? 7))
            guard !Task.isCancelled, let self, queue.shouldExpire(id) else { return }
            close(id)
        }
    }

    private func close(_ id: String) {
        timers[id]?.cancel()
        timers[id] = nil
        shown[id] = nil
        queue.remove(id)
        if queue.replyingID == nil { state.replying = nil; state.draft = "" }
        refresh()
    }

    private func refresh() {
        state.items = queue.ids.compactMap { shown[$0] }
        guard !state.items.isEmpty else { panel?.orderOut(nil); return }
        let panel = panel ?? makePanel()
        self.panel = panel
        if let screen = NSScreen.main {
            let size = panel.contentView?.fittingSize ?? CGSize(width: 372, height: 80)
            panel.setFrame(ScanPopup.frame(size: size, in: screen.visibleFrame), display: true)
        }
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(contentRect: CGRect(x: 0, y: 0, width: 372, height: 80), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: NoticeBannerView(state: state))
        return panel
    }
}
