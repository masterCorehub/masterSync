import SwiftUI

/// The three steps of the first-run flow. The "connect" step is the existing pairing guide.
enum OnboardingStep: Int, CaseIterable {
    case welcome, connect, features

    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
    var isLast: Bool { next == nil }
    var position: String { "\(rawValue + 1) de \(OnboardingStep.allCases.count)" }
    var title: String {
        switch self {
        case .welcome: "Boas-vindas"
        case .connect: "Conectar"
        case .features: "Recursos"
        }
    }
}

enum OnboardingFlow {
    struct Highlight: Identifiable {
        let icon: String
        let title: String
        let detail: String
        var id: String { title }
    }

    static let highlights: [Highlight] = [
        Highlight(icon: "bell.badge", title: "Notificações e códigos", detail: "Veja os avisos do celular e copie códigos de verificação na hora."),
        Highlight(icon: "message", title: "SMS", detail: "Leia e responda as mensagens do celular pelo Mac."),
        Highlight(icon: "photo.on.rectangle", title: "Fotos e arquivos", detail: "Navegue pela galeria e pelo armazenamento, e envie arquivos arrastando."),
        Highlight(icon: "display", title: "Controle do celular", detail: "Use a tela do Android numa janela, com mouse e teclado."),
        Highlight(icon: "doc.on.clipboard", title: "Área de transferência", detail: "Copie num lado e cole no outro."),
        Highlight(icon: "lock.shield", title: "Tudo pela sua rede", detail: "Sem conta e sem nuvem: o Mac e o celular conversam direto.")
    ]

    static func shouldAutoShow(seen: Bool, networkConsent: Bool, hasPeers: Bool) -> Bool {
        !seen && !networkConsent && !hasPeers
    }
}

/// "1 de 3 · Boas-vindas" with three dots.
struct OnboardingHeader: View {
    let step: OnboardingStep
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = NexusPalette(scheme: scheme)
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { item in
                    Capsule().fill(item.rawValue <= step.rawValue ? palette.fill : palette.track)
                        .frame(width: item == step ? 22 : 8, height: 6)
                }
            }
            .accessibilityHidden(true)
            Text("\(step.position) · \(step.title)")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.muted)
            Spacer()
        }
    }
}

struct OnboardingWelcomeStep: View {
    let onStart: () -> Void
    let onSkip: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = NexusPalette(scheme: scheme)
        VStack(alignment: .leading, spacing: 16) {
            OnboardingHeader(step: .welcome)
            Text("Bem-vindo ao masterSync").font(.system(size: 24, weight: .bold))
            Text("Seu Android dentro do Mac. Vamos conectar o celular em poucos passos.")
                .foregroundStyle(palette.muted)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(OnboardingFlow.highlights) { item in
                    HStack(alignment: .top, spacing: 12) {
                        IconBadge(systemName: item.icon, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.system(size: 13.5, weight: .semibold))
                            Text(item.detail).font(.system(size: 12.5)).foregroundStyle(palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            HStack {
                Button("Pular", action: onSkip).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Começar", action: onStart).buttonStyle(NexusPillStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
    }
}

struct OnboardingFeaturesStep: View {
    @ObservedObject var model: NexusModel
    let onFinish: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = NexusPalette(scheme: scheme)
        VStack(alignment: .leading, spacing: 14) {
            OnboardingHeader(step: .features)
            Text("O que você quer usar?").font(.system(size: 22, weight: .bold))
            Text("Cada recurso tem o próprio interruptor e pode ser mudado depois em Configurações. No celular, o app pede só as permissões do que você ligar.")
                .foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                SwitchRow(title: "Notificações do celular", subtitle: "Espelha os avisos do Android neste Mac", isOn: $model.notificationsEnabled)
                SwitchRow(title: "Códigos de verificação", subtitle: "Copia o código e avisa no canto da tela", isOn: $model.codeAutofill)
                SwitchRow(title: "Fotos e vídeos", subtitle: "Mostra a galeria do celular", isOn: $model.galleryEnabled)
                SwitchRow(title: "Enviar e receber arquivos", isOn: $model.filesEnabled)
                SwitchRow(title: "Área de transferência", subtitle: "Texto e imagens entre o Mac e o celular",
                          isOn: Binding(get: { model.clipboardSyncActive }, set: { model.setClipboardSync($0) }),
                          showsDivider: false)
            }
            .padding(.horizontal, 16).padding(.vertical, 4)
            .glassPanel(radius: 18)
            HStack {
                Spacer()
                Button("Começar a usar", action: onFinish).buttonStyle(NexusPillStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
    }
}
