import SwiftUI

private enum SectionGroup: String, CaseIterable {
    case home = "Início"
    case library = "Biblioteca"
    case connection = "Conexão"

    var sections: [Section] {
        switch self {
        case .home: [.overview, .clipboard]
        case .library: [.gallery, .documents, .files]
        case .connection: [.devices, .remote, .notifications, .settings]
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .library: "square.stack"
        case .connection: "link"
        }
    }

    init(section: Section) {
        switch section {
        case .overview, .clipboard: self = .home
        case .gallery, .documents, .files: self = .library
        case .devices, .remote, .notifications, .settings: self = .connection
        }
    }
}

struct DashboardHeader: View {
    @ObservedObject var model: NexusModel
    @ObservedObject var gallery: GalleryModel
    @Environment(\.colorScheme) private var scheme
    @State private var showingSearch = false
    @State private var showingActions = false
    @State private var lastSection: [SectionGroup: Section] = [:]

    private var palette: NexusPalette { NexusPalette(scheme: scheme) }
    private var group: SectionGroup { SectionGroup(section: model.section) }
    private var hasGallerySearch: Bool { model.section == .gallery && model.canBrowseGallery && gallery.advanced }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 15) {
                wordmark
                Spacer(minLength: 2)
                groups
                Spacer(minLength: 2)
                search
                actions
            }
            HStack(spacing: 8) {
                ForEach(group.sections) { section in
                    Button { model.section = section } label: {
                        Label(section.rawValue, systemImage: section.icon)
                            .lineLimit(1).fixedSize()
                    }
                    .buttonStyle(NexusPillStyle(selected: model.section == section, compact: true))
                    .accessibilityAddTraits(model.section == section ? .isSelected : [])
                }
            }
        }
        .onChange(of: model.section) {
            // Returning to a group restores the last section the user opened there.
            lastSection[SectionGroup(section: model.section)] = model.section
        }
    }

    private var wordmark: some View {
        HStack(spacing: 9) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 35, height: 35)
                .background(palette.accentSurface, in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 0) {
                Text("Nexus").font(.system(size: 20, weight: .bold, design: .rounded))
                    .tracking(-0.4)
                    .foregroundStyle(palette.accent)
                Text("masterSync").font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.muted)
            }.fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nexus masterSync")
    }

    private var groups: some View {
        HStack(spacing: 4) {
            ForEach(SectionGroup.allCases, id: \.self) { item in
                Button {
                    if item != group, let section = lastSection[item] ?? item.sections.first { model.section = section }
                } label: {
                    Label(item.rawValue, systemImage: item.icon).fixedSize()
                }
                .buttonStyle(NexusPillStyle(selected: item == group, segmented: true))
                .accessibilityAddTraits(item == group ? .isSelected : [])
            }
        }
        .padding(4)
        .background(palette.surface, in: Capsule())
    }

    private var search: some View {
        Group {
            if hasGallerySearch {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundStyle(palette.muted)
                    TextField("Buscar na galeria", text: $gallery.filters.name)
                        .textFieldStyle(.plain)
                    if !gallery.filters.name.isEmpty {
                        Button { gallery.filters.name = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                        }.buttonStyle(.plain).accessibilityLabel("Limpar busca")
                    }
                }
                .padding(.horizontal, 13)
                .frame(height: 36)
                .background(palette.control, in: Capsule())
            } else {
                Button { showingSearch = true } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass").foregroundStyle(palette.muted)
                        Text("Buscar seção").lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }.buttonStyle(NexusPillStyle())
                    .popover(isPresented: $showingSearch, arrowEdge: .bottom) {
                        SectionSearch { section in
                            model.section = section
                            showingSearch = false
                        }
                    }
            }
        }.frame(minWidth: 118, idealWidth: 178, maxWidth: 210)
    }

    private var actions: some View {
        Button { showingActions = true } label: {
            Image(systemName: "ellipsis").font(.system(size: 14, weight: .bold))
                .frame(width: 36, height: 36)
                .background(palette.control, in: Circle())
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Mais opções")
        .popover(isPresented: $showingActions, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 9) {
                action("Dispositivos", icon: Section.devices.icon) { model.section = .devices }
                action("Configurações", icon: Section.settings.icon) { model.section = .settings }
                if model.screen.sharing {
                    Divider()
                    action("Parar espelhamento", icon: "stop.circle") { model.screen.end() }
                }
            }
            .padding(13)
            .frame(width: 205)
        }
    }

    private func action(_ title: String, icon: String, open: @escaping () -> Void) -> some View {
        Button {
            showingActions = false
            open()
        } label: {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.borderless)
    }
}

private struct SectionSearch: View {
    var open: (Section) -> Void
    @State private var query = ""
    @FocusState private var focused: Bool

    private var matches: [Section] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty ? Section.allCases : Section.allCases.filter { $0.rawValue.localizedStandardContains(term) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            TextField("Buscar seção", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { if let first = matches.first { open(first) } }
            if matches.isEmpty { Text("Nenhuma seção encontrada.").foregroundStyle(.secondary) }
            ForEach(matches) { section in
                Button { open(section) } label: {
                    Label(section.rawValue, systemImage: section.icon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.borderless).controlSize(.large)
            }
        }
        .padding(14)
        .frame(width: 235)
        .onAppear { focused = true }
    }
}

struct ConnectionBar: View {
    @ObservedObject var model: NexusModel
    let sendFile: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var palette: NexusPalette { NexusPalette(scheme: scheme) }
    private var currentTransfer: FileTransfers.Progress? {
        model.files.progress.first { $0.peer == model.selected?.id } ?? model.files.progress.first
    }

    private var connectionDetail: String {
        if model.connecting { return "Iniciando rede local…" }
        if !model.serviceReady { return "Rede local desativada" }
        if model.active { return "Conectado pela rede local" }
        if model.selected != nil { return "Aguardando reconexão" }
        return "Nenhum celular pareado"
    }

    var body: some View {
        HStack(spacing: 17) {
            HStack(spacing: 12) {
                Image(systemName: model.active ? "iphone.radiowaves.left.and.right" : "iphone")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(palette.accentInk)
                    .frame(width: 46, height: 46)
                    .background(palette.accent, in: RoundedRectangle(cornerRadius: 15))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.selected?.name ?? "Android").font(.headline).lineLimit(1)
                    HStack(spacing: 6) {
                        Circle().fill(model.active ? palette.connected : palette.muted.opacity(0.75))
                            .frame(width: 6, height: 6).accessibilityHidden(true)
                        Text(connectionDetail).font(.caption).foregroundStyle(palette.muted).lineLimit(1)
                    }
                }
            }.accessibilityElement(children: .combine)
            if model.active, let battery = model.selectedStatus?.battery {
                let charging = model.selectedStatus?.charging == true
                Label("\(battery)%", systemImage: batterySymbol(battery, charging: charging))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(palette.control, in: Capsule())
                    .fixedSize()
                    .accessibilityLabel("Bateria \(battery) por cento\(charging ? ", carregando" : "")")
            }
            Spacer(minLength: 5)
            if let transfer = currentTransfer { transferStatus(transfer) }
            primaryAction
        }
        .padding(.horizontal, 15).padding(.vertical, 12)
        .nexusPanel(palette, radius: 22)
    }

    @ViewBuilder
    private var primaryAction: some View {
        if model.canSendFiles {
            Button(action: sendFile) { Label("Enviar arquivo", systemImage: "arrow.up") }
                .buttonStyle(NexusPillStyle(prominent: true))
        } else if !model.serviceReady {
            Button {
                model.section = .devices
                model.enableNetwork()
            } label: { Label("Ativar rede local", systemImage: "wifi") }
                .buttonStyle(NexusPillStyle(prominent: true)).disabled(model.connecting)
        } else if model.selected == nil {
            Button {
                model.section = .devices
                model.pair()
            } label: { Label("Parear Android", systemImage: "qrcode") }
                .buttonStyle(NexusPillStyle(prominent: true))
        } else {
            Button { model.section = .devices } label: { Label("Dispositivos", systemImage: "iphone") }
                .buttonStyle(NexusPillStyle())
        }
    }

    private func transferStatus(_ transfer: FileTransfers.Progress) -> some View {
        Button { model.section = .files } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: transfer.sending ? "arrow.up" : "arrow.down")
                    Text(transfer.verifying ? "Verificando arquivo" : transfer.name).lineLimit(1)
                    Spacer(minLength: 0)
                    if !transfer.verifying {
                        Text(transfer.fraction, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                    }
                }.font(.caption.weight(.medium))
                ProgressView(value: transfer.fraction).tint(palette.accent)
            }.frame(minWidth: 112, idealWidth: 172, maxWidth: 220)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Transferência de \(transfer.name)")
        .help("Abrir arquivos")
    }

    private func batterySymbol(_ percentage: Int, charging: Bool) -> String {
        if charging { return "battery.100percent.bolt" }
        switch percentage {
        case 0...5: return "battery.0percent"
        case 6...25: return "battery.25percent"
        case 26...50: return "battery.50percent"
        case 51...75: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
