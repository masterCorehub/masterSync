import SwiftUI

/// The place held for Chamadas, SMS e RCS and Webcam: what each will do, with nothing to press.
struct ComingSoonView: View {
    let section: Section
    @Environment(\.colorScheme) private var scheme

    private var palette: NexusPalette { NexusPalette(scheme: scheme) }

    private var promise: String {
        switch section {
        case .calls: "Atenda e faça ligações pelo Mac, com o áudio nos alto-falantes e no microfone dele."
        case .sms: "Leia e responda as mensagens do celular direto no Mac."
        case .webcam: "Use a câmera do celular como webcam no FaceTime, Zoom, Meet e Teams."
        default: ""
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            IconBadge(systemName: section.icon, size: 64)
            VStack(spacing: 6) {
                Text(section.title).font(.system(size: 20, weight: .bold))
                Text(promise).font(.system(size: 13.5)).foregroundStyle(palette.muted)
                    .multilineTextAlignment(.center).frame(maxWidth: 380).lineSpacing(2)
            }
            Text("EM BREVE")
                .font(.system(size: 11, weight: .bold)).tracking(0.8).foregroundStyle(palette.accent)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(palette.accentSurface, in: Capsule())
        }
        .padding(40)
        .frame(maxWidth: .infinity, minHeight: 320)
        .glassPanel(radius: 22)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(section.title), em breve. \(promise)")
    }
}
