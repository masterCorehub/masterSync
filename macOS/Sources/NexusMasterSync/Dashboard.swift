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
    @State private var scanModal: ReceivedFile?
    @State private var seenScans: Set<String>?
    @State private var imported = false
    @State private var targetingPhoneDrop = false
    @AppStorage("android-launcher-pins") private var storedLauncherPins = Data()
    @State private var chatDraft = ""
    @State private var peerSearch = ""
    @State private var targetingFiles = false
    @State private var notificationsWidth: CGFloat = 0
    @State private var remoteWidth: CGFloat = 0
    @State private var miniPresentation = MiniPlayerPresentation()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showNotices = false
    @State private var connectionGuide = false
    /// Non-nil while the first-run flow (welcome → connect → features) is showing; nil for the plain connection guide.
    @State private var onboardingStep: OnboardingStep?
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
        HStack(spacing: 0) {
            Sidebar(model: model, pinnedApps: sidebarPinnedApps,
                    openApp: { app in
                        if canLaunchApps { model.launchAndroidApp(app); model.section = .remote } else { model.section = .apps }
                    },
                    manageApps: { model.section = .apps })
            VStack(spacing: 0) {
                ContentHeader(model: model, gallery: model.gallery, notificationButton: AnyView(notificationButton))
                    .padding(.horizontal, 26)

                if model.section == .conversation {
                    conversationPanel
                        .padding(.horizontal, 26)
                        .padding(.bottom, 26)
                        .onChange(of: model.selected?.id) { _, _ in chatDraft = "" }
                } else if model.section == .sms {
                    SmsScreen(model: model, sms: model.sms)
                        .padding(.horizontal, 26)
                        .padding(.bottom, 26)
                } else {
                    dashboardContent
                }

                if model.section == .devices {
                    ConnectionBar(model: model) { imported = true }
                        .padding(.horizontal, 23).padding(.top, 12).padding(.bottom, 19)
                }
            }
            .padding(.bottom, miniPlayerReserve)
        }
        .background { NexusBackdrop() }
        .onAppear { if seenScans == nil { seenScans = Set(scanPageIDs) } }
        .onChange(of: scanPageIDs) { _, ids in
            let known = seenScans ?? []
            seenScans = known.union(ids)
            if let id = ScanActions.newPage(known: known, current: ids), let page = model.files.received.first(where: { $0.id == id }) {
                scanModal = page
            }
        }
        .sheet(item: $scanModal) { page in
            ScanModal(file: page, canSend: model.canSendFiles,
                      onSend: { model.sendScanToConversation(page) },
                      onDelete: { model.files.trashReceived(page.id) })
        }
        .overlay {
            GeometryReader { area in
                miniPlayerOverlay(maxHeight: max(160, area.size.height - 40))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Text(toast)
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(palette.ink)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .overlay { Capsule().strokeBorder(palette.line) }
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
                    .onTapGesture { model.actionFeedback = nil; model.cameraFeedback = nil }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.toast)
        .task { volume = await outputVolume() }
        .task(id: model.selected?.id) {
            while !Task.isCancelled {
                model.refreshMedia()
                model.refreshDeviceControls()
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
        .task(id: model.launcherAvailable && !(model.selected?.id ?? "").isEmpty ? model.selected?.id ?? "" : "") { model.refreshLauncher() }
        .task(id: launcherIconsKey) { model.requestLauncherIcons(for: launcherPins[model.selected?.id ?? ""] ?? []) }
        .task(id: model.section == .overview && model.canBrowseGallery) {
            // Keeps "Fotos recentes" current while the home screen is open.
            while !Task.isCancelled, model.section == .overview, model.canBrowseGallery {
                model.gallery.refreshIfStale(maxAge: 20)
                try? await Task.sleep(for: .seconds(20))
            }
        }
        .task(id: shortcutsKey) {
            let peer = model.selected?.id ?? ""
            model.syncAppShortcuts(peer: peer, pinned: AppsCatalog.pinned(model.launcherLists[peer] ?? [], ids: launcherPins[peer] ?? []))
        }
        .foregroundStyle(palette.ink)
        .tint(accent)
        .toggleStyle(GlassToggleStyle())
        .onChange(of: model.latestInstantPhoto?.id) { _, _ in
            if let photo = model.latestInstantPhoto { preview = photo.url }
        }
        .fileImporter(isPresented: $imported, allowedContentTypes: [.item, .folder], allowsMultipleSelection: true) {
            switch $0 {
            case .success(let urls): model.sendItems(urls)
            case .failure(let error): model.problem = error.localizedDescription
            }
        }
        .task {
            if !seenConnectionGuide {
                seenConnectionGuide = true
                if OnboardingFlow.shouldAutoShow(seen: false, networkConsent: networkConsent, hasPeers: !model.peers.isEmpty) {
                    onboardingStep = .welcome
                    connectionGuide = true
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { connectionGuide || model.invitation != nil || model.pending != nil },
            set: { if !$0 { closeConnectionGuide() } }
        )) {
            if connectionGuide {
                switch onboardingStep {
                case .welcome:
                    OnboardingWelcomeStep(onStart: { onboardingStep = .connect }, onSkip: { closeConnectionGuide() })
                        .frame(width: 480)
                case .features:
                    OnboardingFeaturesStep(model: model, onFinish: { closeConnectionGuide(); model.section = .overview })
                        .frame(width: 480)
                default:
                    connectionOnboarding
                }
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
                SnapshotAwareScroll {
                    VStack(alignment: .leading, spacing: 20) {
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
                        case .devices: devices.frame(maxWidth: 760, alignment: .leading)
                        case .clipboard: clipboard.frame(maxWidth: 760, alignment: .leading)
                        case .gallery: gallery
                        case .files: files
                        case .notifications: notifications
                        case .remote: remote
                        case .settings: settings.frame(maxWidth: 760, alignment: .leading)
                        case .apps: appsScreen
                        case .sms: EmptyView()
                        case .calls, .webcam: ComingSoonView(section: model.section)
                        }
                    }
                    .padding(.horizontal, 26)
                    .padding(.top, 4)
                    .padding(.bottom, 26)
                    .frame(maxWidth: 1650, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .id(model.section)
            }
        }
    }

    private func overview(size: CGSize) -> some View {
        let phone = model.selected?.name ?? "Seu Android"
        // The phone's latest photos when the gallery is on; otherwise the photos received on this Mac.
        let recent: [OverviewPhoto] = model.canBrowseGallery
            ? model.gallery.items.prefix(5).map { OverviewPhoto(id: $0.id, image: model.gallery.thumbnails[$0.id], isVideo: !$0.mime.hasPrefix("image/")) }
            : mediaFiles.prefix(5).map { OverviewPhoto(id: $0.id, image: NSImage(contentsOf: $0.url), isVideo: $0.offer.mime.hasPrefix("video/")) }
        let data = OverviewData(
            name: phone, active: model.active, battery: model.selectedStatus?.battery, charging: model.selectedStatus?.charging == true,
            controls: QuickControls.items(model.quickControlInputs),
            notices: model.notifications.notices.filter { $0.peer == model.selected?.id }, recent: recent,
            audioOutput: MediaOutput.current(audioOnlyActive: model.screen.audioOnlyActive, controlActive: model.screen.usbActive),
            audioBusy: model.screen.connecting, audioLocked: model.screen.usbActive && !model.screen.audioOnlyActive)
        var actions = OverviewActions()
        actions.control = { model.section = .remote }
        actions.sendFile = model.canSendFiles ? { imported = true } : nil
        actions.photo = model.canRequestPhoto && !model.cameraPending ? { model.requestInstantPhoto() } : nil
        actions.scan = model.canRequestScan ? { model.requestScan() } : nil
        actions.scanHint = model.active ? "Ative Arquivos e Digitalizar no celular" : "Conecte o celular"
        actions.sendFileHint = model.active ? "Ative Arquivos nos dois lados" : "Conecte o celular"
        actions.photoHint = model.active ? "Ative a câmera remota no celular" : "Conecte o celular"
        actions.pressControl = { model.pressQuickControl($0) }
        actions.chooseOutput = { chooseAudioOutput($0) }
        actions.openNotifications = { model.section = .notifications }
        actions.discardNotice = { model.notifications.discard($0) }
        actions.clearNotices = { if let peer = model.selected?.id { model.notifications.clearAll(peer: peer) } }
        actions.openGallery = { model.section = .gallery }
        actions.needsThumbnail = { id in if model.canBrowseGallery { model.gallery.thumbnail(id) } }
        actions.dropFiles = model.canSendFiles ? { model.sendDroppedFiles($0) } : nil
        let extras = AnyView(VStack(alignment: .leading, spacing: 12) {
            if !model.active {
                Button("Conectar Android") { connectionGuide = true }
                    .buttonStyle(NexusPillStyle(prominent: true, compact: true))
            }
            if let peer = model.selected?.id, model.active, let alert = model.batteryMessages[peer] {
                Label(alert, systemImage: "battery.25percent")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(palette.accent)
            }
        })
        return OverviewScreen(data: data, actions: actions, extras: extras)
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

    private var appsScreen: some View {
        let peer = model.selected?.id ?? ""
        let apps = model.launcherLists[peer] ?? []
        let pins = launcherPins[peer] ?? []
        let screen = model.screen
        var actions = AppsScreenActions()
        actions.open = { app in
            model.launchAndroidApp(app)
            model.section = .remote
        }
        actions.togglePin = { id in setPinned(id, peer: peer, pinned: !pins.contains(id)) }
        actions.refresh = { model.refreshLauncher() }
        actions.setupWireless = { openWirelessControlGuide() }
        actions.focusSession = { model.section = .remote }
        actions.closeSession = { screen.endAll() }
        let session: AppsSession? = (screen.inAppControl || screen.inAppStarting || (screen.controlling && screen.sharing))
            ? AppsSession(title: "Controle do celular", state: screen.inAppStarting ? "Conectando…" : "Em andamento") : nil
        let data = AppsScreenData(
            phoneName: model.selected?.name ?? "celular", apps: apps, listLoaded: model.launcherLists[peer] != nil, pins: pins,
            icons: model.launcherIcons, active: model.active, launcherAvailable: model.launcherAvailable, canLaunch: canLaunchApps,
            needsWirelessSetup: model.wirelessControlDevice(for: peer) == nil, session: session)
        return AppsScreen(data: data, actions: actions)
    }

    /// Changes when the pins, the phone or the phone's app list change, so icons are requested for what the side bar shows.
    private var launcherIconsKey: [String] {
        let peer = model.selected?.id ?? ""
        return (launcherPins[peer] ?? []) + [peer, model.launcherLists[peer] == nil ? "" : "ready"]
    }

    /// Changes when the pins, the app list, the icons that arrived or the option change, so the Mac apps are rebuilt then.
    private var shortcutsKey: [String] {
        launcherIconsKey + ["\(model.launcherIcons.count)", model.shortcutsEnabled ? "on" : "off"]
    }

    private var sidebarPinnedApps: [AndroidApp] {
        let peer = model.selected?.id ?? ""
        let apps = model.launcherLists[peer] ?? []
        return AppsCatalog.sidebarPins(AppsCatalog.pinned(apps, ids: launcherPins[peer] ?? []))
    }

    private var canLaunchApps: Bool {
        (model.canMirror || model.screen.inAppAvailable) && model.wirelessControlDevice(for: model.selected?.id) != nil
            && !model.screen.preparingControl && !model.screen.inAppStarting
    }

    /// The floating player: the phone's current track, collapsed or expanded, with the sound output choice.
    @ViewBuilder private func miniPlayerOverlay(maxHeight: CGFloat) -> some View {
        let screen = model.screen
        let media = model.currentMediaState
        let track = MiniPlayerPresentation.trackKey(title: media?.title, artist: media?.artist)
        let mode = miniPresentation.view(hasMedia: media != nil, track: track)
        if let media, mode != .hidden {
            let output = MediaOutput.current(audioOnlyActive: screen.audioOnlyActive, controlActive: screen.usbActive)
            MiniPlayer(
                state: media, art: media.artKey.flatMap { model.mediaArt[$0] }, phoneName: model.selected?.name ?? "Celular",
                queue: model.mediaQueue, queueActive: model.mediaQueueActive, output: output, connecting: screen.connecting,
                canControl: model.canPlayMedia,
                // A scrcpy control window already owns the audio; ending it is done from its own button.
                canChooseOutput: !(screen.usbActive && !screen.audioOnlyActive), expanded: mode == .full,
                volume: output == .mac ? volume : nil,
                onVolume: { level in Task { volume = await outputVolume(setTo: Int(level)) } },
                onCommand: { model.mediaControl($0) }, onSeek: { model.mediaSeek(toFraction: $0) },
                onLike: { model.mediaLike($0) }, onOpenQueue: { model.mediaQueueRefresh() },
                onPick: { model.mediaPlay(queueItem: $0) },
                onOutput: { chooseAudioOutput($0) },
                onToggleExpanded: { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { miniPresentation.toggleExpanded() } },
                onClose: { miniPresentation.dismiss(track: track) }, maxHeight: maxHeight)
            .padding(.trailing, 24).padding(.bottom, 20)
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .bottomTrailing)))
        }
    }

    /// Sends the phone's sound to the Mac (through an audio-only scrcpy session) or back to the phone.
    private func chooseAudioOutput(_ target: MediaOutput) {
        switch target {
        case .mac:
            if let device = model.wirelessControlDevice(for: model.selected?.id) {
                model.screen.launchScrcpy(audioOnly: true, wireless: device)
            } else { openWirelessControlGuide() }
        case .phone:
            model.screen.stopUSB()
        }
    }

    /// Room kept under the screens so the collapsed player does not cover their lower right corner.
    private var miniPlayerReserve: CGFloat {
        let media = model.currentMediaState
        let track = MiniPlayerPresentation.trackKey(title: media?.title, artist: media?.artist)
        return miniPresentation.view(hasMedia: media != nil, track: track) == .mini ? 84 : 0
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

    /// The phone in its frame: live control in the app, the screen-sharing picture, or the start prompt.
    private func embeddedPhone(height: CGFloat = 600) -> some View {
        let screen = model.screen
        let width = height * 292 / 600
        let outer = height * 44 / 600
        return ZStack {
            RoundedRectangle(cornerRadius: outer, style: .continuous).fill(Color(red: 0.04, green: 0.043, blue: 0.055))
            ZStack {
                Color.black
                if screen.inAppControl {
                    PhoneDisplay(model: screen.display)
                        .accessibilityLabel("Tela interativa do Android")
                } else if let frame = screen.frame {
                    GeometryReader { canvas in
                        let ratio = frame.size.width / max(frame.size.height, 1)
                        let fitWidth = min(canvas.size.width, canvas.size.height * ratio)
                        let fitHeight = fitWidth / max(ratio, 0.01)
                        Image(nsImage: frame).resizable().scaledToFit()
                            .frame(width: fitWidth, height: fitHeight)
                            .contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0).onEnded { gesture in
                                // The fit rectangle excludes the black bars from touch input.
                                guard fitWidth > 0, fitHeight > 0 else { return }
                                screen.gesture(from: CGPoint(x: gesture.startLocation.x / fitWidth,
                                                             y: gesture.startLocation.y / fitHeight),
                                               to: CGPoint(x: gesture.location.x / fitWidth, y: gesture.location.y / fitHeight))
                            })
                            .position(x: canvas.size.width / 2, y: canvas.size.height / 2)
                            .accessibilityLabel("Tela interativa do Android")
                    }
                    if !screen.controlling && !screen.preparingControl {
                        embeddedControlButton
                    }
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "cast").font(.system(size: 36)).foregroundStyle(.white.opacity(0.8))
                            .accessibilityHidden(true)
                        if screen.preparingControl || screen.requesting || screen.sharing || screen.inAppStarting {
                            ProgressView().controlSize(.small)
                            Text(screen.requesting ? "Autorize no Android" : "Conectando…")
                                .font(.system(size: 13)).foregroundStyle(.white)
                        } else {
                            Text("Tela do \(model.selected?.name ?? "celular") pronta")
                                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                            embeddedControlButton
                            if !canStartControl {
                                Text(model.active ? "Autorize o espelhamento no Android." : "Conecte seu Android para começar.")
                                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: outer - 9, style: .continuous))
            .padding(10)
        }
        .frame(width: width, height: height)
        .overlay { RoundedRectangle(cornerRadius: outer, style: .continuous).strokeBorder(.white.opacity(0.12)).allowsHitTesting(false) }
        .shadow(color: .black.opacity(0.4), radius: 28, y: 18)
        .dropDestination(for: URL.self) { urls, _ in
            targetingPhoneDrop = false
            return model.sendDroppedFiles(urls)
        } isTargeted: { targetingPhoneDrop = $0 && model.canSendFiles }
        .overlay {
            if targetingPhoneDrop {
                RoundedRectangle(cornerRadius: outer, style: .continuous)
                    .strokeBorder(palette.accent, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                    .background(palette.accentSurface.opacity(0.9), in: RoundedRectangle(cornerRadius: outer, style: .continuous))
                    .overlay {
                        Label("Solte para enviar", systemImage: "arrow.up.circle")
                            .font(.headline).foregroundStyle(palette.accent)
                    }
                    .allowsHitTesting(false)
            }
        }
    }

    private var canStartControl: Bool {
        model.canMirror || (model.screen.inAppAvailable && model.wirelessControlDevice(for: model.selected?.id) != nil)
    }

    private func startControl() {
        guard let peer = model.selected?.id else { return }
        if let device = model.wirelessControlDevice(for: peer) {
            switch ScreenMirror.controlRoute(hasWirelessADB: true, scrcpyInstalled: model.screen.scrcpyInstalled,
                                             inAppAvailable: model.screen.inAppAvailable) {
            case .inApp: model.screen.beginInAppControl(wireless: device)
            case .scrcpy: model.screen.launchScrcpy(audioOnly: false, wireless: device)
            case .mirror: model.screen.beginControl(peer, wireless: device)
            }
        } else { openWirelessControlGuide() }
    }

    private var embeddedControlButton: some View {
        Button { startControl() } label: { Text("Controlar").font(.system(size: 13, weight: .bold)) }
            .buttonStyle(NexusPillStyle(prominent: true))
            // Control over ADB needs no screen-sharing permission on the phone.
            .disabled(!canStartControl)
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
        let incoming = model.files.received.filter { $0.peerID == peer && ScanActions.belongsInConversation($0) }.map { ConversationEntry.file($0, outgoing: false) }
        let outgoing = model.files.sent.filter { $0.peerID == peer }.map { ConversationEntry.file($0, outgoing: true) }
        return Array((texts + incoming + outgoing).sorted { $0.date < $1.date }.suffix(60))
    }

    private var conversationPanel: some View {
        GeometryReader { area in
            HStack(spacing: 16) {
                if area.size.width >= 700 { conversationList.frame(width: 280) }
                conversationThread
            }
        }
        .frame(maxWidth: 1200, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    private func hue(for id: String) -> Double { NexusPalette.stableHue(id) }

    private var conversationList: some View {
        let peers = model.peers.filter { peerSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(peerSearch) }
        return VStack(spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(palette.muted)
                TextField("Buscar conversas", text: $peerSearch).textFieldStyle(.plain)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(palette.input, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.bottom, 6)
            if peers.isEmpty {
                Text(model.peers.isEmpty ? "Nenhum celular pareado." : "Nenhuma conversa encontrada.")
                    .font(.system(size: 12.5)).foregroundStyle(palette.muted).padding(.top, 20)
            }
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(peers) { peer in
                        let last = (model.messages.filter { $0.peer == peer.id }.map { ($0.date, ($0.outgoing ? "Você: " : "") + $0.text) }
                            + model.files.received.filter { $0.peerID == peer.id }.map { ($0.date, $0.offer.name) })
                            .max { $0.0 < $1.0 }
                        Button { model.selectedID = peer.id } label: {
                            HStack(spacing: 10) {
                                Avatar(initials: initials(peer.name), hue: hue(for: peer.id), size: 38)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(peer.name).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                                        Spacer(minLength: 6)
                                        if let last { Text(last.0, style: .time).font(.system(size: 11)).foregroundStyle(palette.faint) }
                                    }
                                    Text(last.map { Wire.visible($0.1, limit: 80) } ?? (model.online.contains(peer.id) ? "Conectado" : "Desconectado"))
                                        .font(.system(size: 12.5)).foregroundStyle(palette.muted).lineLimit(1)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(model.selected?.id == peer.id ? palette.active : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(model.selected?.id == peer.id ? .isSelected : [])
                    }
                }
            }
        }
        .padding(8)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassPanel(radius: 20)
    }

    private var conversationThread: some View {
        let entries = conversationEntries
        let phone = model.selected?.name ?? "Conversa"
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Avatar(initials: initials(phone), hue: hue(for: model.selected?.id ?? ""), size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(phone).font(.system(size: 14, weight: .bold)).lineLimit(1)
                    Text(model.active ? "Conectado · Wi‑Fi" : "Desconectado")
                        .font(.system(size: 11.5)).foregroundStyle(model.active ? palette.accent : palette.muted)
                }
                Spacer()
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            Rectangle().fill(palette.line).frame(height: 1)
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if entries.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "bubble.left.and.bubble.right").font(.title2)
                                empty("Envie uma mensagem ou um arquivo para o Android.")
                            }
                            .foregroundStyle(palette.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 54)
                        }
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            if index == 0 || !calendar.isDate(entries[index - 1].date, inSameDayAs: entry.date) {
                                Text(entry.date, style: .date)
                                    .font(.system(size: 11)).foregroundStyle(palette.faint)
                                    .padding(.bottom, 6)
                            }
                            conversationBubble(entry).id(entry.id)
                        }
                    }
                    .padding(18)
                }
                .frame(maxHeight: .infinity)
                .onChange(of: entries.last?.id, initial: true) { _, id in
                    if let id { scroll.scrollTo(id, anchor: .bottom) }
                }
            }
            Rectangle().fill(palette.line).frame(height: 1)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Button { imported = true } label: {
                        Image(systemName: "plus.circle").font(.system(size: 21)).foregroundStyle(palette.muted)
                    }
                    .buttonStyle(.plain).disabled(!model.canSendFiles)
                    .help("Enviar arquivo").accessibilityLabel("Enviar arquivo")
                    TextField(model.canChat ? "Mensagem" : "Conversa indisponível", text: $chatDraft)
                        .textFieldStyle(.plain).font(.system(size: 13.5))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(palette.input, in: Capsule())
                        .overlay { Capsule().strokeBorder(palette.line) }
                        .disabled(!model.canChat)
                        .onSubmit { sendChatDraft() }
                    Button { sendChatDraft() } label: {
                        Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold)).foregroundStyle(palette.accentInk)
                            .frame(width: 36, height: 36).background(palette.fill, in: Circle())
                    }
                    .buttonStyle(.plain)
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
            .padding(12)
        }
        .frame(maxHeight: .infinity)
        .glassPanel(radius: 20)
    }

    private func sendChatDraft() {
        if model.sendChat(chatDraft) { chatDraft = "" }
    }

    private func conversationBubble(_ entry: ConversationEntry) -> some View {
        let mine = entry.outgoing
        let shape = UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: mine ? 18 : 6,
                                           bottomTrailingRadius: mine ? 6 : 18, topTrailingRadius: 18, style: .continuous)
        return VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ChatMedia.senderName(outgoing: mine, local: ChatMedia.localDeviceName, peer: model.selected?.name ?? ""))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(mine ? palette.accentInk.opacity(0.7) : palette.muted).lineLimit(1)
                switch entry {
                case .text(let message):
                    Text(message.text).font(.system(size: 13.5)).lineSpacing(2).textSelection(.enabled)
                case .file(let item, _):
                    if ChatMedia.isImage(mime: item.offer.mime) {
                        ChatImage(item: item) { preview = item.url }
                    } else {
                        Button { preview = item.url } label: {
                            Label(item.offer.name, systemImage: "doc").lineLimit(2)
                        }
                        .buttonStyle(.plain).disabled(!FileManager.default.fileExists(atPath: item.url.path))
                    }
                }
            }
            .foregroundStyle(mine ? palette.accentInk : palette.ink)
            .padding(.vertical, 9).padding(.horizontal, 13)
            .background(mine ? palette.fill : palette.panel2, in: shape)
            .overlay { if !mine { shape.strokeBorder(palette.line) } }
            HStack(spacing: 6) {
                Text(entry.date, style: .time)
                if case .text(let message) = entry, mine, !message.confirmed { Text("Sem confirmação").foregroundStyle(palette.muted) }
            }
            .font(.system(size: 10.5)).foregroundStyle(palette.faint).padding(.horizontal, 6)
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
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
            Image(systemName: notice.canDismiss ? "xmark" : "eye.slash")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.faint)
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                Toggle("Sincronizar texto e imagens", isOn: Binding(get: { model.clipboardSyncActive }, set: { model.setClipboardSync($0) }))
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
        FilesScreen(model: model, files: model.files, pixel: model.pixelFiles, chooseFiles: { imported = true })
    }

    private var notifications: some View {
        let notices = model.notifications.notices.filter { $0.peer == model.selected?.id }
        let sideBySide = notificationsWidth >= 640
        let layout = sideBySide ? AnyLayout(HStackLayout(alignment: .top, spacing: 16)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
        return VStack(alignment: .leading, spacing: 0) {
            WidthProbe(width: $notificationsWidth)
            layout {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    clearAllNoticesButton
                    if model.canRefreshNotices && model.notificationsEnabled {
                        Button { model.refreshNotices() } label: { Label("Atualizar", systemImage: "arrow.clockwise") }
                            .buttonStyle(NexusPillStyle(compact: true))
                    }
                    Spacer()
                }
                notificationFeedback
                if notices.isEmpty {
                    Text(model.active ? "Tudo em dia." : "Conecte o Android para ver as notificações.")
                        .font(.system(size: 13)).foregroundStyle(palette.muted)
                        .frame(maxWidth: .infinity).padding(40)
                }
                ForEach(notices) { notice in
                    HStack(alignment: .top, spacing: 12) {
                        Group {
                            if let icon = notice.icon {
                                Image(nsImage: icon).resizable().scaledToFit().padding(4)
                            } else {
                                Text(String(notice.app.prefix(1)).uppercased()).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                            }
                        }
                        .frame(width: 38, height: 38)
                        .background(notice.icon == nil ? NexusPalette.hueColor(hue(for: notice.app)) : palette.panel2,
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(notice.app).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(palette.muted)
                                Spacer()
                                Text(notice.date, style: .time).font(.system(size: 11)).foregroundStyle(palette.faint)
                            }
                            Text(notice.title).font(.system(size: 13.5, weight: .semibold))
                            if !notice.body.isEmpty {
                                Text(notice.body).font(.system(size: 13)).foregroundStyle(palette.muted).lineSpacing(2)
                            }
                            if notice.canReply {
                                Button("Responder") { replyText = ""; replyNotice = notice }
                                    .buttonStyle(NexusPillStyle(compact: true)).padding(.top, 4)
                            }
                        }
                        dismissNoticeButton(notice)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassPanel(radius: 18)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    SwitchRow(title: "Receber do Android", subtitle: "Espelha as notificações neste Mac", isOn: $model.notificationsEnabled)
                    SwitchRow(title: "Ocultar conteúdo", subtitle: "Mostra só o nome do app", isOn: $model.hideNotices)
                    SwitchRow(title: "Não Perturbe no Android", subtitle: "Silencia o celular", isOn: Binding(
                        get: { model.androidDnd?.dndEnabled == true }, set: { model.setAndroidDnd($0) }))
                        .disabled(!model.active || model.androidDnd?.dndAllowed != true)
                    SwitchRow(title: "Silenciar avisos no Mac", isOn: $model.quiet)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Estilo dos avisos").font(.system(size: 13, weight: .semibold))
                        HStack(spacing: 8) {
                            ForEach(NoticeStyle.allCases, id: \.rawValue) { style in
                                Button(style.title) { model.noticeStyle = style }
                                    .buttonStyle(NexusPillStyle(selected: model.noticeStyle == style, compact: true))
                                    .accessibilityAddTraits(model.noticeStyle == style ? .isSelected : [])
                            }
                        }
                        Text(model.noticeStyle == .custom ? "Um cartão no canto da tela, com o ícone do app do celular."
                             : "O aviso do macOS (o ícone do app aparece como imagem ao lado).")
                            .font(.system(size: 11.5)).foregroundStyle(palette.muted)
                    }
                    .padding(.vertical, 10)
                    SwitchRow(title: "Copiar códigos de verificação", subtitle: "Copia o código de SMS e e-mails e avisa no canto da tela",
                              isOn: $model.codeAutofill, showsDivider: false)
                    Button("Autorizar Central de Notificações") { model.notifications.askPermission() }
                        .buttonStyle(NexusPillStyle(compact: true)).padding(.vertical, 10)
                    if let status = model.notifications.authorization { empty(status).font(.system(size: 11.5)) }
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
                .glassPanel(radius: 20)
                if !model.notifications.apps.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Espelhar notificações de").font(.system(size: 13, weight: .bold)).padding(.bottom, 8)
                        ForEach(model.notifications.apps.keys.sorted(), id: \.self) { key in
                            let name = model.notifications.apps[key] ?? key
                            HStack(spacing: 10) {
                                Text(String(name.prefix(1)).uppercased())
                                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: 26, height: 26)
                                    .background(NexusPalette.hueColor(hue(for: key)), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                Text(name).font(.system(size: 13)).lineLimit(1)
                                Spacer()
                                GlassToggle(isOn: Binding(
                                    get: { !model.blockedApps.contains(key) },
                                    set: { if $0 { model.blockedApps.remove(key) } else { model.blockedApps.insert(key) } }), label: name)
                            }
                            .padding(.vertical, 8)
                            .overlay(alignment: .top) { Rectangle().fill(palette.line).frame(height: 1) }
                        }
                    }
                    .padding(16)
                    .glassPanel(radius: 20)
                }
            }
            .frame(width: sideBySide ? 300 : nil)
            }
        }
    }

    private var remote: some View {
        let screen = model.screen
        let controlActive = (screen.controlling && screen.sharing) || screen.inAppControl
        let live = controlActive || screen.usbActive
        let route = ScreenMirror.controlRoute(hasWirelessADB: model.wirelessControlDevice(for: model.selected?.id) != nil,
                                              scrcpyInstalled: screen.scrcpyInstalled, inAppAvailable: screen.inAppAvailable)
        let tools: [(String, String, Bool, () -> Void)] = [
            ("house", "Início", controlActive, { screen.pressSystemKey(home: true) }),
            ("chevron.left", "Voltar", controlActive, { screen.pressSystemKey(home: false) }),
            ("bell.badge", "Tocar celular", model.canFindPhone, { model.findPhone() }),
            ("arrow.up.doc", "Enviar arquivo", model.canSendFiles, { imported = true }),
            ("macwindow", "Janela separada", !(screen.connecting || (screen.usbActive && screen.audioOnlyActive)), {
                if screen.usbActive && !screen.audioOnlyActive { screen.stopUSB() }
                else if let device = model.wirelessControlDevice(for: model.selected?.id) { screen.launchScrcpy(audioOnly: false, wireless: device) }
                else { openWirelessControlGuide() }
            }),
            ("speaker.wave.2", "Ouvir no Mac", !(screen.connecting || (screen.usbActive && !screen.audioOnlyActive)), {
                if screen.usbActive && screen.audioOnlyActive { screen.stopUSB() }
                else if let device = model.wirelessControlDevice(for: model.selected?.id) { screen.launchScrcpy(audioOnly: true, wireless: device) }
                else { openWirelessControlGuide() }
            }),
        ]
        // One layout whose arrangement changes with the width, so the phone view is never built twice.
        let sideBySide = remoteWidth >= 676
        let layout = sideBySide ? AnyLayout(HStackLayout(alignment: .top, spacing: 16)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
        return VStack(alignment: .leading, spacing: 0) {
            WidthProbe(width: $remoteWidth)
            layout {
                remotePhoneStage
                remoteSide(live: live, controlActive: controlActive, route: route, tools: tools)
                    .frame(width: sideBySide ? 300 : nil)
            }
        }
    }

    private var remotePhoneStage: some View {
        embeddedPhone(height: 600)
            .frame(maxWidth: .infinity, minHeight: 640)
            .padding(.vertical, 20)
            .glassPanel(radius: 22)
    }

    private func remoteSide(live: Bool, controlActive: Bool, route: ScreenMirror.ControlRoute,
                            tools: [(String, String, Bool, () -> Void)]) -> some View {
        let screen = model.screen
        let routeName = switch route {
        case .inApp: "Dentro do app"
        case .scrcpy: "Janela do scrcpy"
        case .mirror: "Compartilhamento de tela"
        }
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    StatusDot(color: live ? .red : palette.fill, pulsing: live, size: 8)
                    Text(live ? "Controle ao vivo" : (model.active ? "Pronto para controlar" : "Aguardando conexão"))
                        .font(.system(size: 13, weight: .bold))
                }
                Text("Use mouse e teclado do Mac para controlar o celular. Clique direito é Voltar; arraste arquivos para a tela para enviá-los.")
                    .font(.system(size: 12.5)).foregroundStyle(palette.muted).lineSpacing(2)
                Button {
                    if controlActive || screen.inAppStarting { screen.endAll() } else { startControl() }
                } label: {
                    Text(controlActive || screen.inAppStarting ? "Encerrar controle" : "Iniciar controle")
                        .font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(palette.panel2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.line) }
                }
                .buttonStyle(.plain)
                .disabled(!(controlActive || screen.inAppStarting || canStartControl))
                if screen.connecting { ProgressView("Conectando ao Android…").controlSize(.small) }
                if let feedback = screen.feedback, !screen.requesting { empty(feedback).font(.system(size: 12)) }
            }
            .padding(16)
            .glassPanel(radius: 20)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(Array(tools.enumerated()), id: \.offset) { _, tool in
                    Button { tool.3() } label: {
                        VStack(spacing: 6) {
                            Image(systemName: tool.0).font(.system(size: 18))
                            Text(tool.1).font(.system(size: 11.5)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!tool.2).opacity(tool.2 ? 1 : 0.4)
                    .accessibilityLabel(tool.1)
                }
            }
            .padding(10)
            .glassPanel(radius: 20)

            VStack(alignment: .leading, spacing: 8) {
                infoRow("Aparelho", model.selected?.name ?? "—")
                infoRow("Rota", routeName)
                infoRow("Conexão", model.active ? "Rede local" : "Desconectado")
                HStack(spacing: 8) {
                    if screen.requesting {
                        ProgressView().controlSize(.small)
                        Text("Autorize a prévia no Android.").font(.system(size: 12)).foregroundStyle(palette.muted)
                    } else if screen.sharing {
                        Button("Parar prévia") { screen.end() }.buttonStyle(NexusPillStyle(compact: true))
                        Button("Ampliar") { openWindow(id: "mirror") }.buttonStyle(NexusPillStyle(compact: true))
                    } else {
                        Button("Mostrar prévia") { model.requestMirror() }
                            .buttonStyle(NexusPillStyle(compact: true)).disabled(!model.canMirror)
                            .help("Autorize o espelhamento no Android para mostrar a prévia.")
                    }
                    Spacer()
                    Menu {
                        Button("Configurar Wi-Fi") { wirelessClipboardSetup = true }
                        Button("Controlar por USB") { screen.launchScrcpy(audioOnly: false) }
                            .disabled(screen.usbActive || screen.connecting)
                        Button("Ouvir por USB") { screen.launchScrcpy(audioOnly: true) }
                            .disabled(screen.usbActive || screen.connecting)
                    } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel("Opções de conexão")
                }
                .padding(.top, 4)
            }
            .font(.system(size: 12.5))
            .padding(16)
            .glassPanel(radius: 20)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(palette.muted)
            Spacer()
            Text(value).lineLimit(1)
        }
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
                Button("Rever introdução") { onboardingStep = .welcome; connectionGuide = true }
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
        onboardingStep = nil
        guidePeer = nil
        model.cancelPair()
    }

    /// Ends the connect step: inside the first-run flow it moves on to the features step, otherwise it just closes.
    private func finishConnectStep() {
        guard onboardingStep != nil else {
            closeConnectionGuide()
            model.section = .overview
            return
        }
        if testingGuideControl { model.screen.end() }
        if testingGuideAudio { model.screen.stopUSB() }
        testingGuideControl = false
        testingGuideAudio = false
        guideControlConfirmed = false
        guideAudioConfirmed = false
        wifiToolsMessage = nil
        guidePeer = nil
        model.cancelPair()
        onboardingStep = .features
    }

    private var connectionOnboarding: some View {
        VStack(alignment: .leading, spacing: 18) {
            if onboardingStep != nil { OnboardingHeader(step: .connect) }
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
                Button(onboardingStep != nil ? "Pular esta etapa" : "Fechar") { finishConnectStep() }
                    .keyboardShortcut(.cancelAction)
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
                    .disabled((!model.canMirror || screen.sharing || screen.preparingControl || screen.inAppControl || screen.inAppStarting)
                              && !testingGuideControl)
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
                finishConnectStep()
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
    private var scanPageIDs: [String] { model.files.received.filter { $0.offer.isScanPage }.map(\.id) }
    private var latestScanPage: ReceivedFile? { model.files.received.first { $0.offer.isScanPage } }

    private func isScan(_ file: ReceivedFile) -> Bool {
        file.offer.isScanPage || file.offer.name.hasPrefix("Digitalização")
    }

    private func card<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconBadge(systemName: icon, size: 28)
                Text(title).font(.system(size: 13, weight: .bold))
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            content()
        }
        .font(.system(size: 13))
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(radius: 20)
    }

    private func empty(_ text: String) -> some View {
        Text(text).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func receivedGallery(_ files: [ReceivedFile], empty hint: String) -> some View {
        if files.isEmpty {
            empty(hint)
        } else {
            LibraryDatePicker(selection: $libraryGrouping)
            ForEach(libraryGrouping.sections(for: files, calendar: calendar, date: { $0.date == .distantPast ? nil : $0.date })) { group in
                if libraryGrouping != .none {
                    LibraryDateHeading(date: group.date, grouping: libraryGrouping)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 14) {
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
                        }
                        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
                    }
                }
            }
        }
    }

}

private struct ReceivedTile: View {
    let item: ReceivedFile
    let palette: NexusPalette
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.panel2)
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
                .clipShape(.rect(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            Text(item.offer.name).font(.system(size: 12, weight: .medium))
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
