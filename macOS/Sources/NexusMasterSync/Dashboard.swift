import AppKit
import ApplicationServices
import CoreImage.CIFilterBuiltins
import NexusCore
import Quartz
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct Dashboard: View {
    @ObservedObject var model: NexusModel
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openWindow) private var openWindow
    @State private var pendingScanDeletion: ReceivedFile?
    @State private var imported = false
    @State private var targetingPhoneDrop = false
    @State private var showingLauncher = false
    @State private var launcherSearch = ""
    @AppStorage("android-launcher-pins") private var storedLauncherPins = Data()
    @State private var chatDraft = ""
    @State private var showNotices = false
    @State private var connectionGuide = false
    @State private var confirmTemporaryConnection = false
    @State private var guidePeer: String?
    @State private var installingWiFiTools = false
    @State private var wifiToolsMessage: String?
    @State private var testingGuideControl = false
    @State private var testingGuideAudio = false
    @State private var guideControlConfirmed = false
    @State private var guideAudioConfirmed = false
    @AppStorage("seen-connection-guide") private var seenConnectionGuide = false
    @AppStorage("network-consent") private var networkConsent = false
    @State private var volume: Double?
    @State private var wirelessClipboardSetup = false
    @State private var clipboardClear = false
    @State private var revokePeer: Peer?
    @State private var replyNotice: NotificationSync.Notice?
    @State private var replyText = ""
    @State private var preview: URL?
    @AppStorage("library-date-grouping") private var libraryGrouping = LibraryDateGrouping.day

    private var palette: NexusPalette { NexusPalette(scheme: scheme) }
    private var accent: Color { palette.accent }

    var body: some View {
        VStack(spacing: 0) {
            DashboardHeader(model: model, gallery: model.gallery, notificationButton: AnyView(notificationButton))
                .padding(.horizontal, 28)
                .padding(.top, 30)
                .padding(.bottom, 18)

            if model.section == .conversation {
                conversationPanel
                    .padding(.horizontal, 28)
                    .padding(.bottom, 22)
                    .onChange(of: model.selected?.id) { _, _ in chatDraft = "" }
                    .onChange(of: latestScanPage?.id) { _, page in
                        if page != nil { model.section = .documents }
                    }
            } else {
                dashboardContent
            }

            if model.section == .devices {
                ConnectionBar(model: model) { imported = true }
                    .padding(.horizontal, 23).padding(.top, 12).padding(.bottom, 19)
            }
        }
        .background { NexusBackdrop() }
        .foregroundStyle(palette.ink)
        .tint(accent)
        .toggleStyle(.switch)
        .onChange(of: model.latestInstantPhoto?.id) { _, _ in
            if let photo = model.latestInstantPhoto { preview = photo.url }
        }
        .fileImporter(isPresented: $imported, allowedContentTypes: [.item]) {
            switch $0 {
            case .success(let url): model.sendFile(url)
            case .failure(let error): model.problem = error.localizedDescription
            }
        }
        .task {
            if !seenConnectionGuide {
                seenConnectionGuide = true
                if !networkConsent && model.peers.isEmpty { connectionGuide = true }
            }
        }
        .sheet(isPresented: Binding(
            get: { connectionGuide || model.invitation != nil || model.pending != nil },
            set: { if !$0 { closeConnectionGuide() } }
        )) {
            if connectionGuide {
                connectionOnboarding
            } else {
                pairing
            }
        }
        .sheet(isPresented: $wirelessClipboardSetup) {
            WirelessClipboardSetup(device: model.adbClipboard.wirelessDevice) { device, pairing in
                // A session stuck reconnecting to an old address would make the new setup a no-op.
                model.adbClipboard.stop()
                model.adbClipboard.startWiFi(device: device, pairing: pairing)
            }
        }
        .confirmationDialog("Limpar o histórico da área de transferência?", isPresented: $clipboardClear) {
            Button("Limpar histórico", role: .destructive) { model.clipboard.clear() }
        }
        .confirmationDialog("Revogar o acesso deste celular?",
            isPresented: Binding(get: { revokePeer != nil }, set: { if !$0 { revokePeer = nil } }),
            presenting: revokePeer) { peer in
                Button("Revogar \(peer.name)", role: .destructive) { model.revoke(peer) }
        }
        .sheet(item: $replyNotice) { notice in
            VStack(alignment: .leading, spacing: 14) {
                Text("Responder em \(notice.app)").font(.title2)
                TextField("Mensagem", text: $replyText)
                HStack {
                    Button("Cancelar") { replyNotice = nil }
                    Spacer()
                    Button("Enviar") {
                        model.notifications.reply(to: notice, text: replyText)
                        replyNotice = nil
                    }.buttonStyle(NexusPillStyle(prominent: true)).disabled(replyText.isEmpty || replyText.utf8.count > 1024)
                }
            }.padding(25).frame(width: 390)
        }
        .sheet(isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) {
            if let preview {
                VStack(alignment: .trailing, spacing: 12) {
                    FilePreview(url: preview)
                    if model.latestInstantPhoto?.url == preview {
                        HStack {
                            Button("Copiar arquivo") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.writeObjects([preview as NSURL])
                            }
                            ShareLink(item: preview)
                                .onDrag { NSItemProvider(contentsOf: preview) ?? NSItemProvider() }
                            Spacer()
                        }
                    }
                    Button("Fechar") { self.preview = nil }.keyboardShortcut(.cancelAction)
                }.padding(15).frame(minWidth: 560, minHeight: 410)
            }
        }
    }

    private var dashboardContent: some View {
        GeometryReader { viewport in
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if model.section != .overview {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(model.section.rawValue)
                                        .font(.system(size: 33, weight: .semibold, design: .rounded))
                                        .tracking(-0.75)
                                        .accessibilityAddTraits(.isHeader)
                                }
                                Spacer()
                                if model.section == .documents {
                                    Button { model.requestScan() } label: {
                                        Label("Digitalizar novo", systemImage: "document.viewfinder")
                                    }
                                    .buttonStyle(NexusPillStyle(compact: true)).disabled(!model.canRequestScan)
                                }
                                if model.section == .files {
                                    Button { imported = true } label: {
                                        Label("Enviar novo", systemImage: "arrow.up")
                                    }
                                    .buttonStyle(NexusPillStyle(compact: true)).disabled(!model.canSendFiles)
                                }
                            }
                        }

                        if let problem = model.problem ?? model.networkProblem {
                            Label(problem, systemImage: "exclamationmark.circle")
                                .foregroundStyle(palette.accent)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .nexusPanel(palette, radius: 12, highlighted: true)
                        }

                        switch model.section {
                        case .overview: overview(size: viewport.size)
                        case .conversation: EmptyView()
                        case .devices: devices
                        case .clipboard: clipboard
                        case .documents: documents
                        case .gallery: gallery
                        case .files: files
                        case .notifications: notifications
                        case .remote: remote
                        case .settings: settings
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 5)
                    .padding(.bottom, 20)
                    .frame(maxWidth: 1650, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .id(model.section)
                .onChange(of: latestScanPage?.id) { _, page in
                    guard page != nil else { return }
                    if model.section == .documents { scroll.scrollTo("scan-preview", anchor: .top) }
                    else { model.section = .documents }
                }
            }
        }
    }

    private func overview(size: CGSize) -> some View {
        let columnWidth = min(max(size.width * 0.37, 250), 545)
        // Preserve the handset proportions while using the available viewport height.
        let phoneHeight = min(max(size.height - 130, 380), (columnWidth - 36) * 1.98, 800)
        return HStack(alignment: .top, spacing: 30) {
            phonePanel(height: phoneHeight)
                .frame(width: columnWidth)
                .padding(.vertical, 20)
                .nexusPanel(palette, radius: 22)
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.selected?.name ?? "Seu Android").font(.title2.weight(.semibold))
                        Label(model.active ? "Conectado" : "Desconectado",
                              systemImage: model.active ? "wifi" : "wifi.slash")
                            .font(.caption).foregroundStyle(model.active ? palette.connected : palette.muted)
                    }
                    Spacer()
                    if let battery = model.selectedStatus?.battery {
                        Label("\(battery)%", systemImage: "battery.50percent")
                    }
                }
                if !model.active {
                    Button("Conectar Android") { connectionGuide = true }
                        .buttonStyle(NexusPillStyle(prominent: true, compact: true))
                }
                Button { model.requestInstantPhoto() } label: {
                    Label(model.cameraPending ? "Aguardando foto…" : "Tirar foto com o Android", systemImage: "camera")
                }
                .buttonStyle(NexusPillStyle(compact: true))
                .disabled(!model.canRequestPhoto || model.cameraPending)
                .help("Ative Arquivos e autorize solicitações de câmera no MasterSync do Android.")
                if let feedback = model.cameraFeedback, !feedback.isEmpty { empty(feedback) }
                if let peer = model.selected?.id, model.active, let alert = model.batteryMessages[peer] {
                    Label(alert, systemImage: "battery.25percent")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.accent)
                }
                androidLauncher
                audioPanel
                compactNotifications
                Toggle("Área de transferência", isOn: Binding(
                    get: { model.clipboardEnabled || model.adbClipboard.transport != nil },
                    set: {
                        model.clipboardEnabled = $0
                        if !$0 {
                            model.adbClipboard.stop()
                        } else if let device = model.adbClipboard.wirelessDevice {
                            model.adbClipboard.startWiFi(device: device)
                        }
                    }
                ))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }

    private var launcherPins: [String: [String]] {
        (try? JSONDecoder().decode([String: [String]].self, from: storedLauncherPins)) ?? [:]
    }

    private func setPinned(_ id: String, peer: String, pinned: Bool) {
        var saved = launcherPins
        var ids = saved[peer] ?? []
        ids.removeAll { $0 == id }
        if pinned { ids.append(id) }
        saved[peer] = ids
        if let data = try? JSONEncoder().encode(saved) { storedLauncherPins = data }
    }

    private var canLaunchApps: Bool {
        model.canMirror && model.wirelessControlDevice(for: model.selected?.id) != nil
            && !model.screen.preparingControl
    }

    private var androidLauncher: some View {
        let peer = model.selected?.id ?? ""
        let apps = model.launcherLists[peer] ?? []
        let pins = launcherPins[peer] ?? []
        let pinnedApps = pins.compactMap { id in apps.first { $0.id == id } }
        return VStack(alignment: .leading, spacing: 9) {
            Button {
                launcherSearch = ""
                showingLauncher.toggle()
                if showingLauncher { model.refreshLauncher() }
            } label: {
                Label("Apps do Android", systemImage: "square.grid.2x2")
            }
            .buttonStyle(NexusPillStyle(compact: true))
            .popover(isPresented: $showingLauncher, arrowEdge: .bottom) {
                launcherPopover(apps: apps, peer: peer, pins: pins)
            }
            let withIcon = pinnedApps.filter { model.launcherIcons[$0.id] != nil }
            let withoutIcon = pinnedApps.filter { model.launcherIcons[$0.id] == nil }
            if !withIcon.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(withIcon) { app in pinnedAppButton(app, peer: peer) }
                }
            }
            if !withoutIcon.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(withoutIcon) { app in pinnedAppButton(app, peer: peer) }
                }
            }
        }
        .task(id: model.launcherAvailable && !peer.isEmpty ? peer : "") { model.refreshLauncher() }
        .task(id: pins + [peer, model.launcherLists[peer] == nil ? "" : "ready"]) {
            model.requestLauncherIcons(for: pins)
        }
        .onChange(of: peer) { _, _ in showingLauncher = false }
    }

    private func pinnedAppButton(_ app: AndroidApp, peer: String) -> some View {
        let label = Wire.visible(app.label, limit: 70)
        return Button { model.launchAndroidApp(app) } label: {
            if let icon = model.launcherIcons[app.id] {
                Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
                    .frame(width: 32, height: 32)
            } else {
                Text(label).lineLimit(1).frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(model.launcherIcons[app.id] == nil ? NexusPillStyle(compact: true) : NexusPillStyle(compact: true, segmented: true))
        .help(label)
        .accessibilityLabel(label)
        .disabled(!canLaunchApps)
        .contextMenu {
            Button("Desafixar", systemImage: "pin.slash") { setPinned(app.id, peer: peer, pinned: false) }
        }
    }

    private func launcherPopover(apps: [AndroidApp], peer: String, pins: [String]) -> some View {
        let filtered = apps.filter {
            launcherSearch.isEmpty || $0.label.localizedStandardContains(launcherSearch)
                || $0.component.localizedStandardContains(launcherSearch)
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Apps do Android").font(.headline)
                Spacer()
                Button { model.refreshLauncher() } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(!model.launcherAvailable).accessibilityLabel("Atualizar lista de apps")
            }
            if !model.active {
                empty("Conecte o Android para carregar os apps.")
            } else if !model.launcherAvailable {
                empty("Atualize o MasterSync no Android para ver os apps.")
            } else {
                if model.wirelessControlDevice(for: peer) == nil {
                    Button("Configurar controle por Wi-Fi") {
                        showingLauncher = false
                        openWirelessControlGuide()
                    }
                    .buttonStyle(NexusPillStyle(compact: true))
                } else if !model.canMirror {
                    empty("Ative o espelhamento no MasterSync do Android.")
                }
                TextField("Buscar app", text: $launcherSearch).textFieldStyle(.roundedBorder)
                if model.launcherLists[peer] == nil {
                    Text("Aguardando a lista do Android…").foregroundStyle(palette.muted)
                } else if filtered.isEmpty {
                    empty("Nenhum app encontrado.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(filtered) { app in
                                let pinned = pins.contains(app.id)
                                HStack {
                                    Button {
                                        showingLauncher = false
                                        model.launchAndroidApp(app)
                                    } label: {
                                        Label(Wire.visible(app.label, limit: 70), systemImage: "app")
                                            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain).disabled(!canLaunchApps)
                                    Button { setPinned(app.id, peer: peer, pinned: !pinned) }
                                    label: { Image(systemName: pinned ? "pin.fill" : "pin") }
                                    .buttonStyle(NexusPillStyle(compact: true))
                                    .help(pinned ? "Desafixar app" : "Fixar app")
                                    .accessibilityLabel(pinned ? "Desafixar app" : "Fixar app")
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                    .frame(height: 240)
                }
            }
        }.padding(15).frame(width: 320)
    }

    private var audioPanel: some View {
        let screen = model.screen
        return card("Áudio do Android", icon: "speaker.wave.2") {
            Toggle("Ouvir no Mac", isOn: Binding(
                get: { screen.audioOnlyActive },
                set: { enabled in
                    if enabled {
                        if let device = model.wirelessControlDevice(for: model.selected?.id) {
                            screen.launchScrcpy(audioOnly: true, wireless: device)
                        } else { openWirelessControlGuide() }
                    } else { screen.stopUSB() }
                }
            ))
            .disabled(screen.connecting || (screen.usbActive && !screen.audioOnlyActive))
            Divider()
            HStack(spacing: 10) {
                Image(systemName: "music.note")
                    .frame(width: 40, height: 40)
                    .background(palette.accentSurface, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(palette.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.currentMedia?.name ?? "Reprodução").lineLimit(1)
                    if let artist = model.currentMedia?.text {
                        Text(artist).font(.caption).foregroundStyle(palette.muted).lineLimit(1)
                    }
                }
                Spacer()
                playbackButton("previous", icon: "backward.end.fill", title: "Anterior")
                if let playing = model.currentMedia?.playing {
                    playbackButton(playing ? "pause" : "play", icon: playing ? "pause.fill" : "play.fill",
                                   title: playing ? "Pausar" : "Reproduzir")
                } else {
                    playbackButton("play", icon: "play.fill", title: "Reproduzir")
                    playbackButton("pause", icon: "pause.fill", title: "Pausar")
                }
                playbackButton("next", icon: "forward.end.fill", title: "Próxima")
            }
            if let volume {
                HStack {
                    Slider(value: Binding(get: { self.volume ?? volume }, set: { self.volume = $0 }),
                           in: 0...100, step: 1) {
                        Label("Volume no Mac", systemImage: "speaker.wave.2")
                    } onEditingChanged: { editing in
                        if !editing, let level = self.volume {
                            Task {
                                // Apply the volume to the current macOS output.
                                self.volume = await outputVolume(setTo: Int(level))
                            }
                        }
                    }
                    Text("\(Int(volume))%").monospacedDigit()
                }
            }
            if screen.connecting { ProgressView("Conectando…").controlSize(.small) }
            if let feedback = screen.feedback { empty(feedback) }
        }
        .task { volume = await outputVolume() }
        .task(id: model.selected?.id) {
            while !Task.isCancelled {
                model.refreshMedia()
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
    }

    private func outputVolume(setTo level: Int? = nil) async -> Double? {
        await Task.detached(priority: .utility) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            var commands: [String] = []
            if let level { commands += ["-e", "set volume output volume \(level)"] }
            process.arguments = commands + ["-e", "output volume of (get volume settings)"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return nil }
                return Double(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
            } catch { return nil }
        }.value
    }

    private func playbackButton(_ command: String, icon: String, title: String) -> some View {
        Button { model.mediaControl(command) } label: { Image(systemName: icon) }
            .buttonStyle(NexusPillStyle(compact: true))
            .disabled(!model.canPlayMedia)
            .help(title).accessibilityLabel(title)
    }

    private var notificationButton: some View {
        Button { showNotices.toggle() } label: {
            Image(systemName: model.notifications.notices.isEmpty ? "bell" : "bell.badge")
        }
        .buttonStyle(NexusPillStyle(compact: true))
        .accessibilityLabel("Notificações")
        .popover(isPresented: $showNotices, arrowEdge: .bottom) {
            compactNotifications.frame(width: 340).padding(10)
        }
    }

    private func phonePanel(height: CGFloat) -> some View {
        VStack(spacing: 10) {
            embeddedPhone(height: height)
                .dropDestination(for: URL.self) { urls, _ in
                    targetingPhoneDrop = false
                    return model.sendDroppedFiles(urls)
                } isTargeted: { targetingPhoneDrop = $0 && model.canSendFiles }
                .overlay {
                    if targetingPhoneDrop {
                        RoundedRectangle(cornerRadius: 27)
                            .strokeBorder(palette.accent, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                            .background(palette.accentSurface.opacity(0.9), in: RoundedRectangle(cornerRadius: 27))
                            .overlay {
                                Label("Solte para enviar", systemImage: "arrow.up.circle")
                                    .font(.headline).foregroundStyle(palette.accent)
                            }
                            .allowsHitTesting(false)
                    }
                }
            Button { model.findPhone() } label: {
                Label("Tocar celular", systemImage: "bell.badge")
            }
            .buttonStyle(NexusPillStyle(compact: true)).disabled(!model.canFindPhone)
            if let feedback = model.actionFeedback { empty(feedback) }
        }
    }

    private func embeddedPhone(height: CGFloat = 454) -> some View {
        let screen = model.screen
        return VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 28).fill(Color.black.opacity(0.91))
                if let frame = screen.frame {
                    GeometryReader { canvas in
                        let ratio = frame.size.width / max(frame.size.height, 1)
                        let width = min(canvas.size.width, canvas.size.height * ratio)
                        let height = width / max(ratio, 0.01)
                        Image(nsImage: frame).resizable().scaledToFit()
                            .frame(width: width, height: height)
                            .contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0).onEnded { gesture in
                                // The fit rectangle excludes the black bars from touch input.
                                guard width > 0, height > 0 else { return }
                                screen.gesture(from: CGPoint(x: gesture.startLocation.x / width,
                                                             y: gesture.startLocation.y / height),
                                               to: CGPoint(x: gesture.location.x / width, y: gesture.location.y / height))
                            })
                            .position(x: canvas.size.width / 2, y: canvas.size.height / 2)
                            .accessibilityLabel("Tela interativa do Android")
                    }
                    if !screen.controlling && !screen.preparingControl {
                        embeddedControlButton
                    }
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "iphone").font(.system(size: 41, weight: .ultraLight))
                            .foregroundStyle(.white.opacity(0.55)).accessibilityHidden(true)
                        if screen.preparingControl || screen.requesting || screen.sharing {
                            ProgressView().controlSize(.small)
                            Text(screen.requesting ? "Autorize no Android" : "Conectando…")
                                .font(.caption).foregroundStyle(.white)
                        } else {
                            embeddedControlButton
                            if !model.canMirror {
                                Text(model.active ? "Autorize o espelhamento no Android." : "Conecte seu Android para começar.")
                                    .font(.caption).foregroundStyle(.white.opacity(0.75))
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }
                    .padding(12)
                }
            }
            .padding(5)
            .frame(width: height * 0.507, height: height)
            .clipShape(.rect(cornerRadius: 27))
            .overlay { RoundedRectangle(cornerRadius: 27).strokeBorder(palette.border, lineWidth: 2).allowsHitTesting(false) }
            HStack(spacing: 10) {
                Button { screen.pressSystemKey(home: false) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Voltar no Android")
                Button { screen.pressSystemKey(home: true) } label: { Image(systemName: "circle") }
                    .accessibilityLabel("Tela inicial do Android")
                Button { screen.end() } label: { Image(systemName: "stop.fill") }
                    .accessibilityLabel("Encerrar controle").help("Encerrar controle")
            }
            .buttonStyle(NexusPillStyle(compact: true))
            .disabled(!screen.controlling || !screen.sharing)
            .opacity(screen.controlling && screen.sharing ? 1 : 0)
        }
    }

    private var embeddedControlButton: some View {
        Button {
            if let peer = model.selected?.id {
                if let device = model.wirelessControlDevice(for: peer) {
                    if ScreenMirror.controlRoute(hasWirelessADB: true, scrcpyInstalled: model.screen.scrcpyInstalled) == .scrcpy {
                        model.screen.launchScrcpy(audioOnly: false, wireless: device)
                    } else {
                        model.screen.beginControl(peer, wireless: device)
                    }
                } else { openWirelessControlGuide() }
            }
        } label: {
            Label("Controlar", systemImage: "play.fill")
        }
        .buttonStyle(NexusPillStyle(prominent: true, compact: true))
        .disabled(!model.canMirror)
    }

    private enum ConversationEntry: Identifiable {
        case text(NexusModel.ChatEntry)
        case file(ReceivedFile, outgoing: Bool)

        var id: String {
            switch self {
            case .text(let entry): "message-" + entry.id
            case .file(let item, let outgoing): "file-\(outgoing)-" + item.id
            }
        }

        var date: Date {
            switch self {
            case .text(let entry): entry.date
            case .file(let item, _): item.date
            }
        }

        var outgoing: Bool {
            switch self {
            case .text(let entry): entry.outgoing
            case .file(_, let outgoing): outgoing
            }
        }
    }

    private var conversationEntries: [ConversationEntry] {
        guard let peer = model.selected?.id else { return [] }
        let texts = model.messages.filter { $0.peer == peer }.map(ConversationEntry.text)
        let incoming = model.files.received.filter { $0.peerID == peer }.map { ConversationEntry.file($0, outgoing: false) }
        let outgoing = model.files.sent.filter { $0.peerID == peer }.map { ConversationEntry.file($0, outgoing: true) }
        return Array((texts + incoming + outgoing).sorted { $0.date < $1.date }.suffix(60))
    }

    private var conversationPanel: some View {
        let entries = conversationEntries
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "iphone")
                    .foregroundStyle(palette.accent)
                    .frame(width: 38, height: 38)
                    .background(palette.accentSurface, in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.selected?.name ?? "Conversa").font(.headline)
                    Label(model.active ? "Conectado" : "Desconectado",
                          systemImage: model.active ? "wifi" : "wifi.slash")
                        .font(.caption).foregroundStyle(model.active ? palette.connected : palette.muted)
                }
                Spacer()
            }.padding(16)
            Divider()
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if entries.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "bubble.left.and.bubble.right").font(.title2)
                                empty("Envie uma mensagem ou um arquivo para o Android.")
                            }
                            .foregroundStyle(palette.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 54)
                        }
                        ForEach(entries.indices, id: \.self) { index in
                            let entry = entries[index]
                            if index == 0 || !calendar.isDate(entries[index - 1].date, inSameDayAs: entry.date) {
                                Text(entry.date, style: .date)
                                    .font(.caption.weight(.medium)).foregroundStyle(palette.muted)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(palette.control, in: Capsule())
                            }
                            conversationBubble(entry).id(entry.id)
                        }
                    }
                    .padding(22)
                }
                .frame(maxHeight: .infinity)
                .onChange(of: entries.last?.id, initial: true) { _, id in
                    if let id { scroll.scrollTo(id, anchor: .bottom) }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button { imported = true } label: { Image(systemName: "paperclip") }
                        .buttonStyle(NexusPillStyle(compact: true)).disabled(!model.canSendFiles)
                        .help("Enviar arquivo").accessibilityLabel("Enviar arquivo")
                    TextField(model.canChat ? "Mensagem" : "Conversa indisponível", text: $chatDraft)
                        .textFieldStyle(.roundedBorder).disabled(!model.canChat)
                        .onSubmit { sendChatDraft() }
                    Button { sendChatDraft() } label: { Image(systemName: "arrow.up") }
                        .buttonStyle(NexusPillStyle(prominent: true, compact: true))
                        .disabled(!model.canChat || chatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chatDraft.utf8.count > 2048)
                        .help("Enviar mensagem").accessibilityLabel("Enviar mensagem")
                }
                ForEach(model.files.progress.filter { $0.peer == model.selected?.id }) { item in
                    ProgressView(value: item.fraction) { Text(item.name).lineLimit(1) }
                }
                if let peer = model.selected?.id, let waiting = model.files.queued[peer], !waiting.isEmpty {
                    Label(waiting.count == 1 ? "1 arquivo na fila" : "\(waiting.count) arquivos na fila",
                          systemImage: "tray.full")
                        .font(.caption).foregroundStyle(palette.muted)
                }
                if let feedback = model.files.feedback { empty(feedback) }
            }
            .padding(14)
        }
        .frame(maxWidth: 1200, maxHeight: .infinity)
        .nexusPanel(palette, radius: 20)
        .frame(maxWidth: .infinity)
    }


    private func sendChatDraft() {
        if model.sendChat(chatDraft) { chatDraft = "" }
    }

    private func conversationBubble(_ entry: ConversationEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            switch entry {
            case .text(let message):
                Text(message.text).textSelection(.enabled)
                if message.outgoing && !message.confirmed {
                    Text("Sem confirmação").font(.caption2).foregroundStyle(palette.muted)
                }
            case .file(let item, _):
                Button { preview = item.url } label: {
                    Label(item.offer.name, systemImage: "doc").lineLimit(2)
                }
                .buttonStyle(.plain).disabled(!FileManager.default.fileExists(atPath: item.url.path))
            }
            Text(entry.date, style: .time)
                .font(.caption2).foregroundStyle(palette.muted)
        }
        .padding(.vertical, 9).padding(.horizontal, 13)
        .background(entry.outgoing ? palette.accentSurface : palette.control, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 560, alignment: entry.outgoing ? .trailing : .leading)
        .frame(maxWidth: .infinity, alignment: entry.outgoing ? .trailing : .leading)
    }

    private var androidDndToggle: some View {
        Toggle("Não Perturbe no Android", isOn: Binding(
            get: { model.androidDnd?.dndEnabled == true },
            set: { model.setAndroidDnd($0) }))
            .controlSize(.small)
            .disabled(!model.active || model.androidDnd?.dndAllowed != true)
    }

    @ViewBuilder private var notificationFeedback: some View {
        if model.active, let state = model.androidDnd {
            if let message = state.message {
                empty(Wire.visible(message))
            } else if state.dndAllowed != true {
                empty("No Android, abra MasterSync → Configurações → Notificações e autorize o Não Perturbe.")
            }
        }
        if let peer = model.selected?.id, let error = model.notifications.dismissErrors[peer] {
            empty(error)
        }
    }

    private func dismissNoticeButton(_ notice: NotificationSync.Notice) -> some View {
        let label = notice.canDismiss ? "Dispensar no Android" : "Fixa no Android — ocultar só no Mac"
        return Button {
            if notice.canDismiss { model.notifications.dismiss(notice) } else { model.notifications.hide(notice) }
        } label: {
            Image(systemName: notice.canDismiss ? "xmark.circle" : "eye.slash")
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(notice.canDismiss ? "Dispensar no Android" : "Ocultar no Mac")
    }

    private var clearAllNoticesButton: some View {
        let peer = model.selected?.id
        return Button {
            if let peer { model.notifications.clearAll(peer: peer) }
        } label: {
            Label("Limpar todas", systemImage: "xmark.bin")
        }
        .buttonStyle(NexusPillStyle(compact: true))
        .help("Fecha no Android as que podem ser fechadas e oculta no Mac as fixas")
        .disabled(peer == nil || !model.notifications.notices.contains { $0.peer == peer })
    }

    private var compactNotifications: some View {
        let notices = model.notifications.notices.filter { $0.peer == model.selected?.id }
        return card("Notificações", icon: "bell") {
            HStack {
                androidDndToggle
                Spacer()
                clearAllNoticesButton
                Button("Ver todas") { showNotices = false; model.section = .notifications }
                    .buttonStyle(NexusPillStyle(compact: true))
            }
            notificationFeedback
            if !model.notificationsEnabled {
                Button("Ativar notificações") { showNotices = false; model.section = .notifications }
                    .buttonStyle(NexusPillStyle(compact: true))
            } else if notices.isEmpty {
                empty(model.active ? "Nenhuma notificação ativa. Confira se o espelhamento está autorizado no Android." : "Conecte o Android para ver as notificações.")
            }
            ForEach(notices.prefix(3)) { notice in
                HStack(alignment: .top, spacing: 8) {
                    if let icon = notice.icon {
                        Image(nsImage: icon).resizable().scaledToFit().frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "bell.fill").frame(width: 24, height: 24)
                            .foregroundStyle(palette.accent)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(notice.app).font(.caption.weight(.semibold)).foregroundStyle(palette.muted)
                        Text(notice.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        if !notice.body.isEmpty {
                            Text(notice.body).font(.caption).lineLimit(2)
                        }
                    }
                    Spacer()
                    Text(notice.date, style: .time).font(.caption2).foregroundStyle(palette.muted)
                    dismissNoticeButton(notice)
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.control, in: RoundedRectangle(cornerRadius: 12))
                .contextMenu {
                    if notice.canReply {
                        Button("Responder") { replyText = ""; replyNotice = notice }
                    }
                }
            }
        }
    }

    private var devices: some View {
        VStack(alignment: .leading, spacing: 14) {
            card("Rede local", icon: "wifi") {
                Text("O Mac usa a rede local para receber conexões dos celulares que você autorizar.")
                    .foregroundStyle(palette.muted)
                HStack {
                    Button("Conectar Android") { connectionGuide = true }
                        .buttonStyle(NexusPillStyle(prominent: true))
                    if model.active {
                        Button("Configurar controle e áudio por Wi-Fi") {
                            guidePeer = model.selected?.id
                            connectionGuide = true
                        }
                    }
                }
                if model.serviceReady {
                    HStack {
                        Button("Gerar QR para USB") { model.pair(usb: true) }
                        Spacer()
                        Button("Desativar rede local") { model.disableNetwork() }
                    }
                    if let port = model.networkPort {
                        Text("Para usar USB, execute `adb -d reverse tcp:\(port) tcp:\(port)` antes de ler o QR.")
                            .font(.caption).foregroundStyle(palette.muted).textSelection(.enabled)
                    }
                } else {
                    HStack {
                        Button("Ativar rede local") { model.enableNetwork() }
                            .buttonStyle(NexusPillStyle(prominent: true)).disabled(model.connecting)
                        if model.otherCopyRunning { Button("Mostrar outra cópia") { model.showOtherCopy() } }
                    }
                    if model.connecting { ProgressView("Iniciando serviço…").controlSize(.small) }
                }
            }
            card("Celulares autorizados", icon: "checkmark.shield") {
                if model.peers.isEmpty { empty("Nenhum celular autorizado.") }
                ForEach(model.peers) { peer in
                    HStack {
                        Image(systemName: "iphone").font(.title2).foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(peer.name).fontWeight(.medium)
                            Text(peer.model + (model.online.contains(peer.id) ? " • Conectado" : " • Desconectado"))
                                .font(.caption).foregroundStyle(palette.muted)
                        }
                        Spacer()
                        if model.selected?.id == peer.id { Label("Selecionado", systemImage: "checkmark").foregroundStyle(palette.muted) }
                        else { Button("Selecionar") { model.selectedID = peer.id } }
                        Button("Revogar", role: .destructive) { revokePeer = peer }
                    }.padding(.vertical, 4)
                }
            }
        }
    }

    private var clipboard: some View {
        VStack(alignment: .leading, spacing: 14) {
            card("Sincronização automática", icon: Section.clipboard.icon) {
                Toggle("Sincronizar texto e imagens", isOn: $model.clipboardEnabled)
                Text("Copie em um dispositivo e cole no outro. No Android, escolha o Teclado Nexus para copiar de outros aplicativos e mantenha a conexão em segundo plano.")
                    .foregroundStyle(palette.muted)
                Toggle("Guardar histórico de texto neste Mac", isOn: $model.historyEnabled)
                HStack {
                    Button(model.clipboard.skipNext ? "Próximo item será ignorado" : "Ignorar próximo item") {
                        model.clipboard.ignoreNext()
                    }.disabled(model.clipboard.skipNext || !model.clipboardEnabled)
                    Spacer()
                    Button("Limpar histórico", role: .destructive) { clipboardClear = true }.disabled(model.clipboard.items.isEmpty)
                }
                if let error = model.clipboard.error { Text(error).foregroundStyle(.orange) }
            }
            card("Sincronização por Wi-Fi ou USB", icon: "wifi") {
                Text("Receba textos e imagens do Android com seu teclado atual. Para Wi-Fi, use a Depuração sem fio nas configurações do celular.")
                    .foregroundStyle(palette.muted)
                if let transport = model.adbClipboard.transport {
                    Button(transport == .usb ? "Parar sincronização USB" : "Parar sincronização Wi-Fi") {
                        model.adbClipboard.stop(userInitiated: true)
                    }.buttonStyle(NexusPillStyle())
                } else {
                    HStack {
                        if let device = model.adbClipboard.wirelessDevice {
                            Button("Ativar sincronização Wi-Fi") { model.adbClipboard.startWiFi(device: device) }
                                .buttonStyle(NexusPillStyle(prominent: true))
                        }
                        Button("Configurar Wi-Fi") { wirelessClipboardSetup = true }
                            .buttonStyle(NexusPillStyle(prominent: model.adbClipboard.wirelessDevice == nil))
                        Button("Ativar sincronização USB") { model.adbClipboard.startUSB() }
                            .buttonStyle(NexusPillStyle())
                    }
                }
                if let status = model.adbClipboard.status { empty(status) }
            }
            card("Histórico", icon: "clock.arrow.circlepath") {
                if model.clipboard.items.isEmpty { empty("Nenhum item guardado.") }
                ForEach(model.clipboard.items.sorted { ($0.pinned ? 0 : 1, -$0.date.timeIntervalSince1970) <
                    ($1.pinned ? 0 : 1, -$1.date.timeIntervalSince1970) }) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.text).lineLimit(2).textSelection(.enabled)
                            Text(item.date, style: .relative).font(.caption).foregroundStyle(palette.muted)
                        }
                        Spacer()
                        Button { model.clipboard.apply(item.text) } label: { Image(systemName: "document.on.document") }
                            .help("Copiar texto").accessibilityLabel("Copiar texto")
                        Button { model.clipboard.pin(item.id) } label: { Image(systemName: item.pinned ? "pin.fill" : "pin") }
                            .help(item.pinned ? "Desafixar" : "Fixar").accessibilityLabel(item.pinned ? "Desafixar" : "Fixar")
                        Button(role: .destructive) { model.clipboard.delete(item.id) } label: { Image(systemName: "trash") }
                            .help("Excluir item").accessibilityLabel("Excluir item")
                    }.padding(.vertical, 3)
                    Divider()
                }
            }
        }
    }

    private var documents: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let page = latestScanPage {
                card("Última página salva", icon: "photo") {
                    FilePreview(url: page.url)
                        .frame(height: 280)
                        .accessibilityLabel("Prévia de \(page.offer.name)")
                    fileRow(page)
                }
                .id("scan-preview")
            }
            if let feedback = model.scanRequestFeedback { empty(feedback) }
            if let feedback = model.files.feedback { empty(feedback) }
            receivedGallery(documentFiles, empty: "Nenhum documento.", scanActions: true)
        }
        .confirmationDialog("Mover digitalização para o Lixo?", isPresented: Binding(
            get: { pendingScanDeletion != nil },
            set: { if !$0 { pendingScanDeletion = nil } }
        ), presenting: pendingScanDeletion) { item in
            Button("Mover para o Lixo", role: .destructive) { model.files.trashReceived(item.id) }
            Button("Cancelar", role: .cancel) {}
        } message: { item in
            Text(item.offer.name)
        }
    }

    private var gallery: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.canBrowseGallery {
                GalleryBrowser(gallery: model.gallery, files: model.files, canTransfer: model.canSendFiles,
                               grouping: $libraryGrouping, deviceID: model.selected?.id ?? "")
            } else {
                if !model.active {
                    empty("Aguardando conexão com o Android.")
                } else if !model.galleryEnabled {
                    empty("Ative a galeria em Configurações.")
                } else {
                    empty("Autorize as fotos no MasterSync do Android.")
                }
                if !mediaFiles.isEmpty {
                    receivedGallery(mediaFiles, empty: "")
                }
            }
        }
    }

    private var files: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let feedback = model.files.feedback { empty(feedback) }
            ForEach(model.files.progress) { transfer in
                ProgressView(value: transfer.fraction) {
                    Label(transfer.name, systemImage: transfer.sending ? "arrow.up" : "arrow.down")
                } currentValueLabel: {
                    Text(transfer.verifying ? "Verificando…" : "\(Int(transfer.fraction * 100))%")
                }
            }
            Text("Recebidos").font(.headline).accessibilityAddTraits(.isHeader)
            receivedGallery(model.files.received, empty: "Nenhum arquivo recebido.")
            Text("Enviados").font(.headline).accessibilityAddTraits(.isHeader)
            receivedGallery(model.files.sent, empty: "Nenhum arquivo enviado.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dropDestination(for: URL.self) { urls, _ in
            guard model.canSendFiles, let file = urls.first, file.isFileURL else { return false }
            model.sendFile(file)
            return true
        }
    }

    private var notifications: some View {
        let notices = model.notifications.notices.filter { $0.peer == model.selected?.id }
        return VStack(alignment: .leading, spacing: 14) {
            card("Espelhamento de notificações", icon: "bell") {
                Toggle("Receber notificações do Android", isOn: $model.notificationsEnabled)
                Toggle("Ocultar conteúdo neste Mac", isOn: $model.hideNotices)
                androidDndToggle
                notificationFeedback
                Toggle("Silenciar avisos no Mac", isOn: $model.quiet)
                Button("Autorizar Central de Notificações") { model.notifications.askPermission() }
                if let status = model.notifications.authorization { empty(status) }
            }
            if !model.notifications.apps.isEmpty {
                card("Aplicativos", icon: "square.grid.2x2") {
                    ForEach(model.notifications.apps.keys.sorted(), id: \.self) { key in
                        Toggle(model.notifications.apps[key] ?? key, isOn: Binding(
                            get: { !model.blockedApps.contains(key) },
                            set: { if $0 { model.blockedApps.remove(key) } else { model.blockedApps.insert(key) } }))
                    }
                }
            }
            card("Ativas no Android", icon: "tray") {
                clearAllNoticesButton
                if model.canRefreshNotices && model.notificationsEnabled {
                    Button("Atualizar") { model.refreshNotices() }
                        .buttonStyle(NexusPillStyle(compact: true))
                }
                if notices.isEmpty {
                    empty(model.active ? "Nenhuma notificação ativa." : "Conecte o Android para ver as notificações.")
                }
                ForEach(notices) { notice in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Label {
                                Text(notice.app)
                            } icon: {
                                if let icon = notice.icon { Image(nsImage: icon).resizable().frame(width: 14, height: 14) }
                                else { Image(systemName: "app") }
                            }.font(.caption).foregroundStyle(palette.muted)
                            Text(notice.title).fontWeight(.medium)
                            if !notice.body.isEmpty { Text(notice.body).foregroundStyle(palette.muted) }
                        }
                        Spacer()
                        Text(notice.date, style: .time).font(.caption).foregroundStyle(palette.muted)
                        if notice.canReply {
                            Button("Responder") { replyText = ""; replyNotice = notice }
                        }
                        dismissNoticeButton(notice)
                    }
                    Divider()
                }
            }
        }
    }

    private var remote: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 28) {
                remotePhonePreview
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.selected?.name ?? "Android")
                            .font(.title2.weight(.semibold))
                        Label(model.active ? "Conectado pela rede local" : "Aguardando conexão",
                              systemImage: model.active ? "wifi" : "wifi.slash")
                            .font(.subheadline)
                            .foregroundStyle(model.active ? palette.connected : palette.muted)
                    }

                    HStack(spacing: 8) {
                        remoteAction(audioOnly: false)
                        remoteAction(audioOnly: true)
                    }

                    HStack(spacing: 10) {
                        if model.screen.requesting {
                            ProgressView().controlSize(.small)
                            Text("Autorize a prévia no Android.").foregroundStyle(palette.muted)
                        } else if model.screen.sharing {
                            Button("Parar prévia") { model.screen.end() }
                                .buttonStyle(NexusPillStyle(compact: true))
                            Button("Ampliar") { openWindow(id: "mirror") }
                                .buttonStyle(NexusPillStyle(compact: true))
                        } else {
                            Button("Mostrar prévia") { model.requestMirror() }
                                .buttonStyle(NexusPillStyle(compact: true))
                                .disabled(!model.canMirror)
                                .help("Autorize o espelhamento no Android para mostrar a prévia.")
                        }
                        Menu {
                            Button("Configurar Wi-Fi") { wirelessClipboardSetup = true }
                            Button("Controlar por USB") { model.screen.launchScrcpy(audioOnly: false) }
                                .disabled(model.screen.usbActive || model.screen.connecting)
                            Button("Ouvir por USB") { model.screen.launchScrcpy(audioOnly: true) }
                                .disabled(model.screen.usbActive || model.screen.connecting)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .fixedSize()
                        .accessibilityLabel("Opções de conexão")
                    }
                    if model.screen.connecting {
                        ProgressView("Conectando ao Android…").controlSize(.small)
                    }
                    if let feedback = model.screen.feedback, !model.screen.requesting { empty(feedback) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)
            .nexusPanel(palette, radius: 22)
            card("Ações no Android", icon: "iphone.radiowaves.left.and.right") {
                HStack {
                    Button("Tocar telefone") { model.findPhone() }.disabled(!model.canFindPhone)
                    Spacer()
                    Button("Anterior") { model.mediaControl("previous") }.disabled(!model.canPlayMedia)
                    Button("Reproduzir") { model.mediaControl("play") }.disabled(!model.canPlayMedia)
                    Button("Pausar") { model.mediaControl("pause") }.disabled(!model.canPlayMedia)
                    Button("Próxima") { model.mediaControl("next") }.disabled(!model.canPlayMedia)
                }
                if let feedback = model.actionFeedback { empty(feedback) }
            }
        }
    }

    private var remotePhonePreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 23).fill(palette.canvas)
            if let frame = model.screen.frame {
                // Fit the live frame without cropping system controls.
                Image(nsImage: frame).resizable().scaledToFit()
                    .padding(7)
                    .accessibilityLabel("Prévia da tela do Android")
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "iphone").font(.system(size: 38, weight: .light))
                        .foregroundStyle(palette.accent)
                        .accessibilityHidden(true)
                    Text(model.screen.sharing ? "Carregando prévia…" : "Prévia da tela")
                        .font(.caption).foregroundStyle(palette.muted)
                }
            }
        }
        .frame(width: 158, height: 288)
        .clipShape(.rect(cornerRadius: 23))
        .overlay {
            RoundedRectangle(cornerRadius: 23).strokeBorder(palette.border, lineWidth: 2)
        }
    }

    private func remoteAction(audioOnly: Bool) -> some View {
        let screen = model.screen
        let running = screen.usbActive && screen.audioOnlyActive == audioOnly
        let title = audioOnly ? (running ? "Parar áudio" : "Ouvir no Mac")
                              : (running ? "Encerrar controle" : "Controlar Android")
        let symbol = audioOnly ? (running ? "speaker.slash.fill" : "speaker.wave.2.fill")
                               : (running ? "stop.fill" : "play.fill")
        return Button {
            if running {
                screen.stopUSB()
            } else {
                if let device = model.wirelessControlDevice(for: model.selected?.id) {
                    screen.launchScrcpy(audioOnly: audioOnly, wireless: device)
                } else { openWirelessControlGuide() }
            }
        } label: {
            Label(title, systemImage: symbol)
                .fixedSize()
        }
        .buttonStyle(NexusPillStyle(prominent: !audioOnly))
        .disabled(screen.connecting || (screen.usbActive && !running))
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            card("Aparência", icon: "circle.lefthalf.filled") {
                HStack(spacing: 8) {
                    appearanceOption("Automático", value: "system")
                    appearanceOption("Claro", value: "light")
                    appearanceOption("Escuro", value: "dark")
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Tema")
            }
            card("Alertas de bateria", icon: "battery.75percent") {
                Toggle("Avisar sobre a bateria do Android", isOn: $model.batteryAlertsEnabled)
                if model.batteryAlertsEnabled {
                    Stepper("Bateria baixa · \(model.lowBatteryLimit)%", value: $model.lowBatteryLimit, in: 5...40, step: 5)
                    Stepper("Limite de carga · \(model.chargedBatteryLimit)%", value: $model.chargedBatteryLimit, in: 50...100, step: 5)
                    Button("Autorizar notificações no Mac") { model.notifications.askPermission() }
                        .buttonStyle(NexusPillStyle(compact: true))
                    if let status = model.notifications.authorization { empty(status) }
                }
            }
            card("Permissões", icon: "hand.raised") {
                Toggle("Acessar fotos e vídeos do Android", isOn: $model.galleryEnabled)
                Toggle("Enviar e receber arquivos", isOn: $model.filesEnabled)
                Button("Gerenciar dispositivos") { model.section = .devices }
            }
            card("Digitalizar e colar", icon: "document.viewfinder") {
                Toggle("Ativar atalho \(model.scanShortcut.label)", isOn: $model.scanPasteEnabled)
                Text("A primeira página vai para a área de transferência. Permita Acessibilidade para colar no campo original.")
                    .foregroundStyle(palette.muted)
                Button("Autorizar colagem automática") {
                    _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
                }
                .buttonStyle(NexusPillStyle(compact: true))
                if let feedback = model.scanPasteFeedback { empty(feedback) }
            }
            card("Atalhos", icon: "keyboard") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Digitalizar e colar")
                        Text("Funciona em qualquer app quando o atalho está ativo.").font(.caption).foregroundStyle(palette.muted)
                    }
                    Spacer()
                    ShortcutRecorder(combo: model.scanShortcut) { model.setScanShortcut($0) }
                    Button("Padrão") { model.setScanShortcut(.scanDefault) }
                        .buttonStyle(NexusPillStyle(compact: true))
                        .disabled(model.scanShortcut == .scanDefault)
                }
                if let feedback = model.scanPasteFeedback { empty(feedback) }
                Divider()
                Text("Com o Nexus em primeiro plano, estes usam Shift + Command:")
                    .foregroundStyle(palette.muted)
                let letters = Array("abcdefghijklmnopqrstuvwxyz").map(String.init)
                HStack(spacing: 18) {
                    Picker("Dispositivos", selection: $model.devicesShortcut) {
                        ForEach(letters.filter { $0 != model.filesShortcut }, id: \.self) { Text($0.uppercased()).tag($0) }
                    }.fixedSize()
                    Picker("Arquivos", selection: $model.filesShortcut) {
                        ForEach(letters.filter { $0 != model.devicesShortcut }, id: \.self) { Text($0.uppercased()).tag($0) }
                    }.fixedSize()
                }
            }
        }
    }

    private func appearanceOption(_ label: String, value: String) -> some View {
        Button(label) { model.theme = value }
            .buttonStyle(NexusPillStyle(selected: model.theme == value, compact: true))
            .accessibilityAddTraits(model.theme == value ? .isSelected : [])
    }

    private func openWirelessControlGuide() {
        guidePeer = model.active ? model.selected?.id : nil
        connectionGuide = true
    }

    private func closeConnectionGuide() {
        if testingGuideControl { model.screen.end() }
        if testingGuideAudio { model.screen.stopUSB() }
        testingGuideControl = false
        testingGuideAudio = false
        guideControlConfirmed = false
        guideAudioConfirmed = false
        wifiToolsMessage = nil
        connectionGuide = false
        guidePeer = nil
        model.cancelPair()
    }

    private var connectionOnboarding: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Conectar Android", systemImage: "iphone")
                .font(.title2.weight(.semibold))
            // Read the real pairing state so the guide can resume or retry without a parallel protocol.
            if let peer = guidePeer {
                if model.online.contains(peer) {
                    Label("Android conectado", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(palette.connected)
                    ScrollView { wirelessOnboarding }.frame(maxHeight: 620)
                } else {
                    ProgressView("Aguardando o Android…").controlSize(.small)
                    Button("Gerar outro QR") { guidePeer = nil; model.pair() }
                }
            } else if let pending = model.pending {
                Text("3 de 4 · Autorizar").font(.headline)
                Text("Confirme que este é o celular que leu o QR.")
                Label(pending.peer.name, systemImage: "iphone").font(.headline)
                Text(pending.peer.model).foregroundStyle(palette.muted)
                HStack {
                    Button("Recusar", role: .cancel) { model.confirm(pending, allow: false) }
                    Spacer()
                    Button("Autorizar") {
                        guidePeer = pending.peer.id
                        model.confirm(pending, allow: true)
                    }
                    .buttonStyle(NexusPillStyle(prominent: true))
                }
            } else if let invitation = model.invitation {
                Text("2 de 4 · Ler o QR").font(.headline)
                Text("No MasterSync do Android, abra Dispositivos e toque em Ler QR.")
                    .foregroundStyle(palette.muted)
                if let image = qr(invitation) {
                    Image(nsImage: image).interpolation(.none).resizable()
                        .frame(width: 212, height: 212).padding(12).background(.white)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Código QR de pareamento")
                }
                Button("Gerar outro QR") { model.pair() }
            } else {
                Text("1 de 4 · Preparar a rede").font(.headline)
                Text("Conecte o Mac e o Android à mesma rede Wi-Fi. No celular, abra o MasterSync.")
                    .foregroundStyle(palette.muted)
                if model.connecting {
                    ProgressView("Ativando a rede local…").controlSize(.small)
                } else {
                    Button(model.serviceReady ? "Mostrar QR" : "Ativar rede local") {
                        if model.serviceReady { model.pair() }
                        else { model.enableNetwork() }
                    }
                    .buttonStyle(NexusPillStyle(prominent: true))
                }
            }
            if let problem = model.problem ?? model.networkProblem {
                Label(problem, systemImage: "exclamationmark.circle").foregroundStyle(palette.accent)
            }
            if model.keychainUnavailable {
                Text("Tente ativar a rede novamente para recuperar a identidade salva. Se o macOS continuar bloqueando o acesso, use uma conexão temporária.")
                    .foregroundStyle(palette.muted)
                Button("Conectar só nesta sessão") { confirmTemporaryConnection = true }
                    .buttonStyle(NexusPillStyle(compact: true))
            }
            if model.temporaryNetwork {
                Label("Sessão temporária · será preciso parear novamente após fechar o app.", systemImage: "clock")
                    .font(.caption).foregroundStyle(palette.muted)
            }
            if guidePeer.map({ model.online.contains($0) }) != true {
                Button("Fechar") { closeConnectionGuide() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(26)
        .frame(width: 425)
        .confirmationDialog("Iniciar conexão temporária?", isPresented: $confirmTemporaryConnection) {
            Button("Iniciar sessão temporária") { model.startTemporaryNetwork() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Leia um novo QR no Android. Esta autorização vale até você fechar o MasterSync.")
        }
    }

    private var wirelessOnboarding: some View {
        let adb = model.adbClipboard
        let screen = model.screen
        let toolsAvailable = screen.adbInstalled && screen.scrcpyInstalled
        let device = model.wirelessControlDevice(for: guidePeer)
        let verified = adb.wirelessVerified && device != nil
        return VStack(alignment: .leading, spacing: 12) {
            Label("Rede local conectada", systemImage: "checkmark.circle").foregroundStyle(palette.connected)
            if !toolsAvailable || installingWiFiTools {
                Text("Ferramentas para controle e áudio").font(.headline)
                Text("O MasterSync usa o ADB para controlar o Android e o scrcpy para reproduzir o áudio no Mac.")
                    .foregroundStyle(palette.muted)
                if installingWiFiTools {
                    ProgressView("Instalando ferramentas…").controlSize(.small)
                } else {
                    if WiFiToolInstaller.homebrewPath == nil {
                        Text("O guia vai instalar o Homebrew primeiro. O macOS pode pedir autorização de administrador.")
                            .foregroundStyle(palette.muted)
                    }
                    Button("Instalar ferramentas") { installWiFiTools() }
                        .buttonStyle(NexusPillStyle(prominent: true))
                }
            }
            if let wifiToolsMessage { Text(wifiToolsMessage).foregroundStyle(palette.muted) }
            if verified, let device {
                Label("ADB por Wi-Fi verificado para \(model.selected?.name ?? "o Android")",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(palette.connected)
                if !model.canMirror {
                    Text("Ative o espelhamento nas Configurações do MasterSync no Android para testar o controle.")
                        .foregroundStyle(palette.muted)
                }
                HStack {
                    Button(testingGuideControl ? "Encerrar teste de controle" : "Testar controle") {
                        if testingGuideControl {
                            screen.end()
                            testingGuideControl = false
                        } else if let guidePeer {
                            testingGuideControl = true
                            screen.beginControl(guidePeer, wireless: device)
                        }
                    }
                    .disabled((!model.canMirror || screen.sharing || screen.preparingControl) && !testingGuideControl)
                    Button(screen.audioOnlyActive && testingGuideAudio ? "Parar áudio" : "Testar áudio") {
                        if screen.audioOnlyActive {
                            screen.stopUSB()
                            testingGuideAudio = false
                        } else {
                            testingGuideAudio = true
                            screen.launchScrcpy(audioOnly: true, wireless: device)
                        }
                    }
                    .disabled(!screen.scrcpyInstalled || screen.connecting || (screen.usbActive && !testingGuideAudio))
                }
                .buttonStyle(NexusPillStyle(compact: true))
                if testingGuideControl {
                    if screen.controlling || screen.preparingControl || screen.requesting || screen.sharing {
                        embeddedPhone().frame(maxWidth: .infinity)
                    }
                    if screen.sharing, screen.frame != nil {
                        Text("Toque ou arraste na prévia para conferir a resposta do Android.")
                            .font(.caption).foregroundStyle(palette.muted)
                        Button("O controle funcionou") { guideControlConfirmed = true }
                            .disabled(guideControlConfirmed)
                    }
                }
                if screen.connecting && testingGuideAudio { ProgressView("Conectando o áudio…").controlSize(.small) }
                if screen.audioOnlyActive && testingGuideAudio {
                    Text("Reproduza algo no Android e confira se o som sai no Mac.")
                        .font(.caption).foregroundStyle(palette.muted)
                    Button("Ouvi o áudio no Mac") { guideAudioConfirmed = true }
                        .disabled(guideAudioConfirmed)
                }
                if let feedback = screen.feedback { Text(feedback).foregroundStyle(palette.muted) }
            } else if screen.adbInstalled && !installingWiFiTools {
                WirelessClipboardSetup(device: device, guided: true, busy: adb.checkingWireless) {
                    if let guidePeer { model.configureWirelessControl($0, pairing: $1, peer: guidePeer) }
                }
                if adb.checkingWireless { ProgressView("Testando depuração sem fio…").controlSize(.small) }
                if let error = adb.wirelessSetupError { Text(error).foregroundStyle(palette.accent) }
            }
            if verified {
                Label(guideControlConfirmed ? "Controle confirmado" : "Controle ainda não confirmado",
                      systemImage: guideControlConfirmed ? "checkmark.circle.fill" : "circle")
                Label(guideAudioConfirmed ? "Áudio confirmado" : "Áudio ainda não confirmado",
                      systemImage: guideAudioConfirmed ? "checkmark.circle.fill" : "circle")
            }
            Button(verified ? (guideControlConfirmed && guideAudioConfirmed ? "Finalizar" : "Finalizar sem confirmar os dois testes") : "Agora não") {
                closeConnectionGuide()
                model.section = .overview
            }
            .buttonStyle(NexusPillStyle(prominent: verified && guideControlConfirmed && guideAudioConfirmed))
            .disabled(adb.checkingWireless || installingWiFiTools || screen.connecting)
        }
    }

    private func installWiFiTools() {
        guard !installingWiFiTools else { return }
        let installADB = !model.screen.adbInstalled
        let installScrcpy = !model.screen.scrcpyInstalled
        wifiToolsMessage = nil
        installingWiFiTools = true
        Task {
            defer { installingWiFiTools = false }
            do {
                try await Task.detached(priority: .utility) {
                    try await WiFiToolInstaller.install(adb: installADB, scrcpy: installScrcpy)
                }.value
            } catch {
                wifiToolsMessage = error.localizedDescription
            }
        }
    }

    private var pairing: some View {
        VStack(alignment: .leading, spacing: 17) {
            if let pending = model.pending {
                Label("Autorizar celular?", systemImage: "checkmark.shield").font(.title2.weight(.semibold))
                Text(pending.peer.name).font(.headline)
                Text(pending.peer.model).foregroundStyle(palette.muted)
                Text("Confira se este é o celular que acabou de ler o QR.")
                HStack {
                    Button("Recusar", role: .cancel) { model.confirm(pending, allow: false) }
                    Spacer()
                    Button("Autorizar") { model.confirm(pending, allow: true) }
                        .buttonStyle(NexusPillStyle(prominent: true))
                }
            } else if let invitation = model.invitation {
                Text("Parear Android").font(.title2.weight(.semibold))
                Text("Abra Dispositivos no Nexus do Android e escolha Ler QR.")
                    .foregroundStyle(palette.muted)
                if let image = qr(invitation) {
                    HStack {
                        Spacer()
                        Image(nsImage: image).interpolation(.none).resizable()
                            .frame(width: 212, height: 212).padding(12).background(.white)
                            .accessibilityLabel("Código QR de pareamento")
                        Spacer()
                    }
                }
                Text("Expira em \(Date(timeIntervalSince1970: Double(invitation.expiresAt)), style: .timer)")
                    .monospacedDigit().foregroundStyle(palette.muted)
                Button("Cancelar", role: .cancel) { model.cancelPair() }
            }
        }.padding(28).frame(width: 400)
    }

    private func qr(_ invitation: Invitation) -> NSImage? {
        guard let data = try? JSONEncoder().encode(invitation) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage, let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    private var mediaFiles: [ReceivedFile] { model.files.received.filter {
        ($0.offer.mime.hasPrefix("image/") || $0.offer.mime.hasPrefix("video/")) && !isScan($0)
    } }
    private var documentFiles: [ReceivedFile] { model.files.received.filter {
        $0.offer.mime == "application/pdf" || isScan($0)
    } }
    private var latestScanPage: ReceivedFile? { model.files.received.first { $0.offer.isScanPage } }

    private func isScan(_ file: ReceivedFile) -> Bool {
        file.offer.isScanPage || file.offer.name.hasPrefix("Digitalização")
    }

    private func card<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Label {
                Text(title).font(.headline)
            } icon: {
                Image(systemName: icon).foregroundStyle(palette.accent)
            }
            .accessibilityAddTraits(.isHeader)
            content()
        }.padding(17).frame(maxWidth: .infinity, alignment: .leading)
            .nexusPanel(palette, radius: 16)
    }

    private func empty(_ text: String) -> some View {
        Text(text).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func receivedGallery(_ files: [ReceivedFile], empty hint: String, scanActions: Bool = false) -> some View {
        if files.isEmpty {
            empty(hint)
        } else {
            LibraryDatePicker(selection: $libraryGrouping)
            ForEach(libraryGrouping.sections(for: files, calendar: calendar, date: { $0.date == .distantPast ? nil : $0.date })) { group in
                if libraryGrouping != .none {
                    LibraryDateHeading(date: group.date, grouping: libraryGrouping)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 16) {
                    ForEach(group.items) { item in
                        let available = FileManager.default.fileExists(atPath: item.url.path)
                        Button { preview = item.url } label: {
                            ReceivedTile(item: item, palette: palette)
                        }
                        .buttonStyle(.plain)
                        .disabled(!available)
                        .help(item.offer.name)
                        .contextMenu {
                            Button("Visualizar") { preview = item.url }
                            Button("Mostrar no Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([item.url])
                            }
                            ShareLink(item: item.url)
                            if scanActions { scanFileActions(item) }
                        }
                        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func scanFileActions(_ item: ReceivedFile) -> some View {
        Button("Copiar") {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([item.url as NSURL])
        }
        Button("Excluir…", role: .destructive) { pendingScanDeletion = item }
    }

    private func fileRow(_ item: ReceivedFile) -> some View {
        HStack(spacing: 8) {
            Label(item.offer.name, systemImage: item.offer.mime.hasPrefix("image/") ? "photo" : "doc")
                .lineLimit(1)
            Spacer()
            Button("Visualizar") { preview = item.url }
            scanFileActions(item)
            if model.section != .overview {
                Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: {
                    Image(systemName: "folder").accessibilityLabel("Mostrar no Finder")
                }
                ShareLink(item: item.url) { Image(systemName: "square.and.arrow.up").accessibilityLabel("Compartilhar arquivo") }
            }
        }.onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
    }

}

private struct ReceivedTile: View {
    let item: ReceivedFile
    let palette: NexusPalette
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 10)
                .fill(palette.accentSurface)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    GeometryReader { canvas in
                        if let thumbnail {
                            Image(nsImage: thumbnail).resizable().scaledToFit()
                                .frame(width: canvas.size.width, height: canvas.size.height)
                        } else {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                                .resizable().scaledToFit().frame(width: 48, height: 48)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .clipShape(.rect(cornerRadius: 10))
                .accessibilityHidden(true)
            Text(item.offer.name).font(.subheadline.weight(.medium))
                .lineLimit(1).truncationMode(.middle)
        }
        .task(id: item.url) {
            // Ask Quick Look for a bounded thumbnail instead of loading the original.
            let request = QLThumbnailGenerator.Request(fileAt: item.url, size: CGSize(width: 256, height: 256),
                                                       scale: 2, representationTypes: .thumbnail)
            let result = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            if !Task.isCancelled { thumbnail = result?.nsImage }
        }
    }
}

struct FilePreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = true
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) { view.previewItem = url as NSURL }
}
