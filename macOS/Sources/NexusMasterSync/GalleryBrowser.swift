import AppKit
import NexusCore
import SwiftUI

/// The phone's photos and videos, laid out like the design: tabs, a zoomable grid grouped by day with selection,
/// and a column with albums and loading controls.
struct GalleryBrowser: View {
    @ObservedObject var gallery: GalleryModel
    @ObservedObject var files: FileTransfers
    let canTransfer: Bool
    @Binding var grouping: LibraryDateGrouping
    let deviceID: String
    @AppStorage("media-favorites") private var storedFavorites = Data()
    @AppStorage("gallery-zoom") private var zoomStep = GalleryZoom.standard
    @State private var favoritesOnly = false
    @State private var showFilters = false
    @State private var selection = GallerySelection()
    @State private var width: CGFloat = 0
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var scheme

    private var palette: NexusPalette { NexusPalette(scheme: scheme) }
    private var effectiveGrouping: LibraryDateGrouping { gallery.filters.order == .name ? .none : grouping }
    private var sideBySide: Bool { width >= 760 }
    private var tileMinimum: CGFloat { GalleryZoom.minimumTile[GalleryZoom.clamped(zoomStep)] }
    private var screenshotsAlbumID: String? { GalleryTab.screenshotsAlbumID(in: gallery.albums) }

    private var favorites: [String: [MediaEntry]] {
        (try? JSONDecoder().decode([String: [MediaEntry]].self, from: storedFavorites)) ?? [:]
    }

    private var visibleItems: [MediaEntry] {
        favoritesOnly ? (favorites[deviceID] ?? []).sorted { $0.at > $1.at } : gallery.items
    }

    private var currentTab: GalleryTab {
        GalleryTab.current(mediaType: gallery.filters.mediaType, albumID: gallery.filters.album,
                           screenshotsAlbumID: screenshotsAlbumID, favoritesOnly: favoritesOnly)
    }

    private func isFavorite(_ item: MediaEntry) -> Bool { favorites[deviceID]?.contains { $0.id == item.id } == true }

    private func setFavorite(_ item: MediaEntry, _ on: Bool) {
        var saved = favorites
        var items = saved[deviceID] ?? []
        let present = items.contains { $0.id == item.id }
        if on && !present { items.append(item) }
        if !on && present { items.removeAll { $0.id == item.id } }
        saved[deviceID] = items
        if let data = try? JSONEncoder().encode(saved) { storedFavorites = data }
    }

    private func toggleFavorite(_ item: MediaEntry) { setFavorite(item, !isFavorite(item)) }

    // MARK: Body

    var body: some View {
        let layout = sideBySide ? AnyLayout(HStackLayout(alignment: .top, spacing: 16)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
        return VStack(alignment: .leading, spacing: 0) {
            WidthProbe(width: $width)
            layout {
            VStack(alignment: .leading, spacing: 14) {
                toolbar
                if !selection.isEmpty { selectionBar }
                status
                grid
                if gallery.more && !favoritesOnly {
                    Button("Mais itens") { gallery.page() }
                        .buttonStyle(NexusPillStyle(compact: true)).disabled(gallery.loading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            side.frame(width: sideBySide ? 300 : nil)
            }
        }
        .onAppear { gallery.refresh() }
        // New photos appear on their own: every 20 s while this screen is open, and when the app comes back to the front.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                gallery.refreshIfStale(maxAge: 19)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            gallery.refreshIfStale(maxAge: 5)
        }
        .onChange(of: gallery.filters) { gallery.filtersChanged() }
        .onChange(of: visibleItems.map(\.id)) { _, ids in selection.prune(keeping: Set(ids)) }
        .sheet(isPresented: Binding(get: { gallery.preview != nil }, set: { if !$0 { gallery.preview = nil } })) {
            GalleryViewer(gallery: gallery, files: files, canTransfer: canTransfer, items: visibleItems,
                          isFavorite: isFavorite, toggleFavorite: toggleFavorite)
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            ViewThatFits(in: .horizontal) {
                tabRow
                ScrollView(.horizontal) { tabRow }.scrollIndicators(.hidden)
            }
            .background(palette.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.line) }
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                zoomButton("minus.magnifyingglass", "Fotos menores") { zoomStep = GalleryZoom.clamped(zoomStep - 1) }
                    .disabled(zoomStep <= 0)
                zoomButton("plus.magnifyingglass", "Fotos maiores") { zoomStep = GalleryZoom.clamped(zoomStep + 1) }
                    .disabled(zoomStep >= GalleryZoom.minimumTile.count - 1)
            }
            .padding(4)
            .background(palette.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.line) }
        }
    }

    private var tabRow: some View {
        HStack(spacing: 2) {
            ForEach(GalleryTab.allCases.filter { $0 != .screenshots || screenshotsAlbumID != nil }, id: \.self) { tabButton($0) }
        }
        .padding(4)
    }

    private func tabButton(_ tab: GalleryTab) -> some View {
        let selected = currentTab == tab
        return Button { choose(tab) } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.icon).font(.system(size: 12))
                Text(tab.title).font(.system(size: 13, weight: .semibold))
                if selected {
                    Text(GalleryFormat.tabCount(visibleItems.count, more: gallery.more && !favoritesOnly))
                        .font(.system(size: 12)).foregroundStyle(palette.muted)
                }
            }
            .fixedSize()
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(selected ? palette.active : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(selected ? 0.1 : 0), radius: 4, y: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func choose(_ tab: GalleryTab) {
        favoritesOnly = tab == .favorites
        switch tab {
        case .all: gallery.filters.mediaType = ""; gallery.filters.album = ""
        case .photos: gallery.filters.mediaType = "image"; gallery.filters.album = ""
        case .videos: gallery.filters.mediaType = "video"; gallery.filters.album = ""
        case .screenshots: gallery.filters.mediaType = ""; gallery.filters.album = screenshotsAlbumID ?? ""
        case .favorites: break
        }
    }

    private func zoomButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(palette.ink)
                .frame(width: 32, height: 32).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(label).help(label)
    }

    private var selectionBar: some View {
        let picked = visibleItems.filter { selection.contains($0.id) }
        let allFavorite = !picked.isEmpty && picked.allSatisfy(isFavorite)
        return HStack(spacing: 10) {
            Text(picked.count == 1 ? "1 selecionada" : "\(picked.count) selecionadas")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button {
                for item in picked where !gallery.hasOriginal(item) { gallery.download(item) }
            } label: { Label("Salvar no Mac", systemImage: "arrow.down.to.line") }
                .buttonStyle(NexusPillStyle(prominent: true, compact: true))
                .disabled(!canTransfer || picked.allSatisfy { gallery.hasOriginal($0) })
                .help(canTransfer ? "Baixa os originais" : "Ative Arquivos nos dois dispositivos para baixar.")
            Button { for item in picked { setFavorite(item, !allFavorite) } } label: {
                Label(allFavorite ? "Desfavoritar" : "Favoritar", systemImage: allFavorite ? "heart.slash" : "heart")
            }.buttonStyle(NexusPillStyle(compact: true))
            Button { selection.clear() } label: { Image(systemName: "xmark") }
                .buttonStyle(NexusPillStyle(compact: true)).accessibilityLabel("Limpar seleção")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(palette.accentSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.accent.opacity(0.4)) }
    }

    @ViewBuilder private var status: some View {
        if gallery.loading { ProgressView("Buscando mídia…").controlSize(.small) }
        if let feedback = gallery.feedback { Text(feedback).font(.system(size: 12.5)).foregroundStyle(palette.muted) }
        if visibleItems.isEmpty && (favoritesOnly || (!gallery.loading && gallery.feedback == nil)) {
            Text(favoritesOnly ? "Nenhuma favorita ainda." : "Nenhuma foto ou vídeo corresponde aos filtros.")
                .font(.system(size: 13)).foregroundStyle(palette.muted).padding(.vertical, 20)
        }
    }

    // MARK: Grid

    @ViewBuilder private var grid: some View {
        if effectiveGrouping == .none {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: tileMinimum), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(visibleItems) { tile($0) }
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(dateSections) { group in
                    let ids = group.items.map(\.id)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            heading(group)
                            Spacer()
                            Button(selection.isGroupSelected(ids) ? "Limpar" : "Selecionar") { selection.toggleGroup(ids) }
                                .buttonStyle(.plain).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(palette.accent)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: tileMinimum), spacing: 8)], alignment: .leading, spacing: 8) {
                            ForEach(group.items) { tile($0) }
                        }
                    }
                }
            }
        }
    }

    /// "Hoje 26 nov · 6 itens": the day's name in bold, then the short date and the count.
    @ViewBuilder private func heading(_ group: LibraryDateSection<MediaEntry>) -> some View {
        let count = GalleryFormat.items(group.items.count)
        if effectiveGrouping == .month || group.date == nil {
            LibraryDateHeading(date: group.date, grouping: effectiveGrouping).fixedSize()
            Text(count).font(.system(size: 12.5)).foregroundStyle(palette.muted)
        } else if let date = group.date {
            let heading = GalleryFormat.dayHeading(date, calendar: calendar)
            Text(heading.title).font(.system(size: 15, weight: .bold)).fixedSize()
                .accessibilityAddTraits(.isHeader)
            Text([heading.detail, count].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 12.5)).foregroundStyle(palette.muted)
        }
    }

    private var dateSections: [LibraryDateSection<MediaEntry>] {
        effectiveGrouping.sections(for: visibleItems, oldestFirst: !favoritesOnly && gallery.filters.order == .oldest, calendar: calendar) { item in
            guard (1...253_402_300_799).contains(item.at) else { return nil }
            return Date(timeIntervalSince1970: Double(item.at))
        }
    }

    private func tile(_ item: MediaEntry) -> some View {
        let isPhoto = item.mime.hasPrefix("image/")
        let canOpen = gallery.advanced && (isPhoto || canTransfer || gallery.hasOriginal(item))
        let picked = selection.contains(item.id)
        return Button { gallery.open(item) } label: {
            GeometryReader { canvas in
                ZStack {
                    palette.panel2
                    if let image = gallery.thumbnails[item.id] {
                        Image(nsImage: image).resizable().scaledToFill().frame(width: canvas.size.width, height: canvas.size.height)
                    } else {
                        Image(systemName: isPhoto ? "photo" : "play.circle.fill").font(.title2).foregroundStyle(palette.faint)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                if picked { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.fill, lineWidth: 3) }
            }
            .overlay(alignment: .bottomLeading) {
                if isFavorite(item) { badge("heart.fill") }
            }
            .overlay(alignment: .bottomTrailing) {
                if !isPhoto { badge("play.fill", text: "Vídeo") }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain).disabled(!canOpen)
        .overlay(alignment: .topTrailing) { selectionMark(item, picked: picked) }
        .onAppear { gallery.thumbnail(item.id) }
        .help(canOpen ? item.name : "Ative Arquivos nos dois dispositivos para abrir vídeos.")
        .accessibilityLabel(item.name)
        .contextMenu {
            Button("Abrir") { gallery.open(item) }.disabled(!canOpen)
            Button(isFavorite(item) ? "Remover das favoritas" : "Favoritar") { toggleFavorite(item) }
            Button("Baixar original") { gallery.download(item) }.disabled(!canTransfer || gallery.hasOriginal(item))
        }
    }

    private func selectionMark(_ item: MediaEntry, picked: Bool) -> some View {
        Button { selection.toggle(item.id) } label: {
            ZStack {
                Circle().fill(picked ? palette.fill : Color.black.opacity(0.25))
                Circle().strokeBorder(.white.opacity(picked ? 0 : 0.9), lineWidth: 1.5)
                if picked { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(palette.accentInk) }
            }
            .frame(width: 22, height: 22).padding(8).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(picked ? "Desmarcar \(item.name)" : "Selecionar \(item.name)")
    }

    private func badge(_ symbol: String, text: String? = nil) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold))
            if let text { Text(text).font(.system(size: 11, weight: .semibold)) }
        }
        .foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 4)
        .background(text == nil ? Color.clear : Color.black.opacity(0.55), in: Capsule())
        .shadow(color: .black.opacity(0.4), radius: 3)
        .padding(8)
    }

    // MARK: Side column

    private var side: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Álbuns").font(.system(size: 14, weight: .bold)).padding(.bottom, 8)
                albumRow("Todos os itens", icon: "photo.on.rectangle", selected: gallery.filters.album.isEmpty && !favoritesOnly) {
                    favoritesOnly = false
                    gallery.filters.album = ""
                }
                ForEach(gallery.albums) { album in
                    albumRow(album.name, icon: album.id == screenshotsAlbumID ? "camera.viewfinder" : "folder",
                             selected: gallery.filters.album == album.id && !favoritesOnly) {
                        favoritesOnly = false
                        gallery.filters.album = album.id
                    }
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(radius: 20)
            VStack(alignment: .leading, spacing: 10) {
                Label { Text("Carregamento").font(.system(size: 14, weight: .bold)) } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(palette.accent)
                }
                Text(GalleryFormat.subtitle(count: gallery.items.count, more: gallery.more))
                    .font(.system(size: 12.5)).foregroundStyle(palette.muted)
                HStack(spacing: 8) {
                    Button { gallery.refresh() } label: { Label("Atualizar", systemImage: "arrow.clockwise") }
                        .buttonStyle(NexusPillStyle(compact: true))
                    Button { showFilters.toggle() } label: { Label("Ordenar e filtrar", systemImage: "line.3.horizontal.decrease") }
                        .buttonStyle(NexusPillStyle(compact: true))
                        .popover(isPresented: $showFilters) { filterOptions }
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(radius: 20)
        }
    }

    private func albumRow(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 14)).frame(width: 20).foregroundStyle(selected ? palette.accent : palette.muted)
                Text(title).font(.system(size: 13.5, weight: selected ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(selected ? palette.active : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var filterOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Álbum", selection: $gallery.filters.album) {
                Text("Todos os álbuns").tag("")
                ForEach(gallery.albums) { Text($0.name).tag($0.id) }
            }
            if gallery.advanced {
                Picker("Adicionado em", selection: $gallery.filters.period) {
                    ForEach(GalleryModel.Filters.Period.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("Ordenar", selection: $gallery.filters.order) {
                    ForEach(GalleryModel.Filters.Order.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if gallery.filters.period == .custom {
                    DatePicker("De", selection: $gallery.filters.start, in: ...gallery.filters.end, displayedComponents: .date)
                    DatePicker("Até", selection: $gallery.filters.end, in: gallery.filters.start..., displayedComponents: .date)
                }
            }
            LibraryDatePicker(selection: $grouping).disabled(gallery.filters.order == .name)
        }.padding(16).frame(width: 300)
    }
}
