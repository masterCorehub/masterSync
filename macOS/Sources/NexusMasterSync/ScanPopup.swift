import AppKit
import Combine
import SwiftUI

/// The rules for the scan download pop-up: what it says and where it sits. Pure, so it can be tested.
enum ScanPopup {
    struct Content: Equatable {
        let title: String
        let fraction: Double
        let verifying: Bool
    }

    /// What to show for the transfers in flight: only pages coming from the phone's scanner count.
    static func content(for progress: [FileTransfers.Progress]) -> Content? {
        let pages = progress.filter { $0.scan && !$0.sending }
        guard !pages.isEmpty else { return nil }
        let total = pages.reduce(Int64(0)) { $0 + max($1.size, 0) }
        let done = pages.reduce(Int64(0)) { $0 + min(max($1.offset, 0), max($1.size, 0)) }
        let fraction = total > 0 ? min(1, max(0, Double(done) / Double(total))) : 0
        let verifying = pages.allSatisfy(\.verifying)
        let title = verifying ? "Verificando a digitalização…"
            : pages.count == 1 ? "Baixando a digitalização…" : "Baixando \(pages.count) digitalizações…"
        return Content(title: title, fraction: fraction, verifying: verifying)
    }

    static func finishedTitle(count: Int) -> String {
        count == 1 ? "Digitalização recebida" : "\(count) digitalizações recebidas"
    }

    /// The top right corner of the screen, just under the menu bar.
    static func frame(size: CGSize, in screen: CGRect) -> CGRect {
        CGRect(x: screen.maxX - size.width - 16, y: screen.maxY - size.height - 12, width: size.width, height: size.height)
    }
}

private struct ScanPopupView: View {
    @ObservedObject var state: ScanPopupState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = NexusPalette(scheme: scheme)
        HStack(spacing: 12) {
            IconBadge(systemName: state.done ? "checkmark" : "doc.viewfinder", size: 40)
            VStack(alignment: .leading, spacing: 7) {
                Text(state.title).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                if state.done {
                    Text("Já está na sua área de transferência e na galeria.").font(.system(size: 11.5)).foregroundStyle(palette.muted)
                } else {
                    HStack(spacing: 8) {
                        GeometryReader { bar in
                            ZStack(alignment: .leading) {
                                Capsule().fill(palette.track)
                                Capsule().fill(palette.fill).frame(width: bar.size.width * state.fraction)
                            }
                        }.frame(height: 5)
                        Text("\(Int(state.fraction * 100))%").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(palette.muted)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(palette.windowTint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(palette.edge) }
        .foregroundStyle(palette.ink)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(state.done ? state.title : "\(state.title) \(Int(state.fraction * 100)) por cento")
    }
}

@MainActor
private final class ScanPopupState: ObservableObject {
    @Published var title = ""
    @Published var fraction = 0.0
    @Published var done = false
}

/// A small floating panel, above every app and every Space, that tells when a scan is being downloaded.
@MainActor
final class ScanPopupController {
    private let state = ScanPopupState()
    private var panel: NSPanel?
    private var cancellable: AnyCancellable?
    private var hideTask: Task<Void, Never>?
    private var wasDownloading = false
    private var downloaded = 0
    private var lastScanCount = 0
    private let files: FileTransfers

    init(files: FileTransfers) {
        self.files = files
        lastScanCount = files.received.filter { $0.offer.isScanPage }.count
        cancellable = files.$progress.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.update() }
    }

    private func update() {
        if let content = ScanPopup.content(for: files.progress) {
            hideTask?.cancel()
            wasDownloading = true
            state.done = false
            state.title = content.title
            state.fraction = content.fraction
            show()
        } else if wasDownloading {
            wasDownloading = false
            // The page is indexed a moment after its transfer ends; count the new ones, or hide if the transfer failed.
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                guard let self, !Task.isCancelled else { return }
                let now = files.received.filter { $0.offer.isScanPage }.count
                let fresh = max(0, now - lastScanCount)
                lastScanCount = now
                guard fresh > 0 else { hide(); return }
                state.done = true
                state.title = ScanPopup.finishedTitle(count: fresh)
                state.fraction = 1
                show()
                try? await Task.sleep(for: .seconds(2.6))
                if !Task.isCancelled { hide() }
            }
        }
    }

    private func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        if let screen = NSScreen.main {
            let size = panel.contentView?.fittingSize ?? CGSize(width: 340, height: 80)
            panel.setFrame(ScanPopup.frame(size: size, in: screen.visibleFrame), display: true)
        }
        panel.orderFrontRegardless()
    }

    private func hide() { panel?.orderOut(nil) }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 340, height: 80), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // A notice, not a window: it never takes focus or clicks from what the person is doing.
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: ScanPopupView(state: state))
        return panel
    }
}
