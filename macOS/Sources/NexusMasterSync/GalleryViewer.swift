import AppKit
import NexusCore
import SwiftUI

/// The dark viewer for one photo or video: the picture with arrows, and a side panel with details and actions.
struct GalleryViewer: View {
    @ObservedObject var gallery: GalleryModel
    @ObservedObject var files: FileTransfers
    let canTransfer: Bool
    /// The list the arrows move through (what the grid shows now).
    let items: [MediaEntry]
    let isFavorite: (MediaEntry) -> Bool
    let toggleFavorite: (MediaEntry) -> Void
    @Environment(\.colorScheme) private var scheme

    // The viewer is dark in both appearances, like the design's lightbox.
    private let ink = Color(red: 0.95, green: 0.96, blue: 0.97)
    private let muted = Color(red: 0.95, green: 0.96, blue: 0.97).opacity(0.62)
    private let fill = NexusPalette(scheme: .dark).fill

    var body: some View {
        if let current = gallery.preview {
            HStack(spacing: 0) {
                stage(current)
                details(current)
            }
            .frame(minWidth: 860, idealWidth: 980, minHeight: 540, idealHeight: 640)
            .background(Color(red: 0.063, green: 0.07, blue: 0.086))
            .foregroundStyle(ink)
            .focusable()
            .onKeyPress(.leftArrow) { move(-1, from: current); return .handled }
            .onKeyPress(.rightArrow) { move(1, from: current); return .handled }
        }
    }

    private func move(_ step: Int, from current: GalleryModel.Preview) {
        if let next = GalleryNavigation.neighbour(of: current.item.id, in: items, step: step) { gallery.open(next) }
    }

    // MARK: Stage

    private func stage(_ current: GalleryModel.Preview) -> some View {
        ZStack {
            content(current).padding(.horizontal, 64).padding(.vertical, 56)
            HStack {
                arrow("chevron.left", "Foto anterior", enabled: GalleryNavigation.neighbour(of: current.item.id, in: items, step: -1) != nil) {
                    move(-1, from: current)
                }
                Spacer()
                arrow("chevron.right", "Próxima foto", enabled: GalleryNavigation.neighbour(of: current.item.id, in: items, step: 1) != nil) {
                    move(1, from: current)
                }
            }.padding(.horizontal, 14)
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 12) {
                Button { gallery.preview = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).frame(width: 32, height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain).keyboardShortcut(.cancelAction).accessibilityLabel("Fechar")
                Text(current.item.name).font(.system(size: 13.5, weight: .semibold, design: .monospaced)).lineLimit(1)
                if let position = GalleryNavigation.position(of: current.item.id, in: items) {
                    Text(position).font(.system(size: 12.5)).foregroundStyle(muted)
                }
            }
            .padding(.leading, 16).padding(.top, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func arrow(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                .frame(width: 40, height: 40).background(.white.opacity(0.12), in: Circle()).contentShape(Circle())
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.25).accessibilityLabel(label)
    }

    @ViewBuilder private func content(_ current: GalleryModel.Preview) -> some View {
        switch current.content {
        case .image(let image):
            Image(nsImage: image).resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel(current.item.name)
        case .original(let url):
            FilePreview(url: url).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .loading:
            VStack(spacing: 10) {
                if current.fromTransfer, let progress = files.progress.first(where: { $0.id == current.id }) {
                    ProgressView(value: progress.fraction) {
                        Text(progress.verifying ? "Verificando o arquivo…" : "Recebendo o original…")
                    }.frame(maxWidth: 300)
                } else {
                    ProgressView(current.fromTransfer ? "Preparando o original no Android…" : "Buscando a prévia…")
                }
            }.tint(fill)
        case .failed(let reason):
            Label(reason, systemImage: "exclamationmark.circle").foregroundStyle(muted)
        }
    }

    // MARK: Details

    private func details(_ current: GalleryModel.Preview) -> some View {
        let item = current.item
        let date = (1...253_402_300_799).contains(item.at) ? Date(timeIntervalSince1970: Double(item.at)) : nil
        let favorite = isFavorite(item)
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(date.map { $0.formatted(.dateTime.locale(Locale(identifier: "pt_BR")).day().month(.abbreviated)) } ?? "Sem data")
                    .font(.system(size: 17, weight: .bold))
                if let date {
                    Text(date.formatted(.dateTime.locale(Locale(identifier: "pt_BR")).hour().minute()))
                        .font(.system(size: 12.5)).foregroundStyle(muted)
                }
            }
            VStack(spacing: 0) {
                row("Tamanho", GalleryFormat.size(item.size))
                row("Tipo", item.mime)
                row("Álbum", item.album.isEmpty ? "—" : item.album)
            }
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                primary(current)
                HStack(spacing: 8) {
                    secondary("Copiar", "doc.on.doc", enabled: copyable(current)) { copy(current) }
                    secondary(favorite ? "Favorita" : "Favoritar", favorite ? "heart.fill" : "heart", enabled: true) { toggleFavorite(item) }
                }
            }
        }
        .padding(20)
        .frame(width: 320)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.white.opacity(0.04))
        .overlay(alignment: .leading) { Rectangle().fill(.white.opacity(0.08)).frame(width: 1) }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(muted)
            Spacer()
            Text(value).fontWeight(.medium).lineLimit(1)
        }
        .font(.system(size: 13)).padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
    }

    @ViewBuilder private func primary(_ current: GalleryModel.Preview) -> some View {
        if case .original(let url) = current.content {
            actionButton("Mostrar no Finder", "folder", prominent: true, enabled: true) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        } else {
            actionButton("Salvar no Mac", "arrow.down.to.line", prominent: true, enabled: canTransfer && !current.fromTransfer) {
                gallery.download(current.item, open: true)
            }
        }
    }

    private func secondary(_ title: String, _ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        actionButton(title, symbol, prominent: false, enabled: enabled, action: action)
    }

    private func actionButton(_ title: String, _ symbol: String, prominent: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(prominent ? Color(red: 0.024, green: 0.075, blue: 0.05) : ink)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(prominent ? fill : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.45)
    }

    private func copyable(_ current: GalleryModel.Preview) -> Bool {
        switch current.content {
        case .image, .original: true
        default: false
        }
    }

    private func copy(_ current: GalleryModel.Preview) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch current.content {
        case .image(let image): pasteboard.writeObjects([image])
        case .original(let url): pasteboard.writeObjects([url as NSURL])
        default: break
        }
    }
}
