import AppKit
import NexusCore
import SwiftUI

/// The player of the phone's music or video: cover, track details, controls, progress and where the sound comes out.
struct MediaPlayerCard: View {
    let state: MediaPlayerState?
    let art: NSImage?
    let queue: [MediaQueueItem]
    let queueActive: Int64?
    let output: MediaOutput
    let connecting: Bool
    let canControl: Bool
    let canChooseOutput: Bool
    let palette: NexusPalette
    let onCommand: (String) -> Void
    let onSeek: (Double) -> Void
    let onLike: (Bool) -> Void
    let onOpenQueue: () -> Void
    let onPick: (MediaQueueItem) -> Void
    let onOutput: (MediaOutput) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var showingQueue = false
    @State private var scrubbing: Double?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(palette.border.opacity(0.6))
            controls
        }
        .background { background }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(palette.border.opacity(0.7)) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Player de mídia do Android")
    }

    /// Glass over the app's warm backdrop; a plain surface when the system asks for less transparency.
    @ViewBuilder private var background: some View {
        if reduceTransparency {
            palette.surface
        } else {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                palette.accentSurface.opacity(0.18)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            cover
            VStack(alignment: .leading, spacing: 4) {
                if let state {
                    Text(state.title ?? "Sem título").font(.title3.weight(.bold)).lineLimit(2)
                    if let artist = state.artist { detail("Artista", artist) }
                    if let album = state.album { detail("Álbum", album) }
                    if state.year != nil || state.trackLine != nil {
                        HStack(spacing: 6) {
                            if let year = state.year { detail("Ano", String(year)) }
                            if state.year != nil && state.trackLine != nil { Text("·").foregroundStyle(palette.muted) }
                            if let line = state.trackLine { Text(line).foregroundStyle(palette.muted) }
                        }.font(.callout)
                    }
                } else {
                    Text("Nada tocando no Android").font(.title3.weight(.semibold)).foregroundStyle(palette.muted)
                    Text("Abra um app de música ou vídeo no celular.").font(.callout).foregroundStyle(palette.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let state, state.canLike {
                Button { onLike(!state.liked) } label: {
                    Image(systemName: state.liked ? "heart.fill" : "heart").font(.title3)
                        .foregroundStyle(state.liked ? palette.accent : palette.muted)
                }
                .buttonStyle(.plain).disabled(!canControl)
                .help(state.liked ? "Remover dos favoritos" : "Favoritar")
                .accessibilityLabel(state.liked ? "Remover dos favoritos" : "Favoritar")
            }
        }
        .padding(20)
    }

    private var cover: some View {
        Group {
            if let art {
                Image(nsImage: art).resizable().scaledToFill()
            } else {
                ZStack {
                    palette.accentSurface
                    Image(systemName: state == nil ? "music.note.slash" : "music.note")
                        .font(.title).foregroundStyle(palette.accent)
                }
            }
        }
        .frame(width: 84, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityHidden(true)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        (Text(label + ": ").fontWeight(.semibold) + Text(value))
            .font(.callout).foregroundStyle(palette.muted).lineLimit(1)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 14) {
            outputPicker
            if let state {
                transport(state)
                progress(state)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
    }

    private var outputPicker: some View {
        HStack(spacing: 10) {
            Text("Saída").font(.caption.weight(.semibold)).foregroundStyle(palette.muted)
            HStack(spacing: 2) {
                outputButton("Celular", icon: "iphone", target: .phone)
                outputButton("Mac", icon: "laptopcomputer", target: .mac)
            }
            .padding(3)
            .background(palette.control.opacity(0.55), in: Capsule())
            if connecting { ProgressView().controlSize(.small) }
        }
        .frame(maxWidth: .infinity)
    }

    private func outputButton(_ title: String, icon: String, target: MediaOutput) -> some View {
        Button { if output != target { onOutput(target) } } label: { Label(title, systemImage: icon) }
            .buttonStyle(NexusPillStyle(selected: output == target, compact: true, segmented: true))
            .disabled(connecting || !canChooseOutput)
            .accessibilityAddTraits(output == target ? .isSelected : [])
            .help(target == .mac ? "Ouvir o áudio do celular no Mac" : "Ouvir no celular")
    }

    private func transport(_ state: MediaPlayerState) -> some View {
        HStack(spacing: 26) {
            transportButton("backward.end.fill", "Anterior") { onCommand("previous") }
            let playing = state.playing == true
            Button { onCommand(playing ? "pause" : "play") } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill").font(.title3)
                    .foregroundStyle(palette.accentInk).frame(width: 46, height: 46)
                    .background(palette.accent, in: Circle())
            }
            .buttonStyle(.plain).disabled(!canControl)
            .help(playing ? "Pausar" : "Reproduzir").accessibilityLabel(playing ? "Pausar" : "Reproduzir")
            transportButton("forward.end.fill", "Próxima") { onCommand("next") }
            if state.hasQueue {
                Button { onOpenQueue(); showingQueue.toggle() } label: { Image(systemName: "list.bullet").font(.title3) }
                    .buttonStyle(.plain).disabled(!canControl)
                    .help("Fila").accessibilityLabel("Fila")
                    .popover(isPresented: $showingQueue, arrowEdge: .bottom) { queueList }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func transportButton(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.title3) }
            .buttonStyle(.plain).disabled(!canControl)
            .help(title).accessibilityLabel(title)
    }

    @ViewBuilder private func progress(_ state: MediaPlayerState) -> some View {
        if let duration = state.durationMs {
            TimelineView(.periodic(from: state.receivedAt, by: state.playing == true ? 0.5 : 60)) { context in
                let now = state.fraction(at: context.date)
                HStack(spacing: 10) {
                    Text(MediaPlayerState.clock(scrubbing.map { MediaPlayerState.seekTarget(fraction: $0, durationMs: duration) }
                                                ?? state.position(at: context.date)))
                        .monospacedDigit()
                    if state.canSeek && canControl {
                        Slider(value: Binding(get: { scrubbing ?? now }, set: { scrubbing = $0 }), in: 0...1) { editing in
                            if !editing, let target = scrubbing {
                                onSeek(target)
                                // Keep the thumb where it was dropped until the next status arrives.
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { scrubbing = nil }
                            }
                        }
                        .tint(palette.accent)
                        .accessibilityLabel("Posição da faixa")
                    } else {
                        ProgressView(value: now).tint(palette.accent)
                    }
                    Text(MediaPlayerState.clock(duration)).monospacedDigit()
                }
                .font(.callout).foregroundStyle(palette.muted)
            }
        }
    }

    private var queueList: some View {
        VStack(alignment: .leading, spacing: 2) {
            if queue.isEmpty {
                Text("Carregando a fila…").foregroundStyle(palette.muted).padding(8)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(queue) { item in
                            Button { onPick(item); showingQueue = false } label: {
                                HStack {
                                    Image(systemName: item.id == queueActive ? "speaker.wave.2.fill" : "music.note")
                                        .frame(width: 18).foregroundStyle(palette.accent)
                                    Text(item.title.isEmpty ? "Sem título" : item.title).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 5).padding(.horizontal, 8).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .frame(width: 280).padding(6)
    }
}
