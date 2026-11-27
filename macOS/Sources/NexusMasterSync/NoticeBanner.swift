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

    init(limit: Int) { self.limit = limit }

    var isEmpty: Bool { ids.isEmpty }

    mutating func add(_ id: String) {
        ids.removeAll { $0 == id }
        ids.insert(id, at: 0)
        if ids.count > limit { ids.removeLast(ids.count - limit) }
    }

    mutating func remove(_ id: String) { ids.removeAll { $0 == id } }
}

@MainActor
private final class NoticeBannerState: ObservableObject {
    @Published var items: [NotificationSync.Notice] = []
    var open: () -> Void = {}
    var close: (String) -> Void = { _ in }
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
                    }
                    Spacer(minLength: 0)
                    Button { state.close(notice.id) } label: {
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
                .onTapGesture { state.open(); state.close(notice.id) }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(notice.app): \(notice.title). \(notice.body)")
            }
        }
        .foregroundStyle(palette.ink)
        .padding(6)
    }
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

    init(open: @escaping () -> Void) {
        state.open = open
        state.close = { [weak self] id in self?.close(id) }
    }

    func show(_ notice: NotificationSync.Notice) {
        queue.add(notice.id)
        shown[notice.id] = notice
        timers[notice.id]?.cancel()
        let id = notice.id
        timers[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.seconds ?? 7))
            if !Task.isCancelled { self?.close(id) }
        }
        refresh()
    }

    private func close(_ id: String) {
        timers[id]?.cancel()
        timers[id] = nil
        shown[id] = nil
        queue.remove(id)
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
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 372, height: 80), styleMask: [.borderless, .nonactivatingPanel],
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
