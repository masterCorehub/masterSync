import NexusCore
import SwiftUI

/// Pure rules for what the menu bar icon and panel show.
enum MenuBarSummary {
    static func unread(notices: Int, sms: Int) -> Int { max(0, notices) + max(0, sms) }

    /// "82% · 3", "82%", "3", or nil when there is nothing to show.
    static func labelText(battery: Int?, unread: Int) -> String? {
        let count = unread > 99 ? "99+" : unread > 0 ? "\(unread)" : nil
        switch (battery, count) {
        case let (b?, c?): return "\(b)% · \(c)"
        case let (b?, nil): return "\(b)%"
        case let (nil, c?): return c
        default: return nil
        }
    }

    /// Newest first, at most `limit`.
    static func preview(_ items: [(id: String, date: Date)], limit: Int) -> [(id: String, date: Date)] {
        Array(items.sorted { $0.date > $1.date }.prefix(limit))
    }
}

/// What the menu bar icon opens: the phone, quick switches, pinned apps, what was copied, and the common actions.
struct MenuBarPanel: View {
    @ObservedObject var model: NexusModel
    /// Opens the main window on a section.
    let open: (Section) -> Void
    let quit: () -> Void
    @AppStorage("android-launcher-pins") private var storedPins = Data()
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openWindow) private var openWindow

    private var palette: NexusPalette { NexusPalette(scheme: scheme) }

    private var pinnedApps: [AndroidApp] {
        let peer = model.selected?.id ?? ""
        let pins = ((try? JSONDecoder().decode([String: [String]].self, from: storedPins)) ?? [:])[peer] ?? []
        return AppsCatalog.sidebarPins(AppsCatalog.pinned(model.launcherLists[peer] ?? [], ids: pins))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            phone
            controls
            tiles
            notices
            apps
            clipboard
            if model.screen.inAppControl || model.screen.sharing || model.screen.usbActive { sessions }
            HStack(spacing: 8) {
                button("Enviar arquivo…", prominent: false) { sendFile() }
                button("Abrir MasterSync", prominent: true) { open(.overview) }
            }
            Button("Encerrar Nexus masterSync", action: quit)
                .buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(palette.muted)
                .frame(maxWidth: .infinity)
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
        .background { NexusBackdrop() }
        .foregroundStyle(palette.ink)
        .toggleStyle(GlassToggleStyle())
    }

    private var phone: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: "iphone", size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.selected?.name ?? "Nenhum celular").font(.system(size: 14, weight: .bold)).lineLimit(1)
                Text(model.selected == nil ? "Pareie um Android para começar"
                     : model.active ? "Conectado pela rede local" : "Desconectado")
                    .font(.system(size: 11.5)).foregroundStyle(palette.muted)
            }
            Spacer(minLength: 0)
            if let battery = model.selectedStatus?.battery {
                Label("\(battery)%", systemImage: model.selectedStatus?.charging == true ? "battery.100percent.bolt" : "battery.75percent")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(palette.accent)
            }
        }
    }

    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            tile("document.on.clipboard", "Transferência", model.clipboardSyncActive ? "Sincronizando" : "Pausada", on: model.clipboardSyncActive) {
                model.setClipboardSync(!model.clipboardSyncActive)
            }
            tile("bell", "Notificações", model.notificationsEnabled ? "Espelhando" : "Desligadas", on: model.notificationsEnabled) {
                model.notificationsEnabled.toggle()
            }
            tile("cast", "Espelhar", model.screen.sharing ? "Ao vivo" : "Abre a janela", on: model.screen.sharing, enabled: model.screen.sharing || model.canMirror) {
                if model.screen.sharing { model.screen.end() } else {
                    model.requestMirror()
                    openWindow(id: "mirror")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            tile("speaker.wave.2", "Ouvir som", model.screen.audioOnlyActive ? "Tocando no Mac" : "Do celular no Mac", on: model.screen.audioOnlyActive,
                 enabled: model.active) { toggleAudio() }
            tile("cursorarrow.rays", "Controlar", (model.screen.inAppControl || model.screen.usbActive) ? "Em andamento" : "Abrir", on: model.screen.inAppControl) {
                open(.remote)
            }
            tile("document.viewfinder", "Digitalizar", "Câmera do celular", on: false, enabled: model.active) { model.requestScan() }
        }
    }

    private var controls: some View {
        let items = QuickControls.items(model.quickControlInputs)
        return HStack(spacing: 0) {
            ForEach(items) { item in
                Button { model.pressQuickControl(item.kind) } label: {
                    Image(systemName: item.icon).font(.system(size: 14))
                        .foregroundStyle(item.isOn ? palette.accentInk : palette.ink)
                        .frame(width: 38, height: 38)
                        .background(item.isOn ? palette.fill : palette.panel2, in: Circle())
                        .overlay { Circle().strokeBorder(palette.line) }
                        .opacity(item.isEnabled ? 1 : 0.45)
                }
                .buttonStyle(.plain).frame(maxWidth: .infinity)
                .help(item.accessibilityLabel).accessibilityLabel(item.accessibilityLabel)
            }
        }
    }

    private var peerNotices: [NotificationSync.Notice] {
        model.notifications.notices.filter { $0.peer == model.selected?.id }
    }

    private var notices: some View {
        let byID = Dictionary(peerNotices.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let shown = MenuBarSummary.preview(peerNotices.map { (id: $0.id, date: $0.date) }, limit: 4).compactMap { byID[$0.id] }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("NOTIFICAÇÕES").font(.system(size: 10.5, weight: .semibold)).tracking(0.7).foregroundStyle(palette.muted)
                Spacer()
                if model.smsAvailable, model.sms.unreadTotal > 0 {
                    Button("\(model.sms.unreadTotal) SMS não lidos") { open(.sms) }
                        .buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(palette.accent)
                }
                Button("Todas") { open(.notifications) }.buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(palette.accent)
            }
            if shown.isEmpty {
                Text(model.notificationsEnabled ? "Nenhuma notificação agora." : "Ligue as notificações para vê-las aqui.")
                    .font(.system(size: 11.5)).foregroundStyle(palette.muted)
            } else {
                VStack(spacing: 0) {
                    ForEach(shown) { notice in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(notice.title.isEmpty ? notice.app : "\(notice.app) · \(notice.title)")
                                    .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                if !notice.body.isEmpty {
                                    Text(notice.body).font(.system(size: 11.5)).foregroundStyle(palette.muted).lineLimit(2)
                                }
                            }
                            Spacer(minLength: 0)
                            Text(notice.date, style: .relative).font(.system(size: 10)).foregroundStyle(palette.faint).lineLimit(1)
                            if notice.canDismiss {
                                Button { model.notifications.dismiss(notice) } label: { Image(systemName: "xmark") }
                                    .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(palette.muted)
                                    .accessibilityLabel("Dispensar")
                            }
                        }
                        .padding(.vertical, 6)
                        if notice.id != shown.last?.id { Divider().overlay(palette.line) }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
                .glassPanel(radius: 14)
            }
        }
    }

    private func toggleAudio() {
        if model.screen.audioOnlyActive {
            model.screen.stopUSB()
        } else if let device = model.wirelessControlDevice(for: model.selected?.id) {
            model.screen.launchScrcpy(audioOnly: true, wireless: device)
        } else {
            open(.devices)
        }
    }

    private func sendFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { _ = model.sendItems(panel.urls) }
    }

    private func tile(_ icon: String, _ title: String, _ state: String, on: Bool, enabled: Bool = true,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 14))
                    .foregroundStyle(on ? palette.accentInk : palette.ink)
                    .frame(width: 30, height: 30)
                    .background(on ? palette.fill : palette.panel2, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(state).font(.system(size: 10.5)).foregroundStyle(palette.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(on ? palette.accentSurface : palette.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.line) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.5)
        .accessibilityLabel(title).accessibilityValue(state)
    }

    private var apps: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("APPS FIXADOS").font(.system(size: 10.5, weight: .semibold)).tracking(0.7).foregroundStyle(palette.muted)
                Spacer()
                Button("Todos") { open(.apps) }.buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(palette.accent)
            }
            if pinnedApps.isEmpty {
                Text("Nenhum app fixado.").font(.system(size: 11.5)).foregroundStyle(palette.muted)
            } else {
                HStack(spacing: 6) {
                    ForEach(pinnedApps) { app in
                        let label = Wire.visible(app.label, limit: 70)
                        Button {
                            model.launchAndroidApp(app)
                            open(.remote)
                        } label: {
                            VStack(spacing: 5) {
                                AppIcon(app: app, icon: model.launcherIcons[app.id], size: 38)
                                Text(label).font(.system(size: 10.5)).lineLimit(1).frame(maxWidth: .infinity)
                            }
                            .padding(.vertical, 6).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityLabel("Abrir \(label)")
                    }
                }
            }
        }
    }

    private var clipboard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("COPIADO NO CELULAR").font(.system(size: 10.5, weight: .semibold)).tracking(0.7).foregroundStyle(palette.muted)
            Text(model.clipboard.items.first?.text ?? "Nada copiado ainda.")
                .font(.system(size: 12.5)).lineLimit(2).lineSpacing(1)
                .foregroundStyle(model.clipboard.items.isEmpty ? palette.muted : palette.ink)
        }
        .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(radius: 14)
    }

    private var sessions: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.screen.inAppControl { Button("Encerrar controle") { model.screen.endAll() } }
            if model.screen.sharing { Button("Parar espelhamento") { model.screen.end() } }
            if model.screen.usbActive { Button("Encerrar sessão do scrcpy") { model.screen.stopUSB() } }
        }
        .buttonStyle(NexusPillStyle(compact: true))
    }

    private func button(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12.5, weight: prominent ? .bold : .semibold))
                .foregroundStyle(prominent ? palette.accentInk : palette.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(prominent ? palette.fill : palette.panel2, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay { if !prominent { RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(palette.line) } }
        }.buttonStyle(.plain)
    }
}
