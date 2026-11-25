import AppKit
import CoreImage.CIFilterBuiltins
import NexusCore
import Quartz
import SwiftUI
import UniformTypeIdentifiers

struct Dashboard: View {
    @ObservedObject var model: NexusModel
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openWindow) private var openWindow
    @State private var imported = false
    @State private var usbConfirm = false
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
            DashboardHeader(model: model, gallery: model.gallery)
                .padding(.horizontal, 28)
                .padding(.top, 30)
                .padding(.bottom, 18)

            dashboardContent

            // Connection controls stay in reach while the current section scrolls.
            ConnectionBar(model: model) { imported = true }
                .padding(.horizontal, 23).padding(.top, 12).padding(.bottom, 19)
        }
        .background { NexusBackdrop() }
        .foregroundStyle(palette.ink)
        .tint(accent)
        .toggleStyle(.switch)
        .fileImporter(isPresented: $imported, allowedContentTypes: [.item]) {
            switch $0 {
            case .success(let url): model.sendFile(url)
            case .failure(let error): model.problem = error.localizedDescription
            }
        }
        .sheet(isPresented: Binding(get: { model.invitation != nil || model.pending != nil },
                                   set: { if !$0 { model.cancelPair() } })) { pairing }
        .sheet(isPresented: $wirelessClipboardSetup) {
            WirelessClipboardSetup(device: model.adbClipboard.wirelessDevice) { device, pairing in
                model.adbClipboard.startWiFi(device: device, pairing: pairing)
            }
        }
        .confirmationDialog("Abrir controle USB?", isPresented: $usbConfirm) {
            Button("Abrir scrcpy") { model.screen.launchUSB() }
        } message: {
            Text("O scrcpy abre uma janela própria para o aparelho conectado e autorizado via depuração USB.")
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
                    Button("Fechar") { self.preview = nil }.keyboardShortcut(.cancelAction)
                }.padding(15).frame(minWidth: 560, minHeight: 410)
            }
        }
    }

    private var dashboardContent: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.section.rawValue)
                            .font(.system(size: 33, weight: .semibold, design: .rounded))
                            .tracking(-0.75)
                            .accessibilityAddTraits(.isHeader)
                        if model.section == .overview {
                            Text("Acesse o conteúdo e as funções do seu Android neste Mac.")
                                .foregroundStyle(palette.muted)
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
                    case .overview: overview
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

    private var overview: some View {
        VStack(alignment: .leading, spacing: 23) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 140), spacing: 12), count: 4), spacing: 12) {
                shortcut(.gallery, title: "Galeria", detail: "Abra fotos e vídeos", highlighted: true)
                shortcut(.clipboard, title: "Área de transferência", detail: "Sincronize o que copiar")
                shortcut(.documents, title: "Documentos", detail: "Digitalize com o celular")
                shortcut(.files, title: "Arquivos", detail: "Envie e receba arquivos")
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 2),
                      alignment: .leading, spacing: 12) {
                card("Fotos recentes", icon: "photo") {
                    recent(mediaFiles, empty: "As fotos baixadas da Galeria aparecem aqui.")
                }
                card("Documentos recentes", icon: "doc.text") {
                    recent(documentFiles, empty: "As digitalizações recebidas aparecem aqui.")
                }
                card("Últimos itens copiados", icon: Section.clipboard.icon) {
                    if model.clipboard.items.isEmpty { empty("O histórico está vazio.") }
                    ForEach(model.clipboard.items.prefix(3)) { item in
                        Text(item.text).lineLimit(1).foregroundStyle(palette.muted)
                    }
                }
                card("Atividade", icon: "clock.arrow.circlepath") {
                    if model.events.isEmpty { empty("A atividade aparece após o pareamento.") }
                    ForEach(model.events.prefix(4)) { event in
                        HStack {
                            Label(event.title, systemImage: event.icon).lineLimit(1)
                            Spacer()
                            Text(event.date, style: .time).foregroundStyle(palette.muted).font(.caption)
                        }
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
                if model.serviceReady {
                    HStack {
                        Button("Gerar QR") { model.pair() }.buttonStyle(NexusPillStyle(prominent: true))
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
                        model.adbClipboard.stop()
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
            card("Scanner do Android", icon: Section.documents.icon) {
                Text("Autorize solicitações de digitalização no celular. O scanner abre após confirmação no Android.")
                    .foregroundStyle(palette.muted)
                Button("Solicitar digitalização") { model.requestScan() }
                    .buttonStyle(NexusPillStyle(prominent: true)).disabled(!model.canRequestScan)
                if let feedback = model.scanRequestFeedback { empty(feedback) }
            }
            card("Documentos recebidos", icon: "tray.and.arrow.down") {
                receivedByDate(documentFiles, empty: "Nenhum documento recebido.")
            }
        }
    }

    private var gallery: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.canBrowseGallery {
                Toggle("Biblioteca do Android", isOn: $model.galleryEnabled)
                GalleryBrowser(gallery: model.gallery, files: model.files, canTransfer: model.canSendFiles,
                               grouping: $libraryGrouping)
            } else {
                card("Biblioteca do Android", icon: "albums") {
                    Toggle("Navegar na galeria do Android", isOn: $model.galleryEnabled)
                    empty("Ative a galeria nos dois dispositivos e autorize as fotos ou os vídeos no Android.")
                    if !model.active {
                        Button("Abrir dispositivos") { model.section = .devices }.buttonStyle(NexusPillStyle(compact: true))
                    }
                }
            }
            card("Fotos e vídeos recebidos", icon: "tray.and.arrow.down") {
                receivedByDate(mediaFiles, empty: "Os originais baixados aparecem aqui.")
            }
        }
    }

    private var files: some View {
        VStack(alignment: .leading, spacing: 14) {
            card("Transferência local", icon: "arrow.up.arrow.down") {
                Toggle("Permitir envio e recebimento de arquivos", isOn: $model.filesEnabled)
                Text("Ative arquivos nos dois dispositivos. Envie um arquivo de até 4 GB por vez para cada celular.")
                    .foregroundStyle(palette.muted)
                Button("Escolher arquivo…") { imported = true }
                    .buttonStyle(NexusPillStyle(prominent: true)).disabled(!model.canSendFiles)
                if let feedback = model.files.feedback { empty(feedback) }
                ForEach(model.files.progress) { transfer in
                    ProgressView(value: transfer.fraction) {
                        Label(transfer.name, systemImage: transfer.sending ? "arrow.up" : "arrow.down")
                    } currentValueLabel: {
                        Text(transfer.verifying ? "Verificando integridade…" :
                             "\(ByteCountFormatter.string(fromByteCount: transfer.offset, countStyle: .file)) de \(ByteCountFormatter.string(fromByteCount: transfer.size, countStyle: .file))")
                            .monospacedDigit()
                    }
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard model.canSendFiles, let file = urls.first, file.isFileURL else { return false }
                model.sendFile(file)
                return true
            }
            card("Recebidos", icon: "tray") {
                receivedByDate(model.files.received, empty: "Nenhum arquivo recebido.")
            }
        }
    }

    private var notifications: some View {
        VStack(alignment: .leading, spacing: 14) {
            card("Espelhamento de notificações", icon: "bell") {
                Toggle("Receber notificações do Android", isOn: $model.notificationsEnabled)
                Toggle("Ocultar conteúdo neste Mac", isOn: $model.hideNotices)
                Toggle("Não Perturbe", isOn: $model.quiet)
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
            card("Recebidas", icon: "tray") {
                if model.notifications.notices.isEmpty { empty("Nenhuma notificação recebida.") }
                ForEach(model.notifications.notices) { notice in
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
                        Button("Dispensar") { model.notifications.dismiss(notice) }
                    }
                    Divider()
                }
            }
        }
    }

    private var remote: some View {
        VStack(alignment: .leading, spacing: 14) {
            card("Espelhamento de tela", icon: "rectangle.on.rectangle") {
                Text("A captura começa após você autorizar no Android. Para limitar o conteúdo, escolha uma janela de aplicativo no pedido do sistema quando disponível.")
                    .foregroundStyle(palette.muted)
                HStack {
                    Picker("Resolução", selection: Binding(get: { model.screen.maxSize }, set: { model.screen.maxSize = $0 })) {
                        Text("480 px").tag(480); Text("768 px").tag(768); Text("960 px").tag(960)
                    }
                    Picker("Quadros por segundo", selection: Binding(get: { model.screen.fps }, set: { model.screen.fps = $0 })) {
                        Text("6").tag(6); Text("10").tag(10); Text("15").tag(15)
                    }
                    Picker("Qualidade", selection: Binding(get: { model.screen.quality }, set: { model.screen.quality = $0 })) {
                        Text("Baixa").tag(50); Text("Média").tag(68); Text("Alta").tag(80)
                    }
                }.disabled(model.screen.requesting || model.screen.sharing)
                if model.screen.requesting || model.screen.sharing {
                    HStack {
                        Button("Mostrar tela") { openWindow(id: "mirror") }.buttonStyle(NexusPillStyle(prominent: true))
                        Button("Parar") { model.screen.end() }
                    }
                } else {
                    Button("Solicitar espelhamento") { model.requestMirror(); openWindow(id: "mirror") }
                        .buttonStyle(NexusPillStyle(prominent: true)).disabled(!model.canMirror)
                    if !model.canMirror { empty("Ative solicitações de espelhamento no Android.") }
                }
                if let feedback = model.screen.feedback { empty(feedback) }
            }
            card("Controle com mouse e teclado por USB", icon: "keyboard") {
                Text("Requer o scrcpy, o ADB e um Android autorizado para depuração USB. Os atalhos e o arraste de arquivos ficam na janela do scrcpy.")
                    .foregroundStyle(palette.muted)
                if model.screen.usbActive { Button("Encerrar controle USB") { model.screen.stopUSB() } }
                else { Button("Abrir controle USB") { usbConfirm = true } }
            }
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
            card("Webcam", icon: "web.camera") { empty("Em desenvolvimento.") }
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
            card("Permissões", icon: "hand.raised") {
                Text("Ative cada integração na tela correspondente. Os dispositivos que podem acessar este Mac ficam em Dispositivos.")
                    .foregroundStyle(palette.muted)
                Button("Gerenciar dispositivos") { model.section = .devices }
            }
            card("Atalhos de teclado", icon: "keyboard") {
                Text("Os atalhos abaixo usam Shift + Command quando o Nexus está ativo.")
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

    private func shortcut(_ section: Section, title: String, detail: String, highlighted: Bool = false) -> some View {
        Button { model.section = section } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: section.icon)
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(palette.accent)
                        .frame(width: 39, height: 39, alignment: .leading)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.muted)
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 16, weight: .semibold)).lineLimit(2)
                    Text(detail).font(.subheadline).foregroundStyle(palette.muted).lineLimit(1)
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 129, alignment: .leading)
            .nexusPanel(palette, highlighted: highlighted)
            .contentShape(.rect(cornerRadius: 19))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }

    private func empty(_ text: String) -> some View {
        Text(text).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func receivedByDate(_ files: [ReceivedFile], empty hint: String) -> some View {
        if files.isEmpty {
            empty(hint)
        } else {
            LibraryDatePicker(selection: $libraryGrouping)
            ForEach(libraryGrouping.sections(for: files, calendar: calendar, date: { $0.date == .distantPast ? nil : $0.date })) { group in
                if libraryGrouping != .none {
                    LibraryDateHeading(date: group.date, grouping: libraryGrouping)
                }
                ForEach(group.items) { fileRow($0) }
            }
        }
    }

    @ViewBuilder
    private func recent(_ files: [ReceivedFile], empty hint: String) -> some View {
        if files.isEmpty { empty(hint) }
        ForEach(files.prefix(3)) { fileRow($0) }
    }

    private func fileRow(_ item: ReceivedFile) -> some View {
        HStack(spacing: 8) {
            Label(item.offer.name, systemImage: item.offer.mime.hasPrefix("image/") ? "photo" : "doc")
                .lineLimit(1)
            Spacer()
            Button("Visualizar") { preview = item.url }
            if model.section != .overview {
                Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: {
                    Image(systemName: "folder").accessibilityLabel("Mostrar no Finder")
                }
                ShareLink(item: item.url) { Image(systemName: "square.and.arrow.up").accessibilityLabel("Compartilhar arquivo") }
            }
        }.onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
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
