import AppKit
import SwiftUI

/// Puts a verification code on the pasteboard for a short while, hidden from clipboard managers.
enum CodeClipboard {
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    @MainActor
    static func copy(_ code: String, to pasteboard: NSPasteboard = .general, clearAfter delay: TimeInterval = 120) {
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
        pasteboard.setData(Data(), forType: concealedType)
        let mine = pasteboard.changeCount
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            // Only if the person has not copied anything else since.
            if pasteboard.changeCount == mine { pasteboard.clearContents() }
        }
    }
}

@MainActor
private final class CodePopupState: ObservableObject {
    @Published var code = ""
    @Published var app = ""
}

private struct CodePopupView: View {
    @ObservedObject var state: CodePopupState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = NexusPalette(scheme: scheme)
        HStack(spacing: 12) {
            IconBadge(systemName: "key.fill", size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text("Código copiado · \(state.app)").font(.system(size: 12)).foregroundStyle(palette.muted).lineLimit(1)
                Text(OtpCode.display(state.code)).font(.system(size: 24, weight: .bold, design: .monospaced)).tracking(1)
                Text("Cole com ⌘V").font(.system(size: 11.5)).foregroundStyle(palette.faint)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(palette.windowTint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(palette.edge) }
        .foregroundStyle(palette.ink)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Código \(state.code.map(String.init).joined(separator: " ")) copiado, de \(state.app). Cole com comando V.")
    }
}

/// A notice in the corner of the screen, above every app, for a verification code that was just copied.
@MainActor
final class CodePopupController {
    private let state = CodePopupState()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(code: String, app: String) {
        state.code = code
        state.app = app
        let panel = panel ?? makePanel()
        self.panel = panel
        if let screen = NSScreen.main {
            let size = panel.contentView?.fittingSize ?? CGSize(width: 340, height: 92)
            panel.setFrame(ScanPopup.frame(size: size, in: screen.visibleFrame), display: true)
        }
        panel.orderFrontRegardless()
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { self?.panel?.orderOut(nil) }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 340, height: 92), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: CodePopupView(state: state))
        return panel
    }
}
