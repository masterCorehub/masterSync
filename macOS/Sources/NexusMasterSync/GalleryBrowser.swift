import AppKit
import NexusCore
import SwiftUI

struct GalleryBrowser: View {
    @ObservedObject var gallery: GalleryModel
    @ObservedObject var files: FileTransfers
    let canTransfer: Bool
    @Binding var grouping: LibraryDateGrouping
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var scheme

    private var palette: NexusPalette { NexusPalette(scheme: scheme) }
    private var effectiveGrouping: LibraryDateGrouping { gallery.filters.order == .name ? .none : grouping }
    private let columns = [GridItem(.adaptive(minimum: 171), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                mediaFilter("Tudo", icon: "square.grid.2x2", value: "")
                mediaFilter("Fotos", icon: "photo", value: "image")
                mediaFilter("Vídeos", icon: "play.rectangle", value: "video")
                Spacer(minLength: 8)
                Picker("Álbum", selection: $gallery.filters.album) {
                    Text("Todos os álbuns").tag("")
                    ForEach(gallery.albums) { Text($0.name).tag($0.id) }
                }
                .frame(maxWidth: 235)
                Button { gallery.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(NexusPillStyle(compact: true))
                    .accessibilityLabel("Atualizar galeria").help("Atualizar galeria")
            }

            if gallery.advanced {
                HStack {
                    Picker("Adicionado em", selection: $gallery.filters.period) {
                        ForEach(GalleryModel.Filters.Period.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Ordenar", selection: $gallery.filters.order) {
                        ForEach(GalleryModel.Filters.Order.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    LibraryDatePicker(selection: $grouping)
                        .disabled(gallery.filters.order == .name)
                        .help("Para agrupar por data, ordene pelos mais recentes ou mais antigos.")
                }
                if gallery.filters.period == .custom {
                    HStack {
                        DatePicker("De", selection: $gallery.filters.start, in: ...gallery.filters.end, displayedComponents: .date)
                        DatePicker("Até", selection: $gallery.filters.end, in: gallery.filters.start..., displayedComponents: .date)
                    }
                }
                if gallery.backgroundConnection {
                    Label("Conexão em segundo plano ativa no Android", systemImage: "iphone")
                        .font(.caption).foregroundStyle(palette.muted)
                } else {
                    Text("Para continuar com a tela bloqueada, ative Manter conexão em segundo plano no Android.")
                        .font(.caption).foregroundStyle(palette.muted)
                }
            } else {
                LibraryDatePicker(selection: $grouping)
                Text("Atualize o Nexus no Android para buscar por nome, filtrar por data e abrir os itens aqui.")
                    .font(.caption).foregroundStyle(palette.muted)
            }

            if gallery.loading { ProgressView("Buscando mídia…").controlSize(.small) }
            if let feedback = gallery.feedback { Text(feedback).foregroundStyle(.secondary) }
            if gallery.items.isEmpty && !gallery.loading && gallery.feedback == nil {
                Text("Nenhuma foto ou vídeo corresponde aos filtros.").foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                if effectiveGrouping == .none {
                    ForEach(gallery.items) { item in mediaCell(item) }
                } else {
                    ForEach(dateSections) { group in
                        SwiftUI.Section {
                            ForEach(group.items) { item in mediaCell(item) }
                        } header: {
                            LibraryDateHeading(date: group.date, grouping: effectiveGrouping)
                        }
                    }
                }
            }
            if gallery.more {
                Button("Mais itens") { gallery.page() }
                    .buttonStyle(NexusPillStyle(compact: true)).disabled(gallery.loading)
            }
        }
        .onAppear { gallery.loadIfNeeded() }
        .onChange(of: gallery.filters) { gallery.filtersChanged() }
        .sheet(isPresented: Binding(get: { gallery.preview != nil }, set: { if !$0 { gallery.preview = nil } })) {
            GalleryPreviewSheet(gallery: gallery, files: files, canTransfer: canTransfer)
        }
    }

    private var dateSections: [LibraryDateSection<MediaEntry>] {
        effectiveGrouping.sections(for: gallery.items, oldestFirst: gallery.filters.order == .oldest, calendar: calendar) { item in
            guard (1...253_402_300_799).contains(item.at) else { return nil }
            return Date(timeIntervalSince1970: Double(item.at))
        }
    }

    private func mediaFilter(_ title: String, icon: String, value: String) -> some View {
        let selected = gallery.filters.mediaType == value
        return Button { gallery.filters.mediaType = value } label: {
            Label(title, systemImage: icon).fixedSize()
        }
        .buttonStyle(NexusPillStyle(selected: selected, compact: true))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func mediaCell(_ item: MediaEntry) -> some View {
        let isPhoto = item.mime.hasPrefix("image/")
        let canOpen = gallery.advanced && (isPhoto || canTransfer || gallery.hasOriginal(item))
        return VStack(alignment: .leading, spacing: 6) {
            Button { gallery.open(item) } label: {
                thumbnail(item, isPhoto: isPhoto)
            }
            .buttonStyle(.plain).disabled(!canOpen)
            .accessibilityLabel("Abrir \(item.name) no Mac")
            Text(item.name).lineLimit(1).font(.subheadline.weight(.medium)).help(item.name)
            if effectiveGrouping != .day, (1...253_402_300_799).contains(item.at) {
                Text(Date(timeIntervalSince1970: Double(item.at)), style: .date)
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                if gallery.advanced {
                    Button("Abrir") { gallery.open(item) }
                        .buttonStyle(NexusPillStyle(compact: true)).disabled(!canOpen)
                        .help(canOpen ? "Abrir no Mac" : "Ative Arquivos nos dois dispositivos para abrir vídeos.")
                }
                Spacer(minLength: 0)
                Button { gallery.download(item) } label: { Image(systemName: "arrow.down.to.line") }
                    .buttonStyle(NexusPillStyle(compact: true))
                    .disabled(!canTransfer || gallery.hasOriginal(item))
                    .help("Baixar original").accessibilityLabel("Baixar original de \(item.name)")
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .nexusPanel(palette, radius: 16)
    }

    private func thumbnail(_ item: MediaEntry, isPhoto: Bool) -> some View {
        GeometryReader { canvas in
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(palette.accentSurface)
                if let image = gallery.thumbnails[item.id] {
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: canvas.size.width, height: canvas.size.height)
                }
                if !isPhoto || gallery.thumbnails[item.id] == nil {
                    Image(systemName: isPhoto ? "photo" : "play.circle.fill").font(.title2)
                        .foregroundStyle(gallery.thumbnails[item.id] == nil ? palette.accent : .white)
                        .shadow(color: .black.opacity(0.35), radius: 4)
                }
            }
        }.frame(height: 109).clipShape(RoundedRectangle(cornerRadius: 9))
            .onAppear { gallery.thumbnail(item.id) }
            .accessibilityHidden(true)
    }

}

private struct GalleryPreviewSheet: View {
    @ObservedObject var gallery: GalleryModel
    @ObservedObject var files: FileTransfers
    let canTransfer: Bool

    var body: some View {
        if let current = gallery.preview { mediaPreview(current) }
    }

    private func mediaPreview(_ current: GalleryModel.Preview) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading) {
                    Text(current.item.name).font(.headline).lineLimit(1)
                    Text(current.item.album).foregroundStyle(.secondary).font(.caption)
                }
                Spacer()
                Button("Fechar") { gallery.preview = nil }.keyboardShortcut(.cancelAction)
            }
            switch current.content {
            case .image(let image):
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(current.item.name)
                Button("Baixar e abrir original") { gallery.download(current.item, open: true) }
                    .disabled(!canTransfer)
            case .original(let url):
                FilePreview(url: url)
                Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            case .loading:
                VStack(spacing: 10) {
                    if current.fromTransfer, let progress = files.progress.first(where: { $0.id == current.id }) {
                        ProgressView(value: progress.fraction) {
                            Text(progress.verifying ? "Verificando o arquivo…" : "Recebendo o original…")
                        }
                        .frame(maxWidth: 300)
                    } else {
                        ProgressView(current.fromTransfer ? "Preparando o original no Android…" : "Buscando a prévia…")
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let reason):
                VStack(spacing: 10) {
                    Label(reason, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
                    if canTransfer && !current.fromTransfer {
                        Button("Baixar e abrir original") { gallery.download(current.item, open: true) }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.padding(16).frame(minWidth: 570, minHeight: 435, idealHeight: 530)
    }
}
