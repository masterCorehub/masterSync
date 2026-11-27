import NexusCore
import SwiftUI

/// What the menu bar icon opens: the phone, quick switches, pinned apps, what was copied, and the common actions.
struct MenuBarPanel: View {
    @ObservedObject var model: NexusModel
    /// Opens the main window on a section.
    let open: (Section) -> Void
    let quit: () -> Void
    @AppStorage("android-launcher-pins") private var storedPins = Data()
    @Environment(\.colorScheme) private var scheme

    private var palette: NexusPalette { NexusPalette(scheme: scheme) }

    private var pinnedApps: [AndroidApp] {
        let peer = model.selected?.id ?? ""
        let pins = ((try? JSONDecoder().decode([String: [String]].self, from: storedPins)) ?? [:])[peer] ?? []
        return AppsCatalog.sidebarPins(AppsCatalog.pinned(model.launcherLists[peer] ?? [], ids: pins))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            phone
            tiles
            apps
            clipboard
            if model.screen.inAppControl || model.screen.sharing || model.screen.usbActive { sessions }
            HStack(spacing: 8) {
                button("Enviar arquivo…", prominent: false) { open(.files) }
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
            tile("document.on.clipboard", "Transferência", model.clipboardEnabled ? "Sincronizando" : "Pausada", on: model.clipboardEnabled) {
                model.clipboardEnabled.toggle()
            }
            tile("bell", "Notificações", model.notificationsEnabled ? "Espelhando" : "Desligadas", on: model.notificationsEnabled) {
                model.notificationsEnabled.toggle()
            }
            tile("cast", "Espelhar", model.screen.sharing ? "Ao vivo" : "Pronto", on: model.screen.sharing, enabled: model.screen.sharing || model.canMirror) {
                if model.screen.sharing { model.screen.end() } else { model.requestMirror() }
            }
            tile("cursorarrow.rays", "Controlar", (model.screen.inAppControl || model.screen.usbActive) ? "Em andamento" : "Abrir", on: model.screen.inAppControl) {
                open(.remote)
            }
        }
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
