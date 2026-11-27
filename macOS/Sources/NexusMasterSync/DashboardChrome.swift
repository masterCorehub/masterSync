import SwiftUI

/// The title line above each screen: name and subtitle, with the gallery search, notifications and stop-sharing at the right.
struct ContentHeader: View {
    @ObservedObject var model: NexusModel
    @ObservedObject var gallery: GalleryModel
    var notificationButton: AnyView
    @Environment(\.colorScheme) private var scheme

    private var palette: NexusPalette { NexusPalette(scheme: scheme) }
    private var hasGallerySearch: Bool { model.section == .gallery && model.canBrowseGallery && gallery.advanced }

    var body: some View {
        HStack(spacing: 12) {
            Text(model.section.title)
                .font(.system(size: 20, weight: .bold)).tracking(-0.2)
                .accessibilityAddTraits(.isHeader)
            Text(model.section.subtitle)
                .font(.system(size: 12.5)).foregroundStyle(palette.muted).lineLimit(1)
            Spacer(minLength: 12)
            if hasGallerySearch { search }
            if model.screen.sharing {
                Button { model.screen.end() } label: { Label("Parar espelhamento", systemImage: "stop.circle") }
                    .buttonStyle(NexusPillStyle(compact: true))
            }
            notificationButton
        }
        .frame(height: 58)
    }

    private var search: some View {
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
        .frame(minWidth: 0, maxWidth: 210)
        .frame(height: 34)
        .background(palette.input, in: Capsule())
        .overlay { Capsule().strokeBorder(palette.line) }
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
                    .background(palette.fill, in: RoundedRectangle(cornerRadius: 15))
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
