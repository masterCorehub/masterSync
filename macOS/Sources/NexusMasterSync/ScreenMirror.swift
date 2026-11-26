import AppKit
import Foundation
import NexusCore

@MainActor
final class ScreenMirror: ObservableObject {
    enum ControlRoute: Equatable { case inApp, scrcpy, mirror }

    /// With ADB over Wi-Fi, control needs no consent on the phone and survives the lock screen: inside the app when the
    /// scrcpy server is available, in scrcpy's own window when only scrcpy is, and through the phone's screen sharing otherwise.
    nonisolated static func controlRoute(hasWirelessADB: Bool, scrcpyInstalled: Bool, inAppAvailable: Bool = false) -> ControlRoute {
        guard hasWirelessADB else { return .mirror }
        if inAppAvailable { return .inApp }
        return scrcpyInstalled ? .scrcpy : .mirror
    }

    // MARK: In-app control (ADB video + input, no permission on the phone)

    let display = PhoneDisplayModel()
    @Published private(set) var inAppControl = false
    @Published private(set) var inAppStarting = false
    private var inAppClient: ScrcpyClient?

    var inAppAvailable: Bool { adbPath != nil && scrcpyPath.flatMap(ScrcpyLaunch.serverURL(forScrcpy:)) != nil }

    func beginInAppControl(wireless: ADBWirelessDevice) {
        guard !inAppControl, !inAppStarting else { return }
        guard let adb = adbPath, let scrcpy = scrcpyPath else {
            feedback = "Instale o ADB e o scrcpy para controlar o Android."
            return
        }
        inAppStarting = true
        feedback = nil
        display.reset()
        let client = ScrcpyClient(adb: adb, scrcpyExecutable: scrcpy)
        let display = self.display
        client.onEvent = { event in display.handle(event) }
        client.onEnded = { [weak self, weak client] reason in
            Task { @MainActor [weak self] in
                guard let self, let client, self.inAppClient === client else { return }
                self.finishInApp(reason: reason)
            }
        }
        inAppClient = client
        display.send = { [weak client] data in client?.send(data) }
        Task {
            do {
                try await Task.detached {
                    let session = ADBClipboardSession(adb: adb)
                    let serial = try await session.wirelessSerial(for: wireless)
                    try client.start(serial: serial)
                }.value
                guard inAppClient === client else { client.stop(); return }
                inAppStarting = false
                inAppControl = true
            } catch {
                guard inAppClient === client else { return }
                inAppClient = nil
                inAppStarting = false
                feedback = error.localizedDescription
                client.stop()
            }
        }
    }

    func endInAppControl() {
        let client = inAppClient
        inAppClient = nil
        client?.stop()
        inAppControl = false
        inAppStarting = false
        display.reset()
    }

    private func finishInApp(reason: String?) {
        inAppClient?.stop()
        inAppClient = nil
        inAppControl = false
        inAppStarting = false
        display.reset()
        if let reason { feedback = reason }
    }

    /// Opens an app over ADB, then shows the phone in the app window if it is not there yet.
    func openAppWithInAppControl(_ app: AndroidApp, wireless: ADBWirelessDevice) {
        guard let adb = adbPath else {
            feedback = "Instale o ADB para abrir apps do Android."
            return
        }
        feedback = nil
        Task {
            do {
                try await Task.detached {
                    let session = ADBClipboardSession(adb: adb)
                    let serial = try await session.wirelessSerial(for: wireless)
                    try session.openApp(app, serial: serial)
                }.value
                beginInAppControl(wireless: wireless)
            } catch {
                feedback = error.localizedDescription
            }
        }
    }

    @Published private(set) var frame: NSImage?
    @Published private(set) var controlling = false
    @Published private(set) var preparingControl = false
    private var inputTarget: (session: ADBClipboardSession, serial: String)?
    private var controlRequest: UUID?
    private var inputSize: CGSize?
    private var pendingApp: AndroidApp?
    private var sendingInput = false
    @Published private(set) var sharing = false
    @Published private(set) var requesting = false
    @Published private(set) var feedback: String?
    @Published private(set) var usbActive = false
    @Published private(set) var audioOnlyActive = false
    @Published private(set) var connecting = false
    @Published var maxSize = 768
    @Published var quality = 68
    @Published var fps = 10
    var send: ((String, Message) -> Void)?
    private var peer: String?
    private var request: UUID?
    private var usb: Process?
    private var scrcpyAttempt: UUID?

    func beginControl(_ peer: String, wireless: ADBWirelessDevice?, open app: AndroidApp? = nil) {
        if controlling, self.peer == peer, let app {
            if sharing { launchApp(app) } else { pendingApp = app }
            return
        }
        guard !controlling, !preparingControl else { return }
        guard let adb = adbPath else {
            feedback = "Instale o ADB para controlar a tela."
            return
        }
        let session = ADBClipboardSession(adb: adb)
        let attempt = UUID()
        controlRequest = attempt
        preparingControl = true
        feedback = nil
        Task {
            do {
                let serial = try await Task.detached {
                    if let wireless { return try await session.wirelessSerial(for: wireless) }
                    return try session.usbSerial()
                }.value
                guard controlRequest == attempt else { return }
                preparingControl = false
                inputTarget = (session, serial)
                controlling = true
                if let app {
                    if sharing { launchApp(app) } else { pendingApp = app }
                }
                if !sharing { begin(peer) }
            } catch {
                guard controlRequest == attempt else { return }
                preparingControl = false
                feedback = error.localizedDescription
            }
        }
    }

    private func launchApp(_ app: AndroidApp) {
        guard let inputTarget, !sendingInput else {
            feedback = "Aguarde o comando atual terminar e tente novamente."
            return
        }
        let attempt = controlRequest
        sendingInput = true
        Task {
            defer { if controlRequest == attempt { sendingInput = false } }
            do {
                try await Task.detached {
                    try inputTarget.session.openApp(app, serial: inputTarget.serial)
                }.value
            } catch {
                if controlRequest == attempt { feedback = error.localizedDescription }
            }
        }
    }

    func gesture(from start: CGPoint, to end: CGPoint) {
        guard let inputSize else { return }
        // The preview passes normalized coordinates so resizing the Mac window does not change the target.
        func position(_ point: CGPoint) -> [String] {
            [String(Int(min(max(point.x, 0), 0.999) * inputSize.width)),
             String(Int(min(max(point.y, 0), 0.999) * inputSize.height))]
        }
        let drag = hypot(start.x - end.x, start.y - end.y) > 0.025
        sendInput(drag ? ["swipe"] + position(start) + position(end) + ["220"] : ["tap"] + position(end))
    }

    func pressSystemKey(home: Bool) {
        if inAppControl {
            let key = home ? ScrcpyControl.Key.home : ScrcpyControl.Key.back
            display.send?(ScrcpyControl.keycode(action: ScrcpyControl.Action.down, keycode: key))
            display.send?(ScrcpyControl.keycode(action: ScrcpyControl.Action.up, keycode: key))
            return
        }
        sendInput(["keyevent", home ? "KEYCODE_HOME" : "KEYCODE_BACK"])
    }

    private func sendInput(_ arguments: [String]) {
        guard sharing, controlling, !sendingInput, let inputTarget else { return }
        sendingInput = true
        let attempt = controlRequest
        Task {
            defer { sendingInput = false }
            do {
                try await Task.detached {
                    try inputTarget.session.sendInput(serial: inputTarget.serial, arguments: arguments)
                }.value
            } catch {
                if controlRequest == attempt { feedback = error.localizedDescription }
            }
        }
    }

    var adbInstalled: Bool { adbPath != nil }

    var scrcpyInstalled: Bool { scrcpyPath != nil }

    private var scrcpyPath: String? {
        ["/opt/homebrew/bin/scrcpy", "/usr/local/bin/scrcpy"]
            .first(where: FileManager.default.isExecutableFile(atPath:))
    }

    private var adbPath: String? {
        ["/opt/homebrew/bin/adb", "/usr/local/bin/adb",
         NSHomeDirectory() + "/Library/Android/sdk/platform-tools/adb"]
            .first(where: FileManager.default.isExecutableFile(atPath:))
    }

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
        endInAppControl()
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
            if let pendingApp {
                self.pendingApp = nil
                launchApp(pendingApp)
            }
        case "screenFrame":
            guard sharing, let id = message.id, Wire.validID(id), let data = message.data else { return }
            frame = GalleryModel.image(data, size: 960)
            if let width = message.screenWidth, let height = message.screenHeight,
               (1...16384).contains(width), (1...16384).contains(height) {
                inputSize = CGSize(width: width, height: height)
            } else {
                inputSize = nil
                if controlling { feedback = "Atualize o MasterSync no Android para usar os gestos." }
            }
            var ack = Message("screenAck")
            ack.id = id
            send?(peer, ack)
        case "screenEnded":
            clear(Wire.visible(message.message ?? "Espelhamento encerrado.", limit: 160))
        default: break
        }
    }

    /// Opens the app over ADB and shows it in scrcpy, starting scrcpy only when it is not running yet.
    func openAppWithScrcpy(_ app: AndroidApp, wireless: ADBWirelessDevice) {
        guard let adb = adbPath else {
            feedback = "Instale o ADB para abrir apps do Android."
            return
        }
        feedback = nil
        Task {
            do {
                try await Task.detached {
                    let session = ADBClipboardSession(adb: adb)
                    let serial = try await session.wirelessSerial(for: wireless)
                    try session.openApp(app, serial: serial)
                }.value
                if usb == nil { launchScrcpy(audioOnly: false, wireless: wireless) }
            } catch {
                feedback = error.localizedDescription
            }
        }
    }

    func launchScrcpy(audioOnly: Bool, wireless: ADBWirelessDevice? = nil) {
        guard usb == nil, !connecting else { return }
        guard let path = scrcpyPath, let adb = adbPath else {
            feedback = "Instale o scrcpy e o ADB para controlar o Android."
            return
        }
        let attempt = UUID()
        scrcpyAttempt = attempt
        connecting = true
        feedback = nil
        Task {
            defer { if scrcpyAttempt == attempt { connecting = false } }
            do {
                // Resolve the authorized device off the main thread before starting scrcpy.
                let serial = try await Task.detached {
                    let session = ADBClipboardSession(adb: adb)
                    if let wireless { return try await session.wirelessSerial(for: wireless) }
                    return try session.usbSerial()
                }.value
                guard scrcpyAttempt == attempt else { return }
                try runScrcpy(path: path, adb: adb, serial: serial, audioOnly: audioOnly)
            } catch {
                if scrcpyAttempt == attempt { feedback = error.localizedDescription }
            }
        }
    }

    private func runScrcpy(path: String, adb: String, serial: String, audioOnly: Bool) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        var arguments = ["--serial", serial, "--audio-source=output", "--no-clipboard-autosync"]
        if audioOnly {
            arguments += ["--no-window", "--require-audio"]
        } else {
            arguments += ["--max-fps=60", "--max-size=1600", "--window-title=MasterSync — Controle remoto"]
        }
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["ADB"] = adb
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
                self?.audioOnlyActive = false
                if status != 0 { self?.feedback = "O scrcpy foi encerrado. Confira a conexão ADB e a versão do Android." }
            }
        }
        try process.run()
        usb = process
        audioOnlyActive = audioOnly
        usbActive = true
        feedback = nil
    }

    func stopUSB() {
        scrcpyAttempt = nil
        connecting = false
        usb?.terminate()
        usb = nil
        usbActive = false
        audioOnlyActive = false
    }

    private func clear(_ status: String?) {
        controlRequest = nil
        pendingApp = nil
        sendingInput = false
        preparingControl = false
        controlling = false
        inputSize = nil
        inputTarget = nil
        peer = nil
        request = nil
        frame = nil
        sharing = false
        requesting = false
        feedback = status
    }
}
