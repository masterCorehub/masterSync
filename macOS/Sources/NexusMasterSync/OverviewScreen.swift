import AppKit
import SwiftUI

/// A photo or video for the "Fotos recentes" strip: its small picture, or the file it comes from.
struct OverviewPhoto: Identifiable {
    let id: String
    var image: NSImage?
    var isVideo = false
}

struct OverviewData {
    var name: String
    var active: Bool
    var battery: Int?
    var charging: Bool
    /// The six round buttons under the battery.
    var controls: [QuickControl]
    var notices: [NotificationSync.Notice]
    var recent: [OverviewPhoto]
    /// Where the phone's sound comes out now, and whether the choice can be changed right now.
    var audioOutput: MediaOutput = .phone
    var audioBusy = false
    var audioLocked = false
}

/// What each part does. A nil action leaves its button dimmed, with its hint shown instead of its caption.
struct OverviewActions {
    var control: (() -> Void)?
    var sendFile: (() -> Void)?
    var photo: (() -> Void)?
    var scan: (() -> Void)?
    var sendFileHint = ""
    var photoHint = ""
    var scanHint = ""
    var pressControl: (QuickControl.Kind) -> Void = { _ in }
    var chooseOutput: (MediaOutput) -> Void = { _ in }
    var openNotifications: () -> Void = {}
    var openGallery: () -> Void = {}
    /// Asks the phone for a photo's small picture when its tile shows.
    var needsThumbnail: (String) -> Void = { _ in }
    /// Files dropped on the screen; nil when the phone cannot receive files.
    var dropFiles: (([URL]) -> Bool)?
}

/// The home screen: the phone with its six buttons, what is happening on it now (notifications), and its latest photos.
struct OverviewScreen: View {
    let data: OverviewData
    let actions: OverviewActions
    /// Things the design has no place for but the app keeps here (battery alert, connect button, feedback).
    let extras: AnyView
    @Environment(\.colorScheme) private var scheme
    // Starts narrow: until the probe reports the real width, nothing can be wider than its container.
    @State private var width: CGFloat = 0
    @State private var targetingDrop = false

    private var palette: NexusPalette { NexusPalette(scheme: scheme) }
    private let gap: CGFloat = 16
    static func isWide(width: CGFloat) -> Bool { width >= 860 }
    private var wide: Bool { Self.isWide(width: width) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidthProbe(width: $width)
            VStack(alignment: .leading, spacing: gap) {
                let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: gap)) : AnyLayout(VStackLayout(alignment: .leading, spacing: gap))
                layout {
                    deviceCard.frame(width: wide ? 340 : nil)
                    VStack(alignment: .leading, spacing: gap) {
                        nowCard
                        photosCard
                    }.frame(maxWidth: .infinity, alignment: .topLeading)
                }
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

    // MARK: The phone

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.faint, lineWidth: 2).frame(width: 46, height: 80)
                    .overlay(alignment: .bottom) { Capsule().fill(palette.faint).frame(width: 14, height: 2.5).padding(.bottom, 6) }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(data.name).font(.system(size: 20, weight: .bold)).lineLimit(1)
                    HStack(spacing: 6) {
                        StatusDot(color: data.active ? palette.fill : palette.faint, pulsing: data.active)
                        Text(data.active ? "Conectado pela rede local" : "Desconectado")
                            .font(.system(size: 12.5)).foregroundStyle(data.active ? palette.accent : palette.muted)
                    }
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(data.battery.map { "\($0)%" } ?? "—").font(.system(size: 52, weight: .bold)).tracking(-1.5)
                Spacer()
                if data.charging, data.battery != nil { Text("carregando").font(.system(size: 12.5)).foregroundStyle(palette.muted) }
            }
            if let battery = data.battery {
                GeometryReader { bar in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.track)
                        Capsule().fill(palette.fill).frame(width: bar.size.width * CGFloat(min(max(battery, 0), 100)) / 100)
                    }
                }.frame(height: 6).padding(.top, -10)
                .accessibilityElement(children: .ignore).accessibilityLabel("Bateria \(battery) por cento")
            }
            Rectangle().fill(palette.line).frame(height: 1)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 14) {
                ForEach(data.controls) { roundButton($0) }
            }
            Rectangle().fill(palette.line).frame(height: 1)
            audioSelector
            shortcuts
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassPanel(radius: 24)
    }

    private func roundButton(_ control: QuickControl) -> some View {
        Button { actions.pressControl(control.kind) } label: {
            VStack(spacing: 8) {
                Image(systemName: control.icon).font(.system(size: 20))
                    .foregroundStyle(control.isOn ? palette.accentInk : palette.ink)
                    .frame(width: 60, height: 60)
                    .background(control.isOn ? palette.fill : palette.panel2, in: Circle())
                    .overlay { Circle().strokeBorder(palette.line) }
                Text(control.title).font(.system(size: 12)).foregroundStyle(palette.muted).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Never `.disabled`: pressing a button that is off tells the person why instead of doing nothing.
        .opacity(control.isEnabled ? 1 : 0.5)
        .help(control.subtitle)
        .accessibilityLabel(control.accessibilityLabel)
        .accessibilityAddTraits(control.isOn ? .isSelected : [])
    }

    /// Where the phone's sound comes out: on the phone itself, or on the Mac's speakers.
    private var audioSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SOM DO CELULAR").font(.system(size: 10, weight: .semibold)).tracking(0.7).foregroundStyle(palette.muted)
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

    /// The things the design's home screen leaves out but that are still used often.
    private var shortcuts: some View {
        let items: [(String, String, String, (() -> Void)?)] = [
            ("cursorarrow.rays", "Controlar", "Controle total", actions.control),
            ("arrow.up.doc", "Enviar arquivo", actions.sendFile == nil && !actions.sendFileHint.isEmpty ? actions.sendFileHint : "Arraste e solte", actions.sendFile),
            ("document.viewfinder", "Digitalizar", actions.scan == nil && !actions.scanHint.isEmpty ? actions.scanHint : "Escaneia no celular", actions.scan),
            ("camera", "Foto", actions.photo == nil && !actions.photoHint.isEmpty ? actions.photoHint : "Câmera do celular", actions.photo),
        ]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Button { item.3?() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.0).font(.system(size: 13)).foregroundStyle(palette.accent).frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.1).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Text(item.2).font(.system(size: 10.5)).foregroundStyle(palette.muted).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(palette.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.line) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(item.3 == nil).opacity(item.3 == nil ? 0.5 : 1).accessibilityLabel(item.1)
            }
        }
    }

    // MARK: Now on the phone

    private func title(_ text: String, link: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(text).font(.system(size: 16, weight: .bold))
            Spacer()
            Button(link, action: action).buttonStyle(.plain).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(palette.accent)
        }
    }

    private var nowCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            title("Agora no \(data.name)", link: "Ver tudo", action: actions.openNotifications)
            if data.notices.isEmpty {
                Text(data.active ? "Nenhuma notificação por enquanto." : "Conecte o celular para ver as notificações.")
                    .font(.system(size: 13)).foregroundStyle(palette.muted).padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
            }
            VStack(spacing: 14) {
                ForEach(data.notices.prefix(5)) { notice in noticeRow(notice) }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassPanel(radius: 24)
    }

    private func noticeRow(_ notice: NotificationSync.Notice) -> some View {
        Button { actions.openNotifications() } label: {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if let icon = notice.icon {
                        Image(nsImage: icon).resizable().scaledToFit().padding(5)
                    } else {
                        Text(String(notice.app.prefix(1)).uppercased()).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    }
                }
                .frame(width: 46, height: 46)
                .background(notice.icon == nil ? NexusPalette.hueColor(NexusPalette.stableHue(notice.group)) : palette.panel2,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(notice.title).font(.system(size: 14.5, weight: .semibold)).lineLimit(1)
                        Text(notice.app).font(.system(size: 12)).foregroundStyle(palette.faint).lineLimit(1)
                    }
                    if !notice.body.isEmpty {
                        Text(notice.body).font(.system(size: 13.5)).foregroundStyle(palette.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text(notice.date, style: .time).font(.system(size: 12)).foregroundStyle(palette.faint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(notice.app): \(notice.title). \(notice.body)")
    }

    // MARK: Photos

    private var photosCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            title("Fotos recentes", link: "Ver biblioteca", action: actions.openGallery)
            if data.recent.isEmpty {
                Text("As fotos mais recentes do celular aparecem aqui.").font(.system(size: 13)).foregroundStyle(palette.muted)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            } else {
                let count = wide ? 5 : 3
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: count), spacing: 10) {
                    ForEach(data.recent.prefix(count)) { photo in
                        Button { actions.openGallery() } label: { tile(photo) }.buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassPanel(radius: 24)
    }

    private func tile(_ photo: OverviewPhoto) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(palette.panel2)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = photo.image { Image(nsImage: image).resizable().scaledToFill() }
                else { Image(systemName: photo.isVideo ? "play.circle.fill" : "photo").foregroundStyle(palette.faint) }
            }
            .overlay(alignment: .bottomTrailing) {
                if photo.isVideo {
                    Text("Vídeo").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3).background(.black.opacity(0.55), in: Capsule()).padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onAppear { actions.needsThumbnail(photo.id) }
            .accessibilityLabel(photo.isVideo ? "Vídeo recente" : "Foto recente")
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
