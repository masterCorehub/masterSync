import AppKit
import SwiftUI

/// Opens when a scanned page arrives: the page, and what to do with it.
struct ScanModal: View {
    let file: ReceivedFile
    let canSend: Bool
    let onSend: () -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var feedback: String?
    @State private var confirmingDelete = false

    private var palette: NexusPalette { NexusPalette(scheme: scheme) }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                IconBadge(systemName: "doc.viewfinder", size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Digitalização recebida").font(.system(size: 15, weight: .bold))
                    Text(file.offer.name).font(.system(size: 12)).foregroundStyle(palette.muted).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain).keyboardShortcut(.cancelAction).accessibilityLabel("Fechar")
            }
            page
            if let feedback {
                Text(feedback).font(.system(size: 12.5)).foregroundStyle(palette.accent).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                Button(action: save) { Label("Salvar", systemImage: "arrow.down.to.line") }
                    .buttonStyle(NexusPillStyle(prominent: true))
                Button(action: copy) { Label("Copiar", systemImage: "doc.on.doc") }
                    .buttonStyle(NexusPillStyle())
                Button { onSend(); dismiss() } label: { Label("Enviar na conversa", systemImage: "paperplane") }
                    .buttonStyle(NexusPillStyle()).disabled(!canSend)
                    .help(canSend ? "Envia a página ao celular, na conversa" : "Ative Arquivos nos dois dispositivos para enviar.")
                Spacer(minLength: 0)
                Button(role: .destructive) { confirmingDelete = true } label: { Label("Excluir", systemImage: "trash") }
                    .buttonStyle(NexusPillStyle())
            }
        }
        .padding(20)
        .frame(width: 560)
        .background(palette.canvas)
        .foregroundStyle(palette.ink)
        .confirmationDialog("Mover a digitalização para o Lixo?", isPresented: $confirmingDelete) {
            Button("Mover para o Lixo", role: .destructive) { onDelete(); dismiss() }
            Button("Cancelar", role: .cancel) {}
        } message: { Text(file.offer.name) }
    }

    @ViewBuilder private var page: some View {
        Group {
            if let image = NSImage(contentsOf: file.url) {
                Image(nsImage: image).resizable().scaledToFit().accessibilityLabel("Prévia de \(file.offer.name)")
            } else {
                Label("A página não está mais no Mac.", systemImage: "exclamationmark.circle").foregroundStyle(palette.muted)
            }
        }
        .frame(maxWidth: .infinity).frame(height: 380)
        .background(palette.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func save() {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
        do {
            let saved = try ScanActions.save(file.url, to: downloads)
            feedback = "Salva em Downloads como “\(saved.lastPathComponent)”."
            NSWorkspace.shared.activateFileViewerSelecting([saved])
        } catch {
            feedback = "Não foi possível salvar: \(error.localizedDescription)"
        }
    }

    private func copy() {
        feedback = ScanActions.copy(file.url) ? "Copiada. É só colar." : "Não foi possível copiar a página."
    }
}
