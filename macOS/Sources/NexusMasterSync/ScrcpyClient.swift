import Darwin
import Foundation
import NexusCore

/// Talks to a scrcpy server on the phone over ADB: video comes back as H.264 events, touches and keys go out as control
/// messages. It needs no permission on the phone and keeps working with the screen locked.
final class ScrcpyClient: @unchecked Sendable {
    private let adb: String
    private let scrcpy: String
    private let lock = NSLock()
    private let writes = DispatchQueue(label: "scrcpy.control.write")

    private var serial = ""
    private var port: UInt16 = 0
    private var server: Process?
    private var serverLog = Data()
    private var videoFD: Int32 = -1
    private var controlFD: Int32 = -1
    private var running = false
    private var endReported = false
    private var cleanedUp = false

    var onEvent: (@Sendable (ScrcpyEvent) -> Void)?
    /// The reason it ended, or nil when it was stopped on purpose. Called once.
    var onEnded: (@Sendable (String?) -> Void)?

    init(adb: String, scrcpyExecutable: String) {
        self.adb = adb
        scrcpy = scrcpyExecutable
    }

    // MARK: Start

    /// Blocks until the video stream is connected. Call it off the main thread.
    func start(serial: String) throws {
        lock.lock()
        guard !running else { lock.unlock(); return }
        running = true
        endReported = false
        cleanedUp = false
        self.serial = serial
        lock.unlock()
        do {
            try launch()
        } catch {
            stop(wait: true, reason: nil)
            throw error
        }
    }

    private func launch() throws {
        guard let jar = ScrcpyLaunch.serverURL(forScrcpy: scrcpy) else {
            throw NexusError.transfer("O servidor do scrcpy não foi encontrado. Reinstale o scrcpy.")
        }
        let version = try scrcpyVersion()
        let scid = UInt32.random(in: 1...0x7FFF_FFFF)
        guard let arguments = ScrcpyLaunch.serverArguments(version: version, scid: scid, maxSize: 1600, maxFPS: 60, bitRate: 8_000_000) else {
            throw NexusError.transfer("A versão do scrcpy não é reconhecida.")
        }
        try run(adb, ["-s", serial, "push", jar.path, "/data/local/tmp/scrcpy-server.jar"], timeout: 30,
                failure: "Não foi possível enviar o servidor ao celular. Confira a conexão ADB.")
        let local = try freePort()
        lock.lock(); port = local; lock.unlock()
        try run(adb, ["-s", serial, "forward", "tcp:\(local)", "localabstract:" + ScrcpyLaunch.socketName(scid: scid)], timeout: 10,
                failure: "Não foi possível abrir o túnel até o celular.")

        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: adb)
        process.arguments = ["-s", serial, "shell"] + arguments
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            if data.isEmpty { handle.readabilityHandler = nil; return }
            self.lock.lock(); self.serverLog.append(data); self.serverLog = self.serverLog.suffix(2048); self.lock.unlock()
        }
        process.terminationHandler = { [weak self] _ in self?.serverEnded() }
        lock.lock(); server = process; lock.unlock()
        try process.run()

        let video = try connectVideo(port: local)
        let control = try connectSocket(port: local)
        var one: Int32 = 1
        setsockopt(control, IPPROTO_TCP, TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size))
        lock.lock(); videoFD = video; controlFD = control; lock.unlock()
        Thread.detachNewThread { [weak self] in self?.readVideo(video) }
        Thread.detachNewThread { [weak self] in self?.drain(control) }
    }

    private func scrcpyVersion() throws -> String {
        let output = try capture(scrcpy, ["--version"], timeout: 10, failure: "Não foi possível ler a versão do scrcpy.")
        let first = output.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let fields = first.split(separator: " ")
        guard fields.count >= 2 else { throw NexusError.transfer("Não foi possível ler a versão do scrcpy.") }
        return String(fields[1])
    }

    // MARK: Sockets

    private func freePort() throws -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw NexusError.transfer("Não foi possível abrir uma porta local.") }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) }
        }
        guard bound == 0 else { throw NexusError.transfer("Não foi possível abrir uma porta local.") }
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard named == 0 else { throw NexusError.transfer("Não foi possível abrir uma porta local.") }
        return UInt16(bigEndian: address.sin_port)
    }

    private func connectSocket(port: UInt16) throws -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw NexusError.transfer("Não foi possível abrir a conexão com o celular.") }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = port.bigEndian
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard result == 0 else { close(fd); throw NexusError.transfer("Não foi possível conectar ao túnel.") }
        return fd
    }

    /// The tunnel accepts connections before the server listens on the phone; a real connection answers with one byte.
    private func connectVideo(port: UInt16) throws -> Int32 {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            lock.lock(); let stopped = !running; lock.unlock()
            if stopped { throw NexusError.transfer("Conexão cancelada.") }
            if let fd = try? connectSocket(port: port) {
                var timeout = timeval(tv_sec: 1, tv_usec: 0)
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                var byte: UInt8 = 0
                if read(fd, &byte, 1) == 1 {
                    var none = timeval(tv_sec: 0, tv_usec: 0)
                    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &none, socklen_t(MemoryLayout<timeval>.size))
                    return fd
                }
                close(fd)
            }
            Thread.sleep(forTimeInterval: 0.15)
        }
        throw NexusError.transfer(failureText("O celular não respondeu ao servidor do scrcpy."))
    }

    private func failureText(_ base: String) -> String {
        lock.lock(); defer { lock.unlock() }
        let log = String(decoding: serverLog, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !log.isEmpty else { return base }
        return base + " " + String(log.suffix(240))
    }

    // MARK: Streams

    private func readVideo(_ fd: Int32) {
        var parser = ScrcpyStreamParser(expectDummyByte: false)
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count <= 0 { break }
            do {
                for event in try parser.feed(Data(buffer[0..<count])) { onEvent?(event) }
            } catch {
                close(fd)
                finish(reason: "O vídeo do celular chegou num formato inesperado.")
                return
            }
        }
        close(fd)
        finish(reason: "A conexão com o vídeo do celular foi encerrada.")
    }

    /// The server may answer on the control socket (clipboard, acknowledgements); nothing here uses it.
    private func drain(_ fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while read(fd, &buffer, buffer.count) > 0 {}
        close(fd)
    }

    private func serverEnded() {
        finish(reason: failureText("O servidor do scrcpy no celular foi encerrado."))
    }

    // MARK: Control and stop

    func send(_ message: Data) {
        lock.lock(); let fd = controlFD; let active = running; lock.unlock()
        guard active, fd >= 0 else { return }
        writes.async {
            message.withUnsafeBytes { raw in
                var sent = 0
                while sent < raw.count {
                    let result = write(fd, raw.baseAddress! + sent, raw.count - sent)
                    if result <= 0 { return }
                    sent += result
                }
            }
        }
    }

    /// Ends the session now. With [wait] it also returns only after the server and the tunnel are gone.
    func stop(wait: Bool = false) { stop(wait: wait, reason: nil) }

    private func stop(wait: Bool, reason: String?) {
        lock.lock()
        let wasRunning = running
        running = false
        let video = videoFD, control = controlFD
        videoFD = -1
        controlFD = -1
        let process = server
        server = nil
        let local = port, device = serial
        let shouldClean = !cleanedUp && !device.isEmpty
        cleanedUp = true
        lock.unlock()
        // shutdown wakes the reader threads, which close their own sockets.
        if video >= 0 { shutdown(video, SHUT_RDWR) }
        if control >= 0 { shutdown(control, SHUT_RDWR) }
        process?.terminationHandler = nil
        if process?.isRunning == true { process?.terminate() }
        if wasRunning { finish(reason: reason) }
        guard shouldClean else { return }
        let cleanup = { [adb] in
            if local != 0 { _ = try? self.capture(adb, ["-s", device, "forward", "--remove", "tcp:\(local)"], timeout: 8, failure: "") }
            _ = try? self.capture(adb, ["-s", device, "shell", "rm -f /data/local/tmp/scrcpy-server.jar"], timeout: 8, failure: "")
        }
        if wait { cleanup() } else { DispatchQueue.global(qos: .utility).async(execute: cleanup) }
    }

    private func finish(reason: String?) {
        lock.lock()
        let first = !endReported
        endReported = true
        lock.unlock()
        guard first else { return }
        // An ending nobody asked for still has to release the server and the tunnel.
        if reason != nil { DispatchQueue.global(qos: .utility).async { self.stop(wait: true, reason: nil) } }
        onEnded?(reason)
    }

    // MARK: Processes

    private func run(_ executable: String, _ arguments: [String], timeout: TimeInterval, failure: String) throws {
        _ = try capture(executable, arguments, timeout: timeout, failure: failure)
    }

    @discardableResult
    private func capture(_ executable: String, _ arguments: [String], timeout: TimeInterval, failure: String) throws -> String {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        try process.run()
        let output = LockedData()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil } else { output.append(data) }
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw NexusError.transfer(failure.isEmpty ? "O comando demorou demais." : failure + " (tempo esgotado)")
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        let text = String(decoding: output.value + pipe.fileHandleForReading.availableData, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw NexusError.transfer(failure.isEmpty ? text : failure + " " + String(text.suffix(200)))
        }
        return text
    }
}

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ more: Data) { lock.lock(); data.append(more); lock.unlock() }
    var value: Data { lock.lock(); defer { lock.unlock() }; return data }
}
