import AppKit
import QuickLookThumbnailing
import SwiftUI

struct OverviewConversationRow: Identifiable {
    let id: String
    let title: String
    let preview: String
    let date: Date
    let outgoing: Bool
}

struct OverviewData {
    var name: String
    var active: Bool
    var battery: Int?
    var charging: Bool
    /// The six quick buttons under the battery.
    var controls: [QuickControl]
    var notices: [NotificationSync.Notice]
    var conversation: [OverviewConversationRow]
    var photos: [ReceivedFile]
    var clipboardText: String?
    var clipboardDate: Date?
    /// Where the phone's sound comes out now, and whether the choice can be changed right now.
    var audioOutput: MediaOutput = .phone
    var audioBusy = false
    var audioLocked = false
}

/// What each card does. A nil action leaves its tile disabled.
struct OverviewActions {
    var control: (() -> Void)?
    var sendFile: (() -> Void)?
    var photo: (() -> Void)?
    var scan: (() -> Void)?
    /// Why a tile is off, shown in place of its caption so a dimmed tile never looks broken.
    var sendFileHint = ""
    var photoHint = ""
    var scanHint = ""
    var pressControl: (QuickControl.Kind) -> Void = { _ in }
    var chooseOutput: (MediaOutput) -> Void = { _ in }
    var openNotifications: () -> Void = {}
    var openConversation: () -> Void = {}
    var openGallery: () -> Void = {}
    var copyClipboard: ((String) -> Void)?
    /// Files dropped on the screen; nil when the phone cannot receive files.
    var dropFiles: (([URL]) -> Bool)?
}

/// The home screen, laid out like the design: device card, quick actions, notifications, conversation, photos, clipboard.
struct OverviewScreen: View {
    let data: OverviewData
    let actions: OverviewActions
    /// Things the design has no card for but the app keeps here (battery alert, Do Not Disturb, connect button).
    let extras: AnyView
    @Environment(\.colorScheme) private var scheme
    // Starts narrow: until the probe reports the real width, nothing can be wider than its container.
    @State private var width: CGFloat = 0
    @State private var copied = false
    @State private var targetingDrop = false

    private var palette: NexusPalette { NexusPalette(scheme: scheme) }
    private let gap: CGFloat = 16
    static func isWide(width: CGFloat) -> Bool { width >= 860 }
    private var wide: Bool { Self.isWide(width: width) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidthProbe(width: $width)
            VStack(alignment: .leading, spacing: gap) {
                if wide { wideLayout } else { narrowLayout }
                extras
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(FileDropModifier(accept: actions.dropFiles, targeting: $targetingDrop))
        .overlay {
            if targetingDrop {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(palette.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                    .background(palette.accentSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay { Label("Solte para enviar ao \(data.name)", systemImage: "arrow.up.circle").font(.headline).foregroundStyle(palette.accent) }
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Layouts

    private var wideLayout: some View {
        let column = (width - 290 - gap * 2) / 2
        return VStack(alignment: .leading, spacing: gap) {
            // Each row takes the height of its tallest card and the others stretch to it, as the design's grid does.
            HStack(alignment: .top, spacing: gap) {
                deviceCard.frame(width: 290)
                VStack(alignment: .leading, spacing: gap) {
                    quickTiles
                    HStack(alignment: .top, spacing: gap) {
                        notificationsCard.frame(width: column)
                        conversationCard.frame(width: column)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: gap) {
                photosCard.frame(width: 290 + gap + column)
                clipboardCard.frame(width: column)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var narrowLayout: some View {
        VStack(alignment: .leading, spacing: gap) {
            deviceCard
            quickTiles
            notificationsCard
            conversationCard
            photosCard
            clipboardCard
        }
    }

    // MARK: Cards

    private func title(_ text: String, link: String? = nil, action: (() -> Void)? = nil) -> some View {
        HStack {
            Text(text).font(.system(size: 13, weight: .bold))
            Spacer()
            if let link, let action {
                Button(link, action: action).buttonStyle(.plain)
                    .font(.system(size: 12)).foregroundStyle(palette.accent)
            }
        }
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [palette.panel2, palette.panel], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(height: 190)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(palette.faint, lineWidth: 2).frame(width: 66, height: 108)
                        .overlay(alignment: .bottom) { Capsule().fill(palette.faint).frame(width: 22, height: 3).padding(.bottom, 6) }
                        .overlay { Image(systemName: "iphone.gen3").font(.system(size: 26)).foregroundStyle(palette.accent.opacity(0.8)) }
                        .padding(.top, 14)
                        .accessibilityHidden(true)
                }
                .overlay(alignment: .bottom) { audioSelector.padding(10) }
            VStack(alignment: .leading, spacing: 4) {
                Text(data.name).font(.system(size: 18, weight: .bold))
                HStack(spacing: 6) {
                    StatusDot(color: data.active ? palette.fill : palette.faint, pulsing: data.active)
                    Text(data.active ? "Conectado pela rede local" : "Desconectado")
                        .font(.system(size: 12.5)).foregroundStyle(data.active ? palette.accent : palette.muted)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(data.battery.map { "\($0)%" } ?? "—").font(.system(size: 44, weight: .bold)).tracking(-1.3)
                if data.charging, data.battery != nil {
                    Text("carregando").font(.system(size: 12.5)).foregroundStyle(palette.muted)
                }
            }
            if let battery = data.battery {
                GeometryReader { bar in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.track)
                        Capsule().fill(palette.fill).frame(width: bar.size.width * CGFloat(min(max(battery, 0), 100)) / 100)
                    }
                }.frame(height: 6).padding(.top, -8)
            }
            Rectangle().fill(palette.line).frame(height: 1)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(data.controls) { controlButton($0) }
            }
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassPanel(radius: 20)
    }

    /// Where the phone's sound comes out: on the phone itself, or on the Mac's speakers.
    private var audioSelector: some View {
        VStack(spacing: 5) {
            Text("SOM DO CELULAR").font(.system(size: 9.5, weight: .semibold)).tracking(0.7).foregroundStyle(palette.muted)
            HStack(spacing: 3) {
                audioSegment("No Mac", "laptopcomputer", .mac)
                audioSegment("No celular", "iphone", .phone)
            }
            .padding(3)
            .background(palette.input, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.line) }
        }
        .opacity(data.active ? 1 : 0.5)
    }

    private func audioSegment(_ title: String, _ icon: String, _ target: MediaOutput) -> some View {
        let selected = data.audioOutput == target
        return Button { if !selected { actions.chooseOutput(target) } } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 11))
                Text(title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 6)
            .background(selected ? palette.panel2 : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(selected ? 0.12 : 0), radius: 3, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(data.audioBusy || data.audioLocked || !data.active)
        .help(data.audioLocked ? "O áudio está no controle remoto. Encerre-o para trocar a saída." : "Escolha onde o som do celular sai")
        .accessibilityLabel("Som \(title.lowercased())")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func controlButton(_ control: QuickControl) -> some View {
        Button { actions.pressControl(control.kind) } label: {
            HStack(spacing: 8) {
                Image(systemName: control.icon).font(.system(size: 14))
                    .foregroundStyle(control.isOn ? palette.accentInk : palette.ink)
                    .frame(width: 30, height: 30)
                    .background(control.isOn ? palette.fill : palette.panel2, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(control.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    Text(control.subtitle).font(.system(size: 10.5)).foregroundStyle(palette.muted).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 8)
            .background(control.isOn ? palette.accentSurface : palette.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.line) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Never `.disabled`: pressing a button that is off tells the person why instead of doing nothing.
        .opacity(control.isEnabled ? 1 : 0.5)
        .accessibilityLabel(control.accessibilityLabel)
        .accessibilityAddTraits(control.isOn ? .isSelected : [])
    }

    private var quickTiles: some View {
        let items: [(String, String, String, (() -> Void)?)] = [
            ("cursorarrow.rays", "Controlar", "Controle total", actions.control),
            ("arrow.up.doc", "Enviar arquivo", actions.sendFile == nil && !actions.sendFileHint.isEmpty ? actions.sendFileHint : "Arraste e solte", actions.sendFile),
            ("camera", "Foto com o celular", actions.photo == nil && !actions.photoHint.isEmpty ? actions.photoHint : "Usa a câmera dele", actions.photo),
            ("document.viewfinder", "Digitalizar", actions.scan == nil && !actions.scanHint.isEmpty ? actions.scanHint : "Escaneia com o celular", actions.scan),
        ]
        return HStack(spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Button { item.3?() } label: {
                    VStack(alignment: .leading, spacing: 14) {
                        IconBadge(systemName: item.0, size: 38)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.1).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                            Text(item.2).font(.system(size: 12)).foregroundStyle(palette.muted).lineLimit(1)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassPanel(radius: 18)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(item.3 == nil)
                .opacity(item.3 == nil ? 0.5 : 1)
                .accessibilityLabel(item.1)
            }
        }
    }

    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            title("Notificações", link: "Ver todas", action: actions.openNotifications).padding(.bottom, 6)
            if data.notices.isEmpty {
                Text(data.active ? "Nenhuma notificação por enquanto." : "Conecte o celular para ver as notificações.")
                    .font(.system(size: 12.5)).foregroundStyle(palette.muted)
                    .padding(.top, 8).overlay(alignment: .top) { Rectangle().fill(palette.line).frame(height: 1) }
            }
            ForEach(data.notices.prefix(3)) { notice in
                HStack(alignment: .top, spacing: 10) {
                    Group {
                        if let icon = notice.icon {
                            Image(nsImage: icon).resizable().scaledToFit().padding(3)
                        } else {
                            Image(systemName: "bell.fill").foregroundStyle(palette.accent)
                        }
                    }
                    .frame(width: 30, height: 30)
                    .background(palette.panel2, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(notice.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                        Text(notice.body.isEmpty ? notice.app : notice.body)
                            .font(.system(size: 12)).foregroundStyle(palette.muted).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
                .overlay(alignment: .top) { Rectangle().fill(palette.line).frame(height: 1) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPanel(radius: 20)
    }

    private var conversationCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            title("Conversa", link: "Abrir", action: actions.openConversation).padding(.bottom, 6)
            if data.conversation.isEmpty {
                Text("Nenhuma mensagem ainda.").font(.system(size: 12.5)).foregroundStyle(palette.muted)
                    .padding(.top, 8).overlay(alignment: .top) { Rectangle().fill(palette.line).frame(height: 1) }
            }
            ForEach(data.conversation.suffix(3).reversed()) { row in
                Button { actions.openConversation() } label: {
                    HStack(spacing: 10) {
                        Avatar(initials: String(row.title.prefix(1)).uppercased(), hue: row.outgoing ? 165 : 260, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                            Text(row.preview).font(.system(size: 12)).foregroundStyle(palette.muted).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text(row.date, style: .time).font(.system(size: 11)).foregroundStyle(palette.faint)
                    }
                    .padding(.vertical, 8).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { Rectangle().fill(palette.line).frame(height: 1) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPanel(radius: 20)
    }

    private var photosCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            title("Fotos recentes", link: "Ver galeria", action: actions.openGallery)
            if data.photos.isEmpty {
                Text("As fotos que você receber aparecem aqui.").font(.system(size: 12.5)).foregroundStyle(palette.muted)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: wide ? 7 : 4), spacing: 8) {
                    ForEach(data.photos.prefix(wide ? 7 : 4)) { RecentPhotoTile(item: $0) }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPanel(radius: 20)
    }

    private var clipboardCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "document.on.clipboard").font(.system(size: 14)).foregroundStyle(palette.accent)
                Text("Área de transferência").font(.system(size: 13, weight: .bold))
            }
            Text(data.clipboardText ?? "Nada copiado ainda.")
                .font(.system(size: 13)).lineSpacing(2).lineLimit(4)
                .foregroundStyle(data.clipboardText == nil ? palette.muted : palette.ink)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
            HStack {
                if let date = data.clipboardDate {
                    Text(date, style: .relative).font(.system(size: 11.5)).foregroundStyle(palette.faint)
                }
                Spacer()
                if let text = data.clipboardText, let copy = actions.copyClipboard {
                    Button {
                        copy(text)
                        copied = true
                        Task { try? await Task.sleep(for: .seconds(1.6)); copied = false }
                    } label: {
                        Text(copied ? "Copiado ✓" : "Colar no Mac").font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(palette.panel2, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.line) }
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPanel(radius: 20)
    }
}

/// A square thumbnail from Quick Look, bounded so the original is never loaded.
private struct RecentPhotoTile: View {
    let item: ReceivedFile
    @State private var thumbnail: NSImage?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = NexusPalette(scheme: scheme)
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(palette.panel2)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityLabel(item.offer.name)
            .task(id: item.url) {
                let request = QLThumbnailGenerator.Request(fileAt: item.url, size: CGSize(width: 192, height: 192),
                                                           scale: 2, representationTypes: .thumbnail)
                let result = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
                if !Task.isCancelled { thumbnail = result?.nsImage }
            }
    }
}

/// Lets files be dropped on the screen. Skipped in snapshot tests, where ImageRenderer cannot draw the drop target.
struct FileDropModifier: ViewModifier {
    let accept: (([URL]) -> Bool)?
    @Binding var targeting: Bool
    @Environment(\.nexusFlatBackdrop) private var snapshot

    func body(content: Content) -> some View {
        if snapshot {
            content
        } else {
            content.dropDestination(for: URL.self) { urls, _ in
                targeting = false
                return accept?(urls) ?? false
            } isTargeted: { targeting = $0 && accept != nil }
        }
    }
}
