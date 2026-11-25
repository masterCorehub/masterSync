import SwiftUI

struct WirelessClipboardSetup: View {
    let device: ADBWirelessDevice?
    let connect: (ADBWirelessDevice, ADBPairing?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var needsPairing = true
    @State private var pairingAddress = ""
    @State private var pairingCode = ""
    @State private var connectionAddress = ""

    private var pairing: ADBPairing? { ADBPairing(address: pairingAddress, code: pairingCode) }
    private var endpoint: ADBEndpoint? { ADBEndpoint(connectionAddress) }
    private var valid: Bool {
        if !connectionAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && endpoint == nil { return false }
        return needsPairing ? pairing != nil : endpoint != nil || device?.service != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Área de transferência por Wi-Fi", systemImage: "wifi").font(.title2.weight(.semibold))
            Text("No Android 11 ou superior, abra Opções do desenvolvedor → Depuração sem fio. Mantenha os dois aparelhos na mesma rede.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Parear este Mac com um código", isOn: $needsPairing)
            if needsPairing {
                Text("No celular, toque em Parear dispositivo com código e mantenha a janela aberta enquanto conecta.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                TextField("IP e porta de pareamento", text: $pairingAddress, prompt: Text("192.168.1.10:37123"))
                SecureField("Código de seis dígitos", text: $pairingCode)
            }
            Divider()
            TextField("IP e porta da conexão", text: $connectionAddress, prompt: Text("192.168.1.10:42119"))
            Text("Use o endereço da tela principal da Depuração sem fio. Deixe em branco para descoberta automática após o pareamento.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                Button(needsPairing ? "Parear e ativar" : "Conectar e ativar") {
                    let previous = needsPairing ? nil : device
                    connect(ADBWirelessDevice(address: endpoint?.address, service: previous?.service,
                                              deviceID: previous?.deviceID), needsPairing ? pairing : nil)
                    pairingCode = ""
                    dismiss()
                }.disabled(!valid).buttonStyle(NexusPillStyle(prominent: true)).keyboardShortcut(.defaultAction)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(24)
        .frame(width: 520)
        .onAppear {
            needsPairing = device == nil
            connectionAddress = device?.address ?? ""
        }
    }
}
