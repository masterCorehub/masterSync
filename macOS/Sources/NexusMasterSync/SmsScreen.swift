import NexusCore
import SwiftUI

/// SMS: the phone's conversations on the left, the open conversation and its composer on the right.
struct SmsScreen: View {
    @ObservedObject var model: NexusModel
    @ObservedObject var sms: SmsModel
    @State private var search = ""
    @State private var draft = ""
    @State private var width: CGFloat = 0
    /// Lets snapshot tests show the conversations without a phone; nil in the app.
    var availableOverride: Bool?
    @Environment(\.colorScheme) private var scheme

    private var palette: NexusPalette { NexusPalette(scheme: scheme) }
    private var showsList: Bool { width >= 700 || sms.selectedID == nil }

    var body: some View {
        VStack(spacing: 0) {
            WidthProbe(width: $width)
            if !(availableOverride ?? model.smsAvailable) { unavailable } else {
                HStack(spacing: 16) {
                    if showsList { list.frame(width: width >= 700 ? 290 : nil) }
                    if width >= 700 || sms.selectedID != nil { thread }
                }
            }
        }
        .frame(maxWidth: 1200, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
        .task(id: model.smsAvailable) { if model.smsAvailable { sms.refresh() } }
    }

    // MARK: Not available

    private var unavailable: some View {
        VStack(spacing: 12) {
            IconBadge(systemName: "message", size: 52)
            Text(model.active ? "O SMS ainda não está ligado no celular" : "Conecte o celular para ver os SMS")
                .font(.system(size: 15, weight: .semibold))
            if model.active {
                Text("No MasterSync do Android, abra Recursos → “SMS no Mac”, permita o acesso aos SMS e ligue o recurso. Precisa da versão completa e atualizada do app. Só aparece SMS: o RCS do Google Mensagens não é compartilhado pelo Android.")
                    .font(.system(size: 12.5)).foregroundStyle(palette.muted).multilineTextAlignment(.center).frame(maxWidth: 440).lineSpacing(2)
            }
        }
        .padding(40).frame(maxWidth: .infinity).glassPanel(radius: 22)
    }

    // MARK: Conversations

    private var filtered: [SmsThread] {
        let needle = search.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return sms.threads }
        return sms.threads.filter {
            SmsFormat.title(for: $0).localizedCaseInsensitiveContains(needle) || $0.address.contains(needle) || $0.snippet.localizedCaseInsensitiveContains(needle)
        }
    }

    private var list: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(palette.muted)
                TextField("Buscar conversas", text: $search).textFieldStyle(.plain)
                Button { sms.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).foregroundStyle(palette.muted).accessibilityLabel("Atualizar").help("Atualizar")
            }
            .font(.system(size: 13)).padding(.horizontal, 10).padding(.vertical, 8)
            .background(palette.input, in: RoundedRectangle(cornerRadius: 10, style: .continuous)).padding(.bottom, 6)
            if let error = sms.error { Text(error).font(.system(size: 12)).foregroundStyle(palette.muted).padding(8) }
            if sms.loadingThreads && sms.threads.isEmpty { ProgressView().controlSize(.small).padding(20) }
            if !sms.loadingThreads && filtered.isEmpty && sms.error == nil {
                Text(search.isEmpty ? "Nenhuma conversa de SMS." : "Nada encontrado.").font(.system(size: 12.5))
                    .foregroundStyle(palette.muted).padding(20)
            }
            SnapshotAwareScroll {
                LazyVStack(spacing: 2) { ForEach(filtered) { row($0) } }
            }
        }
        .padding(8).frame(maxHeight: .infinity, alignment: .top).glassPanel(radius: 20)
    }

    private func row(_ thread: SmsThread) -> some View {
        let selected = sms.selectedID == thread.id
        return Button { sms.open(thread.id) } label: {
            HStack(spacing: 10) {
                Avatar(initials: SmsFormat.initials(for: thread), hue: NexusPalette.stableHue(thread.address), size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(SmsFormat.title(for: thread)).font(.system(size: 13.5, weight: thread.unread > 0 ? .bold : .semibold)).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(SmsFormat.shortTime(thread.date)).font(.system(size: 11)).foregroundStyle(palette.faint)
                    }
                    Text(thread.snippet).font(.system(size: 12.5)).foregroundStyle(palette.muted).lineLimit(1)
                }
                if thread.unread > 0 { Circle().fill(palette.fill).frame(width: 8, height: 8).accessibilityHidden(true) }
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? palette.active : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(SmsFormat.title(for: thread)), \(thread.unread > 0 ? "\(thread.unread) não lidas, " : "")\(thread.snippet)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Open conversation

    private var current: SmsThread? { sms.threads.first { $0.id == sms.selectedID } }

    @ViewBuilder private var thread: some View {
        if let current {
            let messages = sms.messages(of: current.id)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    if width < 700 {
                        Button { sms.close() } label: { Image(systemName: "chevron.left") }
                            .buttonStyle(.plain).accessibilityLabel("Voltar às conversas")
                    }
                    Avatar(initials: SmsFormat.initials(for: current), hue: NexusPalette.stableHue(current.address), size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(SmsFormat.title(for: current)).font(.system(size: 14, weight: .bold)).lineLimit(1)
                        Text(current.name == nil ? "SMS" : SmsFormat.formatted(current.address)).font(.system(size: 11.5)).foregroundStyle(palette.muted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
                Rectangle().fill(palette.line).frame(height: 1)
                ScrollViewReader { scroll in
                    SnapshotAwareScroll {
                        LazyVStack(spacing: 8) {
                            if sms.loadingMessages && messages.isEmpty { ProgressView().controlSize(.small).padding(30) }
                            ForEach(messages) { bubble($0) }
                            Color.clear.frame(height: 1).id("end")
                        }.padding(18)
                    }
                    .onChange(of: messages.last?.id, initial: true) { _, _ in scroll.scrollTo("end", anchor: .bottom) }
                }
                Rectangle().fill(palette.line).frame(height: 1)
                composer(current)
            }
            .frame(maxHeight: .infinity).glassPanel(radius: 20)
        } else {
            VStack(spacing: 10) {
                IconBadge(systemName: "message", size: 44)
                Text("Escolha uma conversa").font(.system(size: 14, weight: .semibold))
                Text("Os SMS novos aparecem aqui na hora.").font(.system(size: 12.5)).foregroundStyle(palette.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).glassPanel(radius: 20)
        }
    }

    private func bubble(_ message: SmsMessage) -> some View {
        let mine = message.outgoing
        let shape = UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: mine ? 18 : 6,
                                           bottomTrailingRadius: mine ? 6 : 18, topTrailingRadius: 18, style: .continuous)
        return VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
            Text(message.body).font(.system(size: 13.5)).lineSpacing(2).textSelection(.enabled)
                .foregroundStyle(mine ? palette.accentInk : palette.ink)
                .padding(.vertical, 9).padding(.horizontal, 13)
                .background(mine ? palette.fill : palette.panel2, in: shape)
                .overlay { if !mine { shape.strokeBorder(palette.line) } }
                .frame(maxWidth: 480, alignment: mine ? .trailing : .leading)
            HStack(spacing: 6) {
                Text(Date(timeIntervalSince1970: Double(message.date) / 1000), style: .time)
                switch message.state {
                case .sending: Text("Enviando…")
                case .failed(let reason): Text("Não enviado · \(reason)").foregroundStyle(.red)
                default: EmptyView()
                }
            }
            .font(.system(size: 10.5)).foregroundStyle(palette.faint).padding(.horizontal, 6)
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    private func composer(_ thread: SmsThread) -> some View {
        let canReply = sms.canReply(to: thread.id)
        return VStack(alignment: .leading, spacing: 6) {
            if !canReply {
                Text("Não dá para responder a “\(thread.address)”: o Android só envia SMS para números.")
                    .font(.system(size: 11.5)).foregroundStyle(palette.muted)
            }
            HStack(spacing: 10) {
                TextField(canReply ? "Mensagem de texto" : "Resposta indisponível", text: $draft)
                    .textFieldStyle(.plain).font(.system(size: 13.5))
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(palette.input, in: Capsule()).overlay { Capsule().strokeBorder(palette.line) }
                    .disabled(!canReply).onSubmit { submit(thread) }
                Button { submit(thread) } label: {
                    Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold)).foregroundStyle(palette.accentInk)
                        .frame(width: 36, height: 36).background(palette.fill, in: Circle())
                }
                .buttonStyle(.plain).disabled(!canReply || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Enviar SMS")
            }
        }
        .padding(12)
    }

    private func submit(_ thread: SmsThread) {
        if sms.sendText(draft, to: thread.id) { draft = "" }
    }
}
