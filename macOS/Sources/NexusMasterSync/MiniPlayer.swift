import AppKit
import NexusCore
import SwiftUI

enum MiniPlayerView: Equatable { case hidden, mini, full }

/// When the floating player shows. It follows the phone's media session, can be expanded, and stays closed once the user
/// closes it until a different track plays.
struct MiniPlayerPresentation: Equatable {
    var expanded = false
    private(set) var dismissedTrack: String?

    static func trackKey(title: String?, artist: String?) -> String { (title ?? "") + "\u{1F}" + (artist ?? "") }

    func view(hasMedia: Bool, track: String?) -> MiniPlayerView {
        guard hasMedia else { return .hidden }
        if let dismissedTrack, dismissedTrack == track { return .hidden }
        return expanded ? .full : .mini
    }

    mutating func toggleExpanded() { expanded.toggle() }

    mutating func dismiss(track: String?) {
        dismissedTrack = track
        expanded = false
    }
}

/// The floating player in the window's lower right corner: a one-line bar, or the full controls.
struct MiniPlayer: View {
    let state: MediaPlayerState
    let art: NSImage?
    let phoneName: String
    let queue: [MediaQueueItem]
    let queueActive: Int64?
    let output: MediaOutput
    let connecting: Bool
    let canControl: Bool
    let canChooseOutput: Bool
    let expanded: Bool
    /// The Mac's output volume while the sound is on the Mac; nil when unknown or when the sound is on the phone.
    let volume: Double?
    let onVolume: (Double) -> Void
    let onCommand: (String) -> Void
    let onSeek: (Double) -> Void
    let onLike: (Bool) -> Void
    let onOpenQueue: () -> Void
    let onPick: (MediaQueueItem) -> Void
    let onOutput: (MediaOutput) -> Void
    let onToggleExpanded: () -> Void
    let onClose: () -> Void
    /// The most height the player may take, so a low window never pushes its buttons off screen.
    var maxHeight: CGFloat = .infinity

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var scrubbing: Double?
    @State private var scrubGeneration = 0
    @State private var likedOverride: Bool?
    @State private var likeGeneration = 0
    @State private var draggingVolume: Double?

    private var palette: NexusPalette { NexusPalette(scheme: scheme) }
    private var playing: Bool { state.playing == true }
    private var outputIcon: String { output == .mac ? "laptopcomputer" : "iphone" }

    var body: some View {
        VStack(spacing: 0) {
            if expanded { full } else { mini }
        }
        .frame(width: 360)
        .frame(maxHeight: maxHeight)
        .background { background }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(palette.edge) }
        .shadow(color: .black.opacity(0.35), radius: 24, y: 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Player de mídia do Android")
    }

    @ViewBuilder private var background: some View {
        if reduceTransparency {
            palette.canvas
        } else {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                palette.windowTint
            }
        }
    }

    // MARK: Collapsed

    private var mini: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onToggleExpanded) {
                    HStack(spacing: 10) {
                        cover(size: 44, radius: 11)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.title ?? "Sem título").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            HStack(spacing: 4) {
                                Image(systemName: outputIcon).font(.system(size: 10)).foregroundStyle(palette.accent)
                                Text(state.artist ?? "").font(.system(size: 11.5)).foregroundStyle(palette.muted).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("Expandir player")
                playButton(size: 36)
                iconButton("forward.end.fill", "Próxima", size: 32) { onCommand("next") }
                iconButton("chevron.up", "Expandir player", size: 28, muted: true, action: onToggleExpanded)
            }
            .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 12)
            GeometryReader { bar in
                ZStack(alignment: .leading) {
                    Rectangle().fill(palette.track)
                    TimelineView(.periodic(from: state.receivedAt, by: playing ? 1 : 60)) { context in
                        Rectangle().fill(palette.fill).frame(width: bar.size.width * state.fraction(at: context.date))
                    }
                }
            }.frame(height: 3)
        }
    }

    // MARK: Expanded

    private var full: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Recolher and Fechar stay put; only the rest scrolls when the window is short.
            HStack(spacing: 8) {
                Label { Text("\(phoneName)").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(palette.muted) } icon: {
                    Image(systemName: "music.note").font(.system(size: 10)).foregroundStyle(palette.accent)
                }
                Spacer()
                if state.canLike {
                    let liked = likedOverride ?? state.liked
                    iconButton(liked ? "heart.fill" : "heart", liked ? "Remover dos favoritos" : "Favoritar", size: 28,
                               tint: liked ? palette.accent : palette.muted) {
                        likedOverride = !liked
                        likeGeneration += 1
                        let generation = likeGeneration
                        onLike(!liked)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { if likeGeneration == generation { likedOverride = nil } }
                    }
                }
                iconButton("chevron.down", "Recolher player", size: 28, muted: true, action: onToggleExpanded)
                iconButton("xmark", "Fechar player", size: 28, muted: true, action: onClose)
            }
            ViewThatFits(in: .vertical) {
                fullBody
                ScrollView { fullBody }.scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 14)
    }

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                cover(size: 96, radius: 16)
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.title ?? "Sem título").font(.system(size: 16, weight: .bold)).lineLimit(2)
                    if let artist = state.artist { Text(artist).font(.system(size: 12.5)).foregroundStyle(palette.muted).lineLimit(1) }
                    if let album = state.album { Text(album).font(.system(size: 12)).foregroundStyle(palette.faint).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
            progress
            transport
            if output == .mac, let volume { volumeRow(volume) }
            outputPicker
            if state.hasQueue { queueSection }
        }
    }

    @ViewBuilder private var progress: some View {
        if let duration = state.durationMs {
            TimelineView(.periodic(from: state.receivedAt, by: playing ? 0.5 : 60)) { context in
                let now = state.fraction(at: context.date)
                VStack(spacing: 2) {
                    if state.canSeek && canControl {
                        Slider(value: Binding(get: { scrubbing ?? now }, set: { scrubbing = $0 }), in: 0...1) { editing in
                            if editing {
                                scrubGeneration += 1
                            } else if let target = scrubbing {
                                onSeek(target)
                                let generation = scrubGeneration
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { if scrubGeneration == generation { scrubbing = nil } }
                            }
                        }
                        .tint(palette.fill).accessibilityLabel("Posição da faixa")
                    } else {
                        ProgressView(value: now).tint(palette.fill)
                    }
                    HStack {
                        Text(MediaPlayerState.clock(scrubbing.map { MediaPlayerState.seekTarget(fraction: $0, durationMs: duration) }
                                                    ?? state.position(at: context.date)))
                        Spacer()
                        Text(MediaPlayerState.clock(duration))
                    }
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.muted)
                }
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 18) {
            Spacer()
            iconButton("backward.end.fill", "Anterior", size: 40) { onCommand("previous") }
            playButton(size: 52)
            iconButton("forward.end.fill", "Próxima", size: 40) { onCommand("next") }
            Spacer()
        }
    }

    private func volumeRow(_ level: Double) -> some View {
        HStack(spacing: 10) {
            Image(systemName: (draggingVolume ?? level) <= 0 ? "speaker.slash" : "speaker.wave.2")
                .font(.system(size: 14)).foregroundStyle(palette.muted).frame(width: 22)
            Slider(value: Binding(get: { draggingVolume ?? level }, set: { draggingVolume = $0 }), in: 0...100, step: 1) { editing in
                if !editing, let value = draggingVolume { onVolume(value); draggingVolume = nil }
            }
            .tint(palette.fill).accessibilityLabel("Volume no Mac")
            Text("\(Int(draggingVolume ?? level))%").font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.muted).frame(width: 36, alignment: .trailing)
        }
    }

    private var outputPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SOM DO CELULAR").font(.system(size: 10.5, weight: .semibold)).tracking(0.7).foregroundStyle(palette.muted)
            HStack(spacing: 4) {
                segment("No Mac", "laptopcomputer", .mac)
                segment("No celular", "iphone", .phone)
                if connecting { ProgressView().controlSize(.small) }
            }
            .padding(3).background(palette.input, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(!canChooseOutput ? "O áudio está no controle remoto. Encerre-o para trocar a saída."
                 : output == .mac ? "O som do celular sai nos alto-falantes do Mac." : "O som continua saindo no celular.")
                .font(.system(size: 11.5)).foregroundStyle(palette.muted).lineSpacing(1)
        }
        .padding(10)
        .background(palette.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.line) }
    }

    private func segment(_ title: String, _ icon: String, _ target: MediaOutput) -> some View {
        let selected = output == target
        return Button { if !selected { onOutput(target) } } label: {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 7)
                .background(selected ? palette.panel2 : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(selected ? 0.12 : 0), radius: 4, y: 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(connecting || !canChooseOutput)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("MÍDIA NO CELULAR").font(.system(size: 10.5, weight: .semibold)).tracking(0.7).foregroundStyle(palette.muted)
                .padding(.bottom, 4)
            if queue.isEmpty {
                Text("Carregando a fila…").font(.system(size: 12)).foregroundStyle(palette.muted)
            }
            ForEach(queue.prefix(6)) { item in
                Button { onPick(item) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "music.note").font(.system(size: 12)).foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(NexusPalette.hueColor(NexusPalette.stableHue(item.title)), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Text(item.title.isEmpty ? "Sem título" : item.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 0)
                        if item.id == queueActive { Image(systemName: "waveform").font(.system(size: 12)).foregroundStyle(palette.accent) }
                    }
                    .padding(6).contentShape(Rectangle())
                    .background(item.id == queueActive ? palette.accentSurface : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain).disabled(!canControl)
            }
        }
        .onAppear(perform: onOpenQueue)
    }

    // MARK: Pieces

    private func cover(size: CGFloat, radius: CGFloat) -> some View {
        Group {
            if let art {
                Image(nsImage: art).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [palette.fill, palette.secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note").font(.system(size: size * 0.42)).foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .accessibilityHidden(true)
    }

    private func playButton(size: CGFloat) -> some View {
        Button { onCommand(playing ? "pause" : "play") } label: {
            Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: size * 0.45))
                .foregroundStyle(palette.accentInk).frame(width: size, height: size)
                .background(palette.fill, in: Circle())
                .shadow(color: palette.fill.opacity(0.35), radius: size * 0.2, y: size * 0.1)
        }
        .buttonStyle(.plain).disabled(!canControl)
        .accessibilityLabel(playing ? "Pausar" : "Reproduzir")
    }

    private func iconButton(_ symbol: String, _ label: String, size: CGFloat, muted: Bool = false, tint: Color? = nil,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size * 0.5))
                .foregroundStyle(tint ?? (muted ? palette.muted : palette.ink))
                .frame(width: size, height: size).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!canControl && !muted)
        .accessibilityLabel(label).help(label)
    }
}
