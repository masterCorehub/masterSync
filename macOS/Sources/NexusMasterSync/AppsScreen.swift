import AppKit
import NexusCore
import SwiftUI

/// The current phone-control session, listed as the one "open" app window.
struct AppsSession {
    let title: String
    let state: String
}

struct AppsScreenData {
    var phoneName: String
    var apps: [AndroidApp]
    /// nil while the phone has not sent its list yet.
    var listLoaded: Bool
    var pins: [String]
    var icons: [String: NSImage]
    var active: Bool
    var launcherAvailable: Bool
    var canLaunch: Bool
    var needsWirelessSetup: Bool
    var session: AppsSession?
}

struct AppsScreenActions {
    var open: (AndroidApp) -> Void = { _ in }
    var togglePin: (String) -> Void = { _ in }
    var refresh: () -> Void = {}
    var setupWireless: () -> Void = {}
    var focusSession: () -> Void = {}
    var closeSession: () -> Void = {}
}

/// An app's icon from the phone, or its initial on a color when the icon was not sent.
struct AppIcon: View {
    let app: AndroidApp
    let icon: NSImage?
    var size: CGFloat = 40
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = NexusPalette(scheme: scheme)
        Group {
            if let icon {
                Image(nsImage: icon).resizable().interpolation(.high).scaledToFit().padding(size * 0.1)
            } else {
                Text(String(Wire.visible(app.label, limit: 70).prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .background(icon == nil ? NexusPalette.hueColor(NexusPalette.stableHue(app.id)) : palette.panel2,
                    in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct AppsScreen: View {
    let data: AppsScreenData
    let actions: AppsScreenActions
    @State private var query = ""
    @Environment(\.colorScheme) private var scheme

    private var palette: NexusPalette { NexusPalette(scheme: scheme) }
    private var pinned: [AndroidApp] { AppsCatalog.pinned(data.apps, ids: data.pins) }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                main.frame(maxWidth: .infinity, alignment: .top)
                side.frame(width: 300)
            }
            .frame(minWidth: 660)
            VStack(alignment: .leading, spacing: 16) { main; side }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let notice { notice }
            pinnedCard
            allAppsCard
        }
    }

    private var notice: Text? {
        if !data.active { return Text("Conecte o Android para carregar os apps.") }
        if !data.launcherAvailable { return Text("Atualize o MasterSync no Android para ver os apps.") }
        if !data.listLoaded { return Text("Aguardando a lista do Android…") }
        return nil
    }

    private var pinnedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label { Text("Fixados").font(.system(size: 13, weight: .bold)) } icon: {
                    Image(systemName: "pin.fill").font(.system(size: 12)).foregroundStyle(palette.accent)
                }
                Spacer()
                Text("Os 5 primeiros ficam na barra lateral e no menu").font(.system(size: 12)).foregroundStyle(palette.muted)
            }
            if pinned.isEmpty {
                Text("Use o alfinete num app abaixo para fixá-lo aqui.")
                    .font(.system(size: 12.5)).foregroundStyle(palette.muted).padding(.vertical, 14)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(pinned) { app in
                        let label = Wire.visible(app.label, limit: 70)
                        ZStack(alignment: .topTrailing) {
                            Button { actions.open(app) } label: {
                                VStack(spacing: 8) {
                                    AppIcon(app: app, icon: data.icons[app.id], size: 50)
                                    Text(label).font(.system(size: 12, weight: .medium)).lineLimit(1).frame(maxWidth: 76)
                                }
                                .padding(.vertical, 10).frame(width: 84)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).disabled(!data.canLaunch)
                            .accessibilityLabel("Abrir \(label)")
                            Button { actions.togglePin(app.id) } label: {
                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(palette.muted)
                                    .frame(width: 20, height: 20)
                                    .background(palette.panel2, in: Circle()).overlay { Circle().strokeBorder(palette.line) }
                            }
                            .buttonStyle(.plain).padding(.trailing, 6).padding(.top, 4)
                            .accessibilityLabel("Desafixar \(label)").help("Desafixar \(label)")
                        }
                    }
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(radius: 20)
    }

    private var allAppsCard: some View {
        let filtered = AppsCatalog.filter(data.apps, query: query)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Todos os apps").font(.system(size: 13, weight: .bold))
                    + Text(" · \(data.apps.count)").font(.system(size: 13)).foregroundStyle(palette.muted)
                Spacer()
                Button { actions.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).foregroundStyle(palette.muted)
                    .disabled(!data.launcherAvailable).accessibilityLabel("Atualizar lista de apps")
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(palette.muted)
                    TextField("Buscar apps do \(data.phoneName)", text: $query).textFieldStyle(.plain)
                }
                .font(.system(size: 13))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .frame(width: 240)
                .background(palette.input, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.line) }
            }
            if data.needsWirelessSetup && data.active {
                Button("Configurar controle por Wi-Fi", action: actions.setupWireless)
                    .buttonStyle(NexusPillStyle(compact: true))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], spacing: 8) {
                ForEach(filtered) { app in
                    let label = Wire.visible(app.label, limit: 70)
                    let isPinned = data.pins.contains(app.id)
                    HStack(spacing: 4) {
                        Button { actions.open(app) } label: {
                            HStack(spacing: 10) {
                                AppIcon(app: app, icon: data.icons[app.id], size: 34)
                                Text(label).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 5).padding(.leading, 6).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).disabled(!data.canLaunch)
                        .accessibilityLabel("Abrir \(label)")
                        Button { actions.togglePin(app.id) } label: {
                            Image(systemName: isPinned ? "pin.fill" : "pin").font(.system(size: 14))
                                .foregroundStyle(isPinned ? palette.accent : palette.faint)
                                .frame(width: 28, height: 28).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isPinned ? "Desafixar \(label)" : "Fixar \(label)")
                        .help(isPinned ? "Desafixar app" : "Fixar app")
                    }
                    .padding(.trailing, 4)
                    .overlay { RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(palette.line) }
                }
            }
            if filtered.isEmpty && data.listLoaded {
                Text("Nenhum app encontrado.").font(.system(size: 13)).foregroundStyle(palette.muted)
                    .frame(maxWidth: .infinity).padding(24)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(radius: 20)
    }

    private var side: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Abertos no Mac").font(.system(size: 13, weight: .bold)).padding(.bottom, 8)
                if let session = data.session {
                    HStack(spacing: 10) {
                        Button(action: actions.focusSession) {
                            HStack(spacing: 10) {
                                IconBadge(systemName: "iphone", size: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(session.title).font(.system(size: 13, weight: .semibold))
                                    Text(session.state).font(.system(size: 11)).foregroundStyle(palette.muted)
                                }
                                Spacer(minLength: 0)
                            }.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityLabel("Mostrar o controle do celular")
                        Button(action: actions.closeSession) {
                            Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.muted)
                                .frame(width: 28, height: 28).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityLabel("Encerrar o controle do celular")
                    }
                    .padding(.vertical, 8).overlay(alignment: .top) { Rectangle().fill(palette.line).frame(height: 1) }
                } else {
                    Text("Nenhum app aberto. Clique num app para abri-lo no controle do celular.")
                        .font(.system(size: 12.5)).foregroundStyle(palette.muted).lineSpacing(2)
                        .padding(.top, 8).overlay(alignment: .top) { Rectangle().fill(palette.line).frame(height: 1) }
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(radius: 20)
            VStack(alignment: .leading, spacing: 6) {
                Label("O controle continua com o celular bloqueado", systemImage: "lock.iphone")
                    .font(.system(size: 12.5, weight: .semibold))
                Text("Os apps abrem na tela de controle, que não precisa de autorização no celular.")
                    .font(.system(size: 11.5)).foregroundStyle(palette.muted).lineSpacing(2)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(radius: 20)
        }
    }
}
