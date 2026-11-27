import AppKit
import NexusCore
import SwiftUI

/// Arquivos: send to the phone, the transfers list, the phone's internal storage, and where things are saved.
struct FilesScreen: View {
    enum Tab { case transfers, pixel }

    @ObservedObject var model: NexusModel
    @ObservedObject var files: FileTransfers
    @ObservedObject var pixel: PixelFilesModel
    let chooseFiles: () -> Void
    @State private var tab: Tab
    /// Lets snapshot tests show the phone's folders without a phone; nil in the app.
    private let pixelAvailableOverride: Bool?
    @State private var filter = TransferFilter.all
    @State private var width: CGFloat = 0
    @State private var targetingDrop = false
    @Environment(\.colorScheme) private var scheme

    init(model: NexusModel, files: FileTransfers, pixel: PixelFilesModel, chooseFiles: @escaping () -> Void,
         initialTab: Tab = .transfers, pixelAvailable: Bool? = nil) {
        self.model = model
        self.files = files
        self.pixel = pixel
        self.chooseFiles = chooseFiles
        _tab = State(initialValue: initialTab)
        pixelAvailableOverride = pixelAvailable
    }

    private var palette: NexusPalette { NexusPalette(scheme: scheme) }
    private var sideBySide: Bool { width >= 760 }
    private var phoneName: String { model.selected?.name ?? "celular" }

    var body: some View {
        let layout = sideBySide ? AnyLayout(HStackLayout(alignment: .top, spacing: 16)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
        return VStack(alignment: .leading, spacing: 0) {
            WidthProbe(width: $width)
            layout {
                VStack(alignment: .leading, spacing: 16) {
                    dropZone
                    tabBar
                    if tab == .transfers { transfers } else { pixelFiles }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                side.frame(width: sideBySide ? 300 : nil)
            }
        }
        .modifier(FileDropModifier(accept: model.canSendFiles ? { model.sendItems($0) } : nil, targeting: $targetingDrop))
        .task(id: pixelReady) { if pixelReady { await loadPixel() } }
    }

    private var pixelReady: Bool { pixelAvailableOverride ?? model.pixelFilesAvailable }

    private func loadPixel() async {
        if pixel.entries.isEmpty { await pixel.open(pixel.path) }
        if pixel.storage == nil { await pixel.loadOverview() }
    }

    // MARK: Drop zone

    private var dropZone: some View {
        HStack(spacing: 14) {
            IconBadge(systemName: "arrow.up.doc", size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text("Arraste arquivos ou pastas para enviar ao \(phoneName)").font(.system(size: 14, weight: .semibold))
                Text(model.canSendFiles ? "Chegam em Download/MasterSync · pastas viram .zip"
                     : (model.active ? "Ative Arquivos nos dois dispositivos para enviar." : "Conecte o celular para enviar."))
                    .font(.system(size: 12)).foregroundStyle(palette.muted)
            }
            Spacer(minLength: 8)
            Button { pasteFiles() } label: { Label("Colar", systemImage: "list.clipboard") }
                .buttonStyle(NexusPillStyle(compact: true)).disabled(!model.canSendFiles)
                .help("Envia os arquivos que você copiou no Finder")
            Button(action: chooseFiles) { Label("Escolher", systemImage: "plus") }
                .buttonStyle(NexusPillStyle(prominent: true, compact: true)).disabled(!model.canSendFiles)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(targetingDrop ? palette.accentSurface : palette.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(targetingDrop ? palette.accent : palette.faint, style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
        }
        .opacity(model.canSendFiles ? 1 : 0.6)
    }

    private func pasteFiles() {
        let urls = (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if urls.isEmpty { model.actionFeedback = "Copie arquivos no Finder (⌘C) e use Colar." } else { model.sendItems(urls) }
    }

    // MARK: Tabs

    private var tabBar: some View {
        ViewThatFits(in: .horizontal) {
            tabBarRow
            VStack(alignment: .leading, spacing: 10) { tabsOnly; if tab == .transfers { filtersOnly } }
        }
    }

    private var tabBarRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                tabButton("Transferências", icon: "arrow.up.arrow.down", .transfers)
                tabButton("Arquivos do Pixel", icon: "folder", .pixel)
            }
            .padding(4)
            .background(palette.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.line) }
            Spacer(minLength: 8)
            if tab == .transfers {
                HStack(spacing: 2) {
                    ForEach(TransferFilter.allCases, id: \.self) { item in
                        Button { filter = item } label: {
                            Text(item.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).fixedSize()
                                .padding(.horizontal, 11).padding(.vertical, 6)
                                .background(filter == item ? palette.active : .clear, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain).accessibilityAddTraits(filter == item ? .isSelected : [])
                    }
                }
                if filter != .received && !files.sent.isEmpty {
                    Button("Limpar concluídas") { files.clearSent() }
                        .buttonStyle(.plain).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(palette.accent).lineLimit(1).fixedSize()
                        .help("Limpa o histórico de enviados; os arquivos não são apagados")
                }
            }
        }
    }

    private var tabsOnly: some View {
        HStack(spacing: 2) {
                tabButton("Transferências", icon: "arrow.up.arrow.down", .transfers)
                tabButton("Arquivos do Pixel", icon: "folder", .pixel)
            }
            .padding(4)
            .background(palette.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.line) }
    }

    private var filtersOnly: some View {
        HStack(spacing: 12) {
                HStack(spacing: 2) {
                    ForEach(TransferFilter.allCases, id: \.self) { item in
                        Button { filter = item } label: {
                            Text(item.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).fixedSize()
                                .padding(.horizontal, 11).padding(.vertical, 6)
                                .background(filter == item ? palette.active : .clear, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain).accessibilityAddTraits(filter == item ? .isSelected : [])
                    }
                }
                if filter != .received && !files.sent.isEmpty {
                    Button("Limpar concluídas") { files.clearSent() }
                        .buttonStyle(.plain).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(palette.accent).lineLimit(1).fixedSize()
                        .help("Limpa o histórico de enviados; os arquivos não são apagados")
                }
        }
    }

    private func tabButton(_ title: String, icon: String, _ value: Tab) -> some View {
        let selected = tab == value
        return Button { tab = value } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12))
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .fixedSize().padding(.horizontal, 12).padding(.vertical, 8)
            .background(selected ? palette.active : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Transfers

    private var rows: [TransferRow] {
        TransferRows.make(progress: files.progress, sent: files.sent, received: files.received,
                          peerNames: Dictionary(uniqueKeysWithValues: model.peers.map { ($0.id, $0.name) }), filter: filter)
    }

    @ViewBuilder private var transfers: some View {
        if let feedback = files.feedback ?? model.actionFeedback { Text(feedback).font(.system(size: 12.5)).foregroundStyle(palette.muted) }
        let items = rows
        if items.isEmpty {
            Text(filter == .all ? "Nenhuma transferência ainda." : "Nada por aqui.")
                .font(.system(size: 13)).foregroundStyle(palette.muted).frame(maxWidth: .infinity).padding(36)
                .glassPanel(radius: 20)
        } else {
            VStack(spacing: 0) {
                ForEach(items) { row in
                    transferRow(row)
                        .overlay(alignment: .bottom) { if row.id != items.last?.id { Rectangle().fill(palette.line).frame(height: 1) } }
                }
            }
            .padding(.horizontal, 16).glassPanel(radius: 20)
        }
    }

    private func transferRow(_ row: TransferRow) -> some View {
        let sent = row.direction == .sent
        let exists = row.url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        return HStack(spacing: 12) {
            Image(systemName: sent ? "arrow.up.right" : "arrow.down.left").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.accent)
                .frame(width: 36, height: 36).background(palette.panel2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(row.name).font(.system(size: 13.5, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(row.fraction.map { row.verifying ? "Verificando…" : "\(Int($0 * 100))%" }
                         ?? "\(sent ? "Enviado" : "Recebido") · \(TransferRows.sizeText(row.size))")
                        .font(.system(size: 12).monospacedDigit()).foregroundStyle(palette.muted)
                }
                if let fraction = row.fraction {
                    ProgressView(value: fraction).progressViewStyle(.linear).tint(palette.fill)
                } else {
                    Text([row.date.map { $0.formatted(date: .omitted, time: .shortened) }, row.deviceName,
                          sent ? "Download/MasterSync" : "Pasta do MasterSync"].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11.5)).foregroundStyle(palette.faint).lineLimit(1)
                }
            }
            if let url = row.url {
                HStack(spacing: 2) {
                    rowAction("arrow.up.forward.square", "Abrir", enabled: exists) { NSWorkspace.shared.open(url) }
                    rowAction("folder", "Mostrar no Finder", enabled: exists) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    if sent { rowAction("arrow.counterclockwise", "Enviar de novo", enabled: exists && model.canSendFiles) { model.sendItems([url]) } }
                    rowAction("xmark", sent ? "Tirar da lista" : "Mover para o Lixo", enabled: true) {
                        if sent { files.removeSent(row.fileID) } else { files.trashReceived(row.fileID) }
                    }
                }
            }
        }
        .padding(.vertical, 12)
    }

    private func rowAction(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(palette.muted)
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.35).accessibilityLabel(label).help(label)
    }

    // MARK: The phone's storage

    @ViewBuilder private var pixelFiles: some View {
        if !pixelReady {
            VStack(spacing: 12) {
                IconBadge(systemName: "externaldrive.badge.wifi", size: 48)
                Text("Para ver o armazenamento do celular").font(.system(size: 14, weight: .semibold))
                Text("Configure o controle por Wi‑Fi (ADB) na tela Dispositivos. O Mac lê as pastas do celular por essa conexão, sem nuvem.")
                    .font(.system(size: 12.5)).foregroundStyle(palette.muted).multilineTextAlignment(.center).frame(maxWidth: 380)
                Button("Abrir Dispositivos") { model.section = .devices }.buttonStyle(NexusPillStyle(prominent: true, compact: true))
            }
            .padding(32).frame(maxWidth: .infinity).glassPanel(radius: 20)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                breadcrumbs
                if let error = pixel.error { Text(error).font(.system(size: 12.5)).foregroundStyle(palette.muted) }
                if pixel.loading && pixel.entries.isEmpty { ProgressView("Lendo o celular…").controlSize(.small) }
                if pixel.path == PixelPath.root { folderCards } else { fileList }
                if !pixel.selection.isEmpty || pixel.downloading || pixel.downloadMessage != nil { downloadBar }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).glassPanel(radius: 20)
        }
    }

    private var breadcrumbs: some View {
        HStack(spacing: 6) {
            Image(systemName: "iphone").foregroundStyle(palette.muted)
            ForEach(Array(PixelPath.breadcrumbs(pixel.path).enumerated()), id: \.offset) { index, crumb in
                if index > 0 { Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(palette.faint) }
                Button(crumb.title) { Task { await pixel.open(crumb.path) } }
                    .buttonStyle(.plain).font(.system(size: 13, weight: index == PixelPath.breadcrumbs(pixel.path).count - 1 ? .bold : .regular))
            }
            Spacer()
            Button { Task { await pixel.reload(); await pixel.loadOverview() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).foregroundStyle(palette.muted).accessibilityLabel("Atualizar").help("Atualizar")
        }
    }

    private func folderIcon(_ name: String) -> String {
        switch name {
        case "Download": "arrow.down.circle"
        case "DCIM": "camera"
        case "Documents": "doc.text"
        case "Music": "music.note"
        case "Pictures": "photo"
        case "Movies": "film"
        case "Recordings": "mic"
        default: "folder"
        }
    }

    private var folderCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 8)], spacing: 8) {
            ForEach(pixel.entries.filter { $0.isDirectory && $0.name != "Android" }) { entry in
                Button { Task { await pixel.enter(entry) } } label: {
                    HStack(spacing: 10) {
                        IconBadge(systemName: folderIcon(entry.name), size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            Text(pixel.folderCounts[entry.name].map { GalleryFormat.items($0) } ?? " ")
                                .font(.system(size: 11.5)).foregroundStyle(palette.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.line) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(!entry.isSafe)
            }
            ForEach(pixel.entries.filter { !$0.isDirectory }) { fileEntry($0) }
        }
    }

    private var fileList: some View {
        VStack(spacing: 0) {
            if pixel.entries.isEmpty && !pixel.loading && pixel.error == nil {
                Text("Pasta vazia.").font(.system(size: 13)).foregroundStyle(palette.muted).padding(24)
            }
            ForEach(pixel.entries) { entry in
                fileEntry(entry).overlay(alignment: .bottom) { Rectangle().fill(palette.line).frame(height: 1) }
            }
        }
    }

    private func fileEntry(_ entry: PixelListing.Entry) -> some View {
        let picked = pixel.selection.contains(entry.name)
        return HStack(spacing: 10) {
            Button { pixel.toggle(entry) } label: {
                Image(systemName: picked ? "checkmark.circle.fill" : "circle").font(.system(size: 16))
                    .foregroundStyle(picked ? palette.fill : palette.faint)
            }
            .buttonStyle(.plain).disabled(!entry.isSafe).accessibilityLabel(picked ? "Desmarcar \(entry.name)" : "Selecionar \(entry.name)")
            Button { if entry.isDirectory { Task { await pixel.enter(entry) } } else { pixel.toggle(entry) } } label: {
                HStack(spacing: 10) {
                    Image(systemName: entry.isDirectory ? "folder" : "doc").foregroundStyle(palette.accent).frame(width: 20)
                    Text(entry.name).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    if !entry.isDirectory {
                        Text(TransferRows.sizeText(entry.size)).font(.system(size: 12)).foregroundStyle(palette.muted)
                    }
                    if let date = entry.modified {
                        Text(date.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 12)).foregroundStyle(palette.faint)
                    }
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .opacity(entry.isSafe ? 1 : 0.45)
        .help(entry.isSafe ? entry.name : "O nome tem caracteres que o Mac não consegue ler com segurança.")
    }

    private var downloadBar: some View {
        HStack(spacing: 10) {
            Text(pixel.downloadMessage ?? (pixel.selection.count == 1 ? "1 item selecionado" : "\(pixel.selection.count) itens selecionados"))
                .font(.system(size: 12.5, weight: .semibold)).lineLimit(2)
            Spacer()
            if pixel.downloading { ProgressView().controlSize(.small) }
            if !pixel.lastDownloaded.isEmpty {
                Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting(pixel.lastDownloaded) }
                    .buttonStyle(NexusPillStyle(compact: true))
            }
            if !pixel.selection.isEmpty {
                Button { Task { await pixel.downloadSelection() } } label: { Label("Baixar", systemImage: "arrow.down.to.line") }
                    .buttonStyle(NexusPillStyle(prominent: true, compact: true)).disabled(pixel.downloading)
                Button { pixel.clearSelection() } label: { Image(systemName: "xmark") }
                    .buttonStyle(NexusPillStyle(compact: true)).accessibilityLabel("Limpar seleção")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(palette.accentSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Side column

    private var side: some View {
        VStack(alignment: .leading, spacing: 16) {
            storageCard
            savedCard
            optionsCard
        }
    }

    private var segmentColors: [Color] {
        [NexusPalette.oklch(0.7, 0.13, 300), palette.fill, NexusPalette.oklch(0.72, 0.15, 145), NexusPalette.oklch(0.72, 0.14, 55)]
    }

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Armazenamento do \(phoneName)").font(.system(size: 13, weight: .bold)).lineLimit(1)
                Spacer()
                if let storage = pixel.storage {
                    Text("\(PixelStorage.gigabytes(storage.free)) livres").font(.system(size: 12)).foregroundStyle(palette.muted)
                }
            }
            if let storage = pixel.storage {
                GeometryReader { bar in
                    HStack(spacing: 0) {
                        ForEach(Array(pixel.segments.enumerated()), id: \.offset) { index, segment in
                            Rectangle().fill(segmentColors[index % segmentColors.count]).frame(width: bar.size.width * segment.fraction)
                        }
                        Spacer(minLength: 0)
                    }
                    .background(palette.track).clipShape(Capsule())
                }.frame(height: 8)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                    ForEach(Array(pixel.segments.enumerated()), id: \.offset) { index, segment in
                        HStack(spacing: 6) {
                            Circle().fill(segmentColors[index % segmentColors.count]).frame(width: 7, height: 7)
                            Text(segment.title).font(.system(size: 11.5)).foregroundStyle(palette.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 2)
                            Text(PixelStorage.gigabytes(segment.bytes)).font(.system(size: 11.5, weight: .semibold))
                        }
                    }
                }
                Text("\(PixelStorage.gigabytes(storage.used)) usados de \(PixelStorage.gigabytes(storage.total))")
                    .font(.system(size: 11.5)).foregroundStyle(palette.faint)
            } else {
                Text(pixelReady ? "Lendo o armazenamento…" : "Disponível com o controle por Wi‑Fi configurado.")
                    .font(.system(size: 12)).foregroundStyle(palette.muted)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).glassPanel(radius: 20)
    }

    private var savedCard: some View {
        let folder = files.receivedDirectory
        let shown = folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        return VStack(alignment: .leading, spacing: 10) {
            Text("Onde salvar").font(.system(size: 13, weight: .bold))
            locationRow(icon: "laptopcomputer", title: "Recebidos no Mac", path: shown, action: ("Mostrar", { NSWorkspace.shared.open(folder) }))
            locationRow(icon: "iphone", title: "Enviados ao \(phoneName)", path: "Download/MasterSync", action: nil)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).glassPanel(radius: 20)
    }

    private func locationRow(icon: String, title: String, path: String, action: (String, () -> Void)?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(palette.muted).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 11.5)).foregroundStyle(palette.muted)
                Text(path).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if let action { Button(action.0, action: action.1).buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.accent) }
        }
    }

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SwitchRow(title: "Abrir ao receber", subtitle: "Abre o arquivo assim que chega no Mac", isOn: $model.openOnReceive)
            SwitchRow(title: "Compactar pastas", subtitle: "Pastas são enviadas como .zip", isOn: $model.compressFolders, showsDivider: false)
        }
        .padding(.horizontal, 16).padding(.vertical, 4).glassPanel(radius: 20)
    }
}
