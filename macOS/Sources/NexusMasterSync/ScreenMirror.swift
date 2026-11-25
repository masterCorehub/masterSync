import AppKit
import Foundation
import NexusCore

@MainActor
final class ScreenMirror: ObservableObject {
    @Published private(set) var frame: NSImage?
    @Published private(set) var sharing = false
    @Published private(set) var requesting = false
    @Published private(set) var feedback: String?
    @Published private(set) var usbActive = false
    @Published var maxSize = 768
    @Published var quality = 68
    @Published var fps = 10
    var send: ((String, Message) -> Void)?
    private var peer: String?
    private var request: UUID?
    private var usb: Process?

    func begin(_ peer: String) {
        guard self.peer == nil else { return }
        self.peer = peer
        requesting = true
        feedback = "Aguardando permissão do Android."
        var message = Message("screenRequest")
        message.id = Wire.id()
        message.rate = fps
        message.quality = quality
        message.size = Int64(maxSize)
        send?(peer, message)
        let request = UUID()
        self.request = request
        Task {
            try? await Task.sleep(for: .seconds(40))
            if self.request == request {
                end()
                feedback = "A solicitação expirou. Abra o Nexus no celular e tente novamente."
            }
        }
    }

    func disconnect(_ peer: String) {
        if self.peer == peer { clear("O celular foi desconectado.") }
    }

    func end() {
        if let peer { send?(peer, Message("screenStop")) }
        clear(nil)
    }

    func receive(_ message: Message, from peer: String) {
        guard self.peer == peer else { return }
        switch message.type {
        case "screenActive":
            request = nil
            sharing = true
            requesting = false
            feedback = nil
        case "screenFrame":
            guard sharing, let id = message.id, Wire.validID(id), let data = message.data else { return }
            frame = GalleryModel.image(data, size: 960)
            var ack = Message("screenAck")
            ack.id = id
            send?(peer, ack)
        case "screenEnded":
            clear(Wire.visible(message.message ?? "Espelhamento encerrado.", limit: 160))
        default: break
        }
    }

    func launchUSB() {
        guard usb == nil else { return }
        let fileManager = FileManager.default
        guard let path = ["/opt/homebrew/bin/scrcpy", "/usr/local/bin/scrcpy"]
            .first(where: fileManager.isExecutableFile(atPath:)) else {
            feedback = "Instale o scrcpy e o ADB para abrir o controle por USB."
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--select-usb", "--no-clipboard-autosync", "--no-audio", "--max-fps=60",
                             "--window-title=Nexus masterSync — Controle USB"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(URL(fileURLWithPath: path).deletingLastPathComponent().path):/usr/local/bin:/usr/bin:/bin"
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { @MainActor in
                guard self?.usb === process else { return }
                self?.usb = nil
                self?.usbActive = false
                if status != 0 { self?.feedback = "O controle USB foi encerrado. Confira o cabo e a autorização do ADB." }
            }
        }
        do {
            try process.run()
            usb = process
            usbActive = true
            feedback = nil
        } catch { feedback = error.localizedDescription }
    }

    func stopUSB() {
        usb?.terminate()
        usb = nil
        usbActive = false
    }

    private func clear(_ status: String?) {
        peer = nil
        request = nil
        frame = nil
        sharing = false
        requesting = false
        feedback = status
    }
}
