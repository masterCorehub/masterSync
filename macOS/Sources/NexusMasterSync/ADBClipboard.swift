import Foundation
import Network
import NexusCore

struct ADBEndpoint: Equatable, Sendable {
    let address: String

    init?(_ input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = text.lastIndex(of: ":"), let port = UInt16(text[text.index(after: separator)...]), port > 0 else { return nil }
        var host = String(text[..<separator])
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        if IPv4Address(host) != nil { address = "\(host):\(port)" }
        else if IPv6Address(host) != nil { address = "[\(host)]:\(port)" }
        else { return nil }
    }
}

struct ADBWirelessDevice: Codable, Equatable, Sendable {
    var address: String?
    var service: String?
    var deviceID: String?
    var peerID: String? = nil
}

struct ADBPairing: Sendable {
    let endpoint: ADBEndpoint
    let code: String

    init?(address: String, code: String) {
        guard let endpoint = ADBEndpoint(address), code.utf8.count == 6,
              code.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        self.endpoint = endpoint
        self.code = code
    }
}

@MainActor
final class ADBClipboard: ObservableObject {
    enum Transport: Sendable { case usb, wifi }

    @Published private(set) var transport: Transport?
    @Published private(set) var status: String?
    @Published private(set) var wirelessDevice: ADBWirelessDevice?

    @Published private(set) var checkingWireless = false
    @Published private(set) var wirelessVerified = false
    @Published private(set) var wirelessSetupError: String?

    var receive: ((ADBClipboardEvent) -> Void)?
    /// Where the phone is on the network right now (its saved port on its current IP), so a network change is followed.
    var addressProvider: ((ADBWirelessDevice) -> String?)?
    fileprivate func freshAddress(for device: ADBWirelessDevice) -> String? { addressProvider?(device) }
    /// Called when a running session ends on its own (not when the user stops it).
    var onEnded: (() -> Void)?
    /// The user stopped the sync; automatic start waits until they start it again.
    private(set) var paused = UserDefaults.standard.bool(forKey: "adb-clipboard-paused") {
        didSet { defaults.set(paused, forKey: "adb-clipboard-paused") }
    }

    nonisolated static func shouldAutoStart(clipboardEnabled: Bool, device: ADBWirelessDevice?, connectedPeer: String?,
                                            running: Bool, paused: Bool) -> Bool {
        guard clipboardEnabled, !running, !paused, let device, let connectedPeer else { return false }
        return device.peerID == connectedPeer
    }

    private var session: ADBClipboardSession?
    private var task: Task<Void, Never>?
    private let defaults = UserDefaults.standard
    private static let wirelessKey = "adb-clipboard-wireless-device"

    init() {
        if let stored = defaults.data(forKey: Self.wirelessKey) {
            wirelessDevice = try? JSONDecoder().decode(ADBWirelessDevice.self, from: stored)
        }
    }

    func configureWireless(_ device: ADBWirelessDevice, pairing: ADBPairing?, peer: String,
                           proof: @escaping (ADBClipboardSession, String, String) async throws -> Void) {
        guard !checkingWireless else { return }
        wirelessVerified = false
        wirelessSetupError = nil
        guard let adb = Self.adbPath else {
            wirelessSetupError = "Instale o ADB no Mac e tente novamente."
            return
        }
        checkingWireless = true
        Task {
            defer { checkingWireless = false }
            do {
                let session = ADBClipboardSession(adb: adb)
                let resolved = try await Task.detached {
                    var target = device
                    if let pairing { target.service = try session.pair(pairing) }
                    let serial = try await session.wirelessSerial(for: target)
                    guard let identity = try session.hardwareID(serial: serial) else {
                        throw NexusError.transfer("O ADB não conseguiu identificar o celular.")
                    }
                    target.deviceID = identity
                    target.peerID = peer
                    return (target, serial)
                }.value
                // Save the binding only after both transports prove they reach this peer.
                try await proof(session, resolved.1, peer)
                let confirmed = resolved.0
                wirelessDevice = confirmed
                defaults.set(try? JSONEncoder().encode(confirmed), forKey: Self.wirelessKey)
                wirelessVerified = true
            } catch {
                wirelessSetupError = error.localizedDescription
            }
        }
    }

    static var adbExecutable: String? { adbPath }

    private static var adbPath: String? {
        ["/opt/homebrew/bin/adb", "/usr/local/bin/adb",
         NSHomeDirectory() + "/Library/Android/sdk/platform-tools/adb"]
            .first(where: FileManager.default.isExecutableFile(atPath:))
    }

    func startUSB() {
        paused = false
        start(.usb) { [weak self] session, helper in
            let serial = try session.usbSerial()
            try await session.listen(serial: serial, helper: helper, onReady: { [weak self] in
                await self?.ready(session, transport: .usb)
            }, onEvent: { [weak self] event in
                await self?.accept(event, from: session)
            })
        }
    }

    func startWiFi(device: ADBWirelessDevice, pairing: ADBPairing? = nil) {
        paused = false
        start(.wifi) { [weak self] session, helper in
            var target = device
            if let pairing {
                target.service = try session.pair(pairing)
                if target.service != nil || target.address != nil {
                    await self?.remember(session, device: target)
                }
            }

            var wasReady = false
            var failures = 0
            var repairedAt = -3
            while !Task.isCancelled {
                // The phone may have changed networks since the address was saved.
                if let fresh = await self?.freshAddress(for: target) { target.address = fresh }
                do {
                    let serial = try await session.wirelessSerial(for: target)
                    let identity = try session.hardwareID(serial: serial)
                    if let previous = target.deviceID, identity != previous { throw ADBWirelessError.changedDevice }
                    target.deviceID = identity
                    let confirmed = target
                    try await session.listen(serial: serial, helper: helper, onReady: { [weak self] in
                        wasReady = true
                        failures = 0
                        await self?.ready(session, transport: .wifi, device: confirmed)
                    }, onEvent: { [weak self] event in
                        await self?.accept(event, from: session)
                    })
                } catch ADBWirelessError.changedDevice {
                    throw ADBWirelessError.changedDevice
                } catch {
                    // A phone already verified once is looked for again, saying why; a first setup reports its error.
                    if (!wasReady && target.deviceID == nil) || Task.isCancelled { throw error }
                    failures += 1
                    let usbSerial = session.usbSerial(matching: target.deviceID)
                    switch ADBRecovery.next(failures: failures, usbDeviceAttached: usbSerial != nil) {
                    case .retry(let text), .waitForCable(let text):
                        await self?.update(session, status: text)
                    case .repairOverUSB(let text):
                        await self?.update(session, status: text)
                        if failures - repairedAt >= 3, let usbSerial {
                            repairedAt = failures
                            let saved = ADBAddress.port(of: target.address) ?? 5555
                            try? session.enableTCPIP(serial: usbSerial, port: saved >= 1024 ? saved : 5555)
                            try? await Task.sleep(for: .seconds(2))
                        }
                    }
                }
                guard !Task.isCancelled else { return }
                // Reconnect only when there is a stable identity for the device already selected.
                guard target.service != nil || target.deviceID != nil else { return }
                if target.deviceID == nil { target.address = nil }
                if failures == 0 { await self?.update(session, status: "Reconectando ao mesmo celular pelo Wi-Fi…") }
                try await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func start(_ transport: Transport,
                       listen: @escaping @Sendable (ADBClipboardSession, URL) async throws -> Void) {
        guard session == nil else { return }
        guard let adb = Self.adbPath else {
            status = "Instale o ADB para usar esta sincronização."
            return
        }
        guard let helper = Bundle.main.url(forResource: "NexusUsbClipboard", withExtension: "jar") else {
            status = "O leitor ADB está ausente neste build do Nexus."
            return
        }

        let session = ADBClipboardSession(adb: adb)
        self.session = session
        self.transport = transport
        status = transport == .usb ? "Conectando ao Android por USB…" : "Conectando à Depuração sem fio do Android…"
        task = Task.detached { [weak self] in
            do {
                try await listen(session, helper)
                let status = transport == .usb ? "Sessão USB encerrada. Reconecte o cabo e ative novamente."
                    : "Sessão Wi-Fi encerrada. Confira o endereço em Configurar Wi-Fi."
                await self?.ended(session, status: status)
            } catch {
                await self?.ended(session, status: error.localizedDescription)
            }
        }
    }

    func stop(userInitiated: Bool = false) {
        if userInitiated { paused = true }
        task?.cancel()
        session?.cancel()
        task = nil
        session = nil
        transport = nil
        status = nil
    }

    private func ready(_ session: ADBClipboardSession, transport: Transport, device: ADBWirelessDevice? = nil) {
        guard self.session === session else { return }
        if let device { remember(session, device: device) }
        status = "Sincronização \(transport == .usb ? "USB" : "Wi-Fi") ativa. Copie texto ou imagem no celular."
    }

    private func remember(_ session: ADBClipboardSession, device: ADBWirelessDevice) {
        guard self.session === session, wirelessDevice != device else { return }
        wirelessDevice = device
        defaults.set(try? JSONEncoder().encode(device), forKey: Self.wirelessKey)
    }

    private func update(_ session: ADBClipboardSession, status: String) {
        guard self.session === session else { return }
        self.status = status
    }

    private func accept(_ event: ADBClipboardEvent, from session: ADBClipboardSession) {
        guard self.session === session else { return }
        receive?(event)
    }

    private func ended(_ session: ADBClipboardSession, status: String) {
        guard self.session === session else { return }
        stop()
        self.status = status
        onEnded?()
    }
}

enum ADBWirelessError: LocalizedError {
    case changedDevice

    var errorDescription: String? { "O endereço passou a apontar para outro aparelho. Confira a Depuração sem fio e configure novamente." }
}

enum ADBClipboardEvent: Equatable {
    case text(String)
    case image(Data, mime: String)
}

// One worker reads the pipe. The lock lets the window close its input from the main thread.
final class ADBClipboardSession: @unchecked Sendable {
    private struct Command {
        let process: Process
        let output: FileHandle
        let input: FileHandle?
    }

    private let adb: String
    private let lock = NSLock()
    private var command: Command?
    private var cancelled = false

    init(adb: String) { self.adb = adb }

    func openApp(_ app: AndroidApp, serial: String) throws {
        guard app.validComponent else { throw NexusError.invalidFrame }
        // adb shell joins the arguments into a remote command, so quote the validated component.
        let result = try capture(["-s", serial, "shell", "am", "start", "-a", "android.intent.action.MAIN",
                                  "-c", "android.intent.category.LAUNCHER", "-n", "'\(app.component)'"],
                                 diagnostics: true)
        let output = String(decoding: result.0, as: UTF8.self).lowercased()
        guard result.1 == 0, !output.contains("error"), !output.contains("exception") else {
            throw NexusError.transfer("O Android não conseguiu abrir este app.")
        }
    }

    func sendInput(serial: String, arguments: [String]) throws {
        let result = try capture(["-s", serial, "shell", "input"] + arguments)
        guard result.1 == 0 else {
            throw NexusError.transfer("O Android não recebeu o comando. Confira a conexão ADB.")
        }
    }

    /// The serial of [id] when that phone is on a cable and authorized, so its ADB can be switched back to Wi-Fi.
    func usbSerial(matching id: String?) -> String? {
        guard let id, let output = try? capture(["devices"]) else { return nil }
        return ADBAddress.usbSerials(from: String(decoding: output.0, as: UTF8.self)).first { $0 == id }
    }

    /// Makes the phone listen for ADB on [port] over the network again (it stops after a reboot).
    func enableTCPIP(serial: String, port: Int) throws {
        guard let arguments = Self.tcpipArguments(serial: serial, port: port) else { throw NexusError.invalidFrame }
        let result = try capture(arguments)
        guard result.1 == 0 else { throw NexusError.transfer("O Android não aceitou reativar o ADB pelo cabo.") }
    }

    func usbSerial() throws -> String {
        let result = try capture(["-d", "get-serialno"])
        let serial = String(decoding: result.0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.1 == 0, !serial.isEmpty, serial != "unknown" else {
            throw NexusError.transfer("Conecte um único celular por USB e aceite a depuração no Android.")
        }
        return serial
    }

    func pair(_ pairing: ADBPairing) throws -> String? {
        // ADB accepts the code on stdin, so it stays out of process arguments and settings.
        let result = try capture(["pair", pairing.endpoint.address], input: Data((pairing.code + "\n").utf8), diagnostics: true)
        let output = String(decoding: result.0, as: UTF8.self)
        guard result.1 == 0, output.contains("Successfully paired") else {
            let diagnostic = output.lowercased()
            let hint: String
            if diagnostic.contains("permission denied") || diagnostic.contains("operation not permitted") {
                hint = "O Mac bloqueou o acesso do ADB à rede. Revise o acesso à Rede Local nos Ajustes do Sistema."
            } else if diagnostic.contains("failed to connect") || diagnostic.contains("connection refused")
                        || diagnostic.contains("timed out") || diagnostic.contains("no route to host") {
                hint = "O Mac não conseguiu alcançar a porta de pareamento. Use a porta da janela do código e mantenha essa janela aberta no Android."
            } else if diagnostic.contains("daemon") || diagnostic.contains("cannot bind") {
                hint = "O serviço local do ADB não iniciou. Feche sessões antigas de depuração e tente novamente."
            } else {
                hint = "O Android não confirmou o pareamento. Abra uma nova janela de código, confira o IP e a porta e tente novamente."
            }
            // Keep raw ADB output out of the UI because it can contain device addresses.
            throw NexusError.transfer(hint)
        }
        guard let prefix = output.range(of: "[guid="), let end = output[prefix.upperBound...].firstIndex(of: "]") else { return nil }
        let guid = String(output[prefix.upperBound..<end])
        return !guid.isEmpty && guid.utf8.count <= 128 ? guid : nil
    }

    func verifyPeer(serial: String, nonce: String) throws -> Bool {
        guard Wire.validID(nonce) else { return false }
        for app in ["com.nexus.mastersync", "com.nexus.mastersync.direct"] {
            let component = app + "/com.nexus.mastersync.services.AdbProofReceiver"
            let result = try capture(["-s", serial, "shell", "am", "broadcast", "--receiver-foreground",
                                      "-n", component, "--es", "nonce", nonce])
            let response = String(decoding: result.0, as: UTF8.self).split(whereSeparator: \.isNewline)
            if result.1 == 0 && response.contains("Broadcast completed: result=1") { return true }
        }
        return false
    }

    func wirelessSerial(for device: ADBWirelessDevice) async throws -> String {
        let serial = try await resolveWirelessSerial(for: device)
        if let expected = device.deviceID, try hardwareID(serial: serial) != expected {
            throw ADBWirelessError.changedDevice
        }
        return serial
    }

    private func resolveWirelessSerial(for device: ADBWirelessDevice) async throws -> String {
        let endpoint = device.address.flatMap(ADBEndpoint.init)
        if let guid = device.service {
            let service = guid + "._adb-tls-connect._tcp"
            for attempt in 0..<(endpoint == nil ? 9 : 1) {
                let output = try capture(["devices"])
                let lines = String(decoding: output.0, as: UTF8.self).split(whereSeparator: \.isNewline)
                for line in lines {
                    let fields = line.split(whereSeparator: \.isWhitespace)
                    guard fields.count >= 2, fields[1] == "device" else { continue }
                    let serial = String(fields[0])
                    if serial == service || serial == service + "." { return serial }
                }
                if attempt < 8 && endpoint == nil { try await Task.sleep(for: .milliseconds(750)) }
            }
        }
        guard let endpoint else {
            throw NexusError.transfer("O celular não foi descoberto pelo Wi-Fi. Informe o IP e a porta da tela principal da Depuração sem fio.")
        }
        _ = try capture(["connect", endpoint.address])
        let state = try capture(["-s", endpoint.address, "get-state"])
        guard state.1 == 0, String(decoding: state.0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "device" else {
            throw NexusError.transfer("O ADB não conectou pelo Wi-Fi. Se o celular reiniciou, conecte o cabo e use Configurar Wi-Fi para reativar; senão, confira o IP e a porta.")
        }
        return endpoint.address
    }

    func hardwareID(serial: String) throws -> String? {
        let result = try capture(["-s", serial, "shell", "getprop", "ro.serialno"])
        let id = String(decoding: result.0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.1 == 0 && !id.isEmpty && id != "unknown" ? id : nil
    }

    func listen(serial: String, helper: URL, onReady: () async -> Void,
                onEvent: (ADBClipboardEvent) async -> Void) async throws {
        let remote = "/data/local/tmp/nexus-adb-clipboard-\(Wire.id()).jar"
        let device = ["-s", serial]
        let pushed = try capture(device + ["push", helper.path, remote])
        guard pushed.1 == 0 else { throw NexusError.transfer("O ADB não conseguiu preparar o leitor no celular.") }

        // Android 14 and later require dynamically loaded DEX files to be read-only.
        let launch = "trap 'rm -f \(remote)' EXIT; chmod 400 \(remote) && " +
            "CLASSPATH=\(remote) app_process /system/bin com.nexus.mastersync.adb.NexusUsbClipboard"
        let stream = try start(device + ["shell", "-T", launch], liveInput: true)
        defer { finish(stream) }
        guard let magic = try Self.read(4, from: stream.output) else {
            stream.process.waitUntilExit()
            let message = stream.process.terminationStatus == 4
                ? "O Android deste celular não permite que o ADB leia a área de transferência em segundo plano."
                : "O leitor ADB não iniciou. Confira a conexão e a autorização de depuração no Android."
            throw NexusError.transfer(message)
        }
        guard magic == Data("NXC1".utf8) else { throw NexusError.invalidFrame }

        await onReady()
        while !Task.isCancelled, let header = try Self.read(5, from: stream.output) {
            let kind = header[0]
            let length = header.dropFirst().reduce(0) { ($0 << 8) | Int($1) }
            let limit = kind == 1 ? 32 * 1024 : ClipboardImages.limit + 121
            guard (kind == 1 || kind == 2), (1...limit).contains(length),
                  let payload = try Self.read(length, from: stream.output) else { throw NexusError.invalidFrame }
            if kind == 1, let text = String(data: payload, encoding: .utf8) {
                await onEvent(.text(text))
            } else if kind == 2 {
                let mimeLength = Int(payload[0])
                guard (1...120).contains(mimeLength), mimeLength + 1 < payload.count,
                      let mime = String(data: payload.dropFirst().prefix(mimeLength), encoding: .ascii),
                      ClipboardImages.formats.contains(mime) else { throw NexusError.invalidFrame }
                let bytes = Data(payload.dropFirst(mimeLength + 1))
                guard bytes.count <= ClipboardImages.limit else { throw NexusError.invalidFrame }
                await onEvent(.image(bytes, mime: mime))
            } else { throw NexusError.invalidFrame }
        }
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if let command {
            if let input = command.input { try? input.close() }
            else if command.process.isRunning { command.process.terminate() }
        }
    }

    static let mastersyncPackages = ["com.nexus.mastersync", "com.nexus.mastersync.direct"]

    /// `am start` arguments that open MasterSync and let it accept scan `id` without asking. Quoted for the remote shell.
    static func scanCameraArguments(serial: String, package: String, id: String) -> [String]? {
        guard Wire.validID(id), mastersyncPackages.contains(package) else { return nil }
        return ["-s", serial, "shell", "am", "start", "-n", "'\(package)/com.nexus.mastersync.MainActivity'",
                "--es", "accept-scan", "'\(id)'"]
    }

    /// Opens MasterSync on the phone for scan `id`, trying the full edition first and then the direct one.
    func openScanCamera(serial: String, requestID: String) throws {
        for package in Self.mastersyncPackages {
            guard let arguments = Self.scanCameraArguments(serial: serial, package: package, id: requestID) else { continue }
            let result = try capture(arguments, diagnostics: true)
            let output = String(decoding: result.0, as: UTF8.self).lowercased()
            if result.1 == 0, !output.contains("error"), !output.contains("exception") { return }
        }
        throw NexusError.transfer("O Android não abriu a câmera do MasterSync.")
    }

    private func capture(_ arguments: [String], input: Data? = nil, diagnostics: Bool = false) throws -> (Data, Int32) {
        let command = try start(arguments, liveInput: input != nil, diagnostics: diagnostics)
        defer { finish(command) }
        if let input, let writer = command.input {
            try writer.write(contentsOf: input)
            try writer.close()
        }
        let data = try command.output.readToEnd() ?? Data()
        command.process.waitUntilExit()
        return (data, command.process.terminationStatus)
    }

    private func start(_ arguments: [String], liveInput: Bool, diagnostics: Bool = false) throws -> Command {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { throw CancellationError() }
        let process = Process()
        let output = Pipe()
        let input = liveInput ? Pipe() : nil
        process.executableURL = URL(fileURLWithPath: adb)
        process.arguments = arguments
        process.standardInput = input.map { $0 as Any } ?? FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = diagnostics ? output : FileHandle.nullDevice
        try process.run()
        let command = Command(process: process, output: output.fileHandleForReading, input: input?.fileHandleForWriting)
        self.command = command
        return command
    }

    private func finish(_ command: Command) {
        if let input = command.input { try? input.close() }
        if command.process.isRunning { command.process.terminate() }
        command.process.waitUntilExit()
        try? command.output.close()
        lock.lock()
        if self.command?.process === command.process { self.command = nil }
        lock.unlock()
    }

    private static func read(_ size: Int, from handle: FileHandle) throws -> Data? {
        var bytes = Data()
        while bytes.count < size {
            guard let part = try handle.read(upToCount: size - bytes.count), !part.isEmpty else {
                if bytes.isEmpty { return nil }
                throw NexusError.invalidFrame
            }
            bytes.append(part)
        }
        return bytes
    }
}
