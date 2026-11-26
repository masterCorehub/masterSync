import Darwin
import Foundation
import NexusCore

/// A socket that is closed exactly once, by whoever lets go of it last. Readers and writers borrow it with `use`, so its
/// number can never be closed (and then reused by something else) while someone is still about to read or write it.
final class SocketHandle: @unchecked Sendable {
    private let fd: Int32
    private let lock = NSLock()
    private var users = 1          // the owner's reference, dropped by shutdownAndRelease
    private var closed = false

    init(_ fd: Int32) { self.fd = fd }

    /// Runs [body] with the descriptor while keeping it open. nil when the socket was already shut down.
    func use<T>(_ body: (Int32) -> T) -> T? {
        lock.lock()
        guard !closed else { lock.unlock(); return nil }
        users += 1
        lock.unlock()
        defer { release() }
        return body(fd)
    }

    /// Wakes anyone blocked on the socket and drops the owner's reference. Safe to call again.
    func shutdownAndRelease() {
        lock.lock()
        let first = !closed
        closed = true
        lock.unlock()
        guard first else { return }
        shutdown(fd, SHUT_RDWR)
        release()
    }

    private func release() {
        lock.lock()
        users -= 1
        let last = users == 0
        lock.unlock()
        if last { close(fd) }
    }
}

/// Talks to a scrcpy server on the phone over ADB: video comes back as H.264 events, touches and keys go out as control
/// messages. It needs no permission on the phone and keeps working with the screen locked.
final class ScrcpyClient: @unchecked Sendable {
    private let adb: String
    private let scrcpy: String
    private let lock = NSLock()
    private let writes = DispatchQueue(label: "scrcpy.control.write")

    private var serial = ""
    private var forwardPort: UInt16 = 0      // set once the tunnel exists
    private var remoteJar: String?           // set once the server file is on the phone
    private var server: Process?
    private var serverPipe: Pipe?
    private var serverLog = Data()
    private var video: SocketHandle?
    private var control: SocketHandle?
    private var running = false
    private var endReported = false
    private var eventHandler: (@Sendable (ScrcpyEvent) -> Void)?
    private var endHandler: (@Sendable (String?) -> Void)?

    var onEvent: (@Sendable (ScrcpyEvent) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return eventHandler }
        set { lock.lock(); eventHandler = newValue; lock.unlock() }
    }

    /// The reason it ended, or nil when it was stopped on purpose. Called once, and never for a start that failed (that throws).
    var onEnded: (@Sendable (String?) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return endHandler }
        set { lock.lock(); endHandler = newValue; lock.unlock() }
    }

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
        serverLog = Data()
        self.serial = serial
        lock.unlock()
        do {
            try launch()
        } catch {
            // A start that fails is reported by throwing, not as an ending nobody can explain.
            lock.lock(); endReported = true; lock.unlock()
            stop(wait: true)
            throw error
        }
    }

    private func ensureRunning() throws {
        lock.lock(); let active = running; lock.unlock()
        if !active { throw NexusError.transfer("Conexão cancelada.") }
    }

    private func launch() throws {
        guard let jar = ScrcpyLaunch.serverURL(forScrcpy: scrcpy) else {
            throw NexusError.transfer("O servidor do scrcpy não foi encontrado. Reinstale o scrcpy.")
        }
        let version = try scrcpyVersion()
        guard ScrcpyLaunch.isSupported(version: version) else {
            throw NexusError.transfer("O controle dentro do app precisa do scrcpy 5.0, e a versão instalada é a \(version).")
        }
        try ensureRunning()
        let scid = UInt32.random(in: 1...0x7FFF_FFFF)
        let remote = ScrcpyLaunch.jarPath(scid: scid)
        guard let arguments = ScrcpyLaunch.serverArguments(version: version, scid: scid, maxSize: 1600, maxFPS: 60, bitRate: 8_000_000) else {
            throw NexusError.transfer("A versão do scrcpy não é reconhecida.")
        }
        try run(adb, ["-s", serial, "push", jar.path, remote], timeout: 30,
                failure: "Não foi possível enviar o servidor ao celular. Confira a conexão ADB.")
        lock.lock(); remoteJar = remote; lock.unlock()
        try ensureRunning()

        let local = try freePort()
        try run(adb, ["-s", serial, "forward", "tcp:\(local)", "localabstract:" + ScrcpyLaunch.socketName(scid: scid)], timeout: 10,
                failure: "Não foi possível abrir o túnel até o celular.")
        lock.lock(); forwardPort = local; lock.unlock()
        try ensureRunning()

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
        lock.lock(); server = process; serverPipe = pipe; lock.unlock()
        try process.run()

        let videoHandle = try connectVideo(port: local)
        let controlHandle: SocketHandle
        do { controlHandle = SocketHandle(try connectSocket(port: local)) } catch {
            videoHandle.shutdownAndRelease()
            throw error
        }
        _ = controlHandle.use { fd in
            var one: Int32 = 1
            setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size))
        }
        lock.lock()
        guard running else {
            lock.unlock()
            videoHandle.shutdownAndRelease()
            controlHandle.shutdownAndRelease()
            throw NexusError.transfer("Conexão cancelada.")
        }
        video = videoHandle
        control = controlHandle
        lock.unlock()
        Thread.detachNewThread { [weak self] in self?.readVideo(videoHandle) }
        Thread.detachNewThread { [weak self] in self?.drain(controlHandle) }
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

    /// The tunnel accepts connections before the server listens on the phone. A real connection answers with one byte and a
    /// dead one is closed. Silence is not a failure: the server accepts only one video connection, so a socket it may
    /// already have accepted is waited on, never replaced.
    private func connectVideo(port: UInt16) throws -> SocketHandle {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            try ensureRunning()
            if let fd = try? connectSocket(port: port) {
                var timeout = timeval(tv_sec: 1, tv_usec: 0)
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                var byte: UInt8 = 0
                var outcome = read(fd, &byte, 1)
                while outcome < 0, errno == EAGAIN || errno == EWOULDBLOCK, Date() < deadline {
                    lock.lock(); let active = running; lock.unlock()
                    if !active { close(fd); throw NexusError.transfer("Conexão cancelada.") }
                    outcome = read(fd, &byte, 1)
                }
                if outcome == 1 {
                    var none = timeval(tv_sec: 0, tv_usec: 0)
                    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &none, socklen_t(MemoryLayout<timeval>.size))
                    return SocketHandle(fd)
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

    private func readVideo(_ handle: SocketHandle) {
        var parser = ScrcpyStreamParser(expectDummyByte: false)
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        let reason: String?? = handle.use { fd -> String? in
            while true {
                let count = read(fd, &buffer, buffer.count)
                if count <= 0 { return "A conexão com o vídeo do celular foi encerrada." }
                do {
                    let handler = onEvent
                    for event in try parser.feed(Data(buffer[0..<count])) { handler?(event) }
                } catch {
                    return "O vídeo do celular chegou num formato inesperado."
                }
            }
        }
        // nil here means stop() already closed the socket: nothing to report.
        if let reason, let text = reason { finish(reason: text) }
    }

    /// The server may answer on the control socket (clipboard, acknowledgements); nothing here uses it.
    private func drain(_ handle: SocketHandle) {
        _ = handle.use { fd in
            var buffer = [UInt8](repeating: 0, count: 4096)
            while read(fd, &buffer, buffer.count) > 0 {}
        }
    }

    private func serverEnded() {
        finish(reason: failureText("O servidor do scrcpy no celular foi encerrado."))
    }

    // MARK: Control and stop

    func send(_ message: Data) {
        lock.lock(); let handle = control; let active = running; lock.unlock()
        guard active, let handle else { return }
        writes.async {
            _ = handle.use { fd in
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
    }

    /// Ends the session now. With [wait] it also returns only after the server file and the tunnel are gone.
    func stop(wait: Bool = false) {
        lock.lock()
        let wasRunning = running
        running = false
        eventHandler = nil           // late frames must not reach a display that was already reset
        let videoHandle = video, controlHandle = control
        video = nil
        control = nil
        let process = server, pipe = serverPipe
        server = nil
        serverPipe = nil
        let port = forwardPort, jar = remoteJar, device = serial
        forwardPort = 0
        remoteJar = nil
        lock.unlock()
        // Report first, so a reader woken by the shutdown below cannot announce an ending nobody asked for.
        if wasRunning { finish(reason: nil) }
        videoHandle?.shutdownAndRelease()
        controlHandle?.shutdownAndRelease()
        pipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil
        if process?.isRunning == true { process?.terminate() }
        guard port != 0 || jar != nil else { return }
        let cleanup = { [adb] in
            if port != 0 { _ = try? self.capture(adb, ["-s", device, "forward", "--remove", "tcp:\(port)"], timeout: 8, failure: "") }
            if let jar { _ = try? self.capture(adb, ["-s", device, "shell", "rm -f \(jar)"], timeout: 8, failure: "") }
        }
        if wait { cleanup() } else { DispatchQueue.global(qos: .utility).async(execute: cleanup) }
    }

    private func finish(reason: String?) {
        lock.lock()
        let first = !endReported
        endReported = true
        let handler = endHandler
        lock.unlock()
        guard first else { return }
        // An ending nobody asked for still has to release the server and the tunnel.
        if reason != nil { DispatchQueue.global(qos: .utility).async { self.stop(wait: true) } }
        handler?(reason)
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
            pipe.fileHandleForReading.readabilityHandler = nil
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
