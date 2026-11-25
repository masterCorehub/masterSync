import CryptoKit
import Foundation
import ImageIO
import PDFKit
import XCTest
@testable import NexusCore
@testable import NexusMasterSync

final class AndroidEmulatorTests: XCTestCase {
    @MainActor func testAndroidClientPairingClipboardAndResumableUpload() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let adb = environment["NEXUS_TEST_ANDROID_ADB"],
              let serial = environment["NEXUS_TEST_ANDROID_SERIAL"], serial.hasPrefix("emulator-") else {
            throw XCTSkip("Defina o ADB e o serial do emulador para o teste entre plataformas.")
        }
        let server = LocalServer(identity: try TLSIdentity.ephemeral(), id: Wire.id(),
                                 name: "Mac de teste", peers: []) { _ in }
        let ready = expectation(description: "servidor disponível")
        server.onUpdate = {
            if server.port != nil { ready.fulfill(); server.onUpdate = nil }
        }
        server.start(port: 0, advertise: false)
        defer { server.stop() }
        wait(for: [ready], timeout: 10)
        let qr = try server.invite(host: "127.0.0.1")
        let port = "tcp:\(qr.port)"
        XCTAssertEqual(try run(adb, ["-s", serial, "reverse", port, port]), 0)
        defer { _ = try? run(adb, ["-s", serial, "reverse", "--remove", port]) }

        let clipboard = expectation(description: "texto do Android")
        let finished = expectation(description: "arquivo íntegro depois da reconexão")
        let scanSaved = expectation(description: "duas páginas JPEG e PDF verificados e salvos")
        let android = expectation(description: "instrumentação concluída")
        var approved = false
        var interrupted = false
        var received = Data()
        var offer: FileOffer?
        var receivedOriginal = false
        let scanInbox = FileManager.default.temporaryDirectory.appendingPathComponent(Wire.id(), isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scanInbox) }
        let scanTransfers = FileTransfers(storage: scanInbox) { peer, message in server.send(message, to: peer) }
        var scanUploads: [ReceivedFile] = []
        scanTransfers.didReceive = { file in
            scanUploads.append(file)
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path))
            XCTAssertEqual(try? FileOffer.hash(file.url), file.offer.hash)
            if scanUploads.count <= 2 {
                XCTAssertTrue(file.offer.isScanPage)
                XCTAssertTrue(file.offer.name.hasSuffix("Página \(scanUploads.count).jpg"))
                XCTAssertNotNil(CGImageSourceCreateWithURL(file.url as CFURL, nil))
            } else {
                XCTAssertEqual(file.offer.mime, "application/pdf")
                XCTAssertFalse(file.offer.isScanPage)
                XCTAssertEqual(PDFDocument(url: file.url)?.pageCount, 2)
                let saved = FileTransfers(storage: scanInbox) { _, _ in }
                XCTAssertEqual(saved.received.filter { $0.offer.isScanPage }.count, 2)
                XCTAssertEqual(saved.received.count, 3)
                scanSaved.fulfill()
            }
        }
        server.onUpdate = {
            guard !approved, let pending = server.pending else { return }
            approved = true
            server.confirm(pending.id, allow: true)
        }
        server.onSession = { peer in
            scanTransfers.allow(peer)
            var flags = Message("capabilities")
            flags.files = true
            flags.clipboard = true
            server.send(flags, to: peer)
            if !interrupted {
                var text = Message("clipboard")
                text.text = "Olá do Mac"
                server.send(text, to: peer)
            }
        }
        server.onMessage = { peer, message in
            if receivedOriginal && message.type.hasPrefix("file") {
                scanTransfers.handle(message, peer: peer)
                return
            }
            switch message.type {
            case "clipboard":
                XCTAssertEqual(message.text, "Olá do Android")
                clipboard.fulfill()
            case "fileOffer":
                let offered = FileOffer(message)
                XCTAssertNotNil(offered)
                if let offer { XCTAssertEqual(offer, offered) } else { offer = offered }
                if interrupted { XCTAssertEqual(received.count, Wire.chunk) }
                var response = Message("fileOffset")
                response.id = message.id
                response.offset = Int64(received.count)
                server.send(response, to: peer)
            case "fileData":
                guard let data = message.data.flatMap({ Data(base64Encoded: $0) }) else { return XCTFail("Bloco ausente") }
                XCTAssertEqual(message.offset, Int64(received.count))
                received.append(data)
                if !interrupted {
                    interrupted = true
                    server.stop()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        server.start(port: qr.port, advertise: false)
                    }
                } else {
                    var response = Message("fileAck")
                    response.id = message.id
                    response.offset = Int64(received.count)
                    server.send(response, to: peer)
                }
            case "fileDone":
                XCTAssertEqual(Int64(received.count), offer?.size)
                XCTAssertEqual(Data(SHA256.hash(data: received)).base64EncodedString(), offer?.hash)
                var response = Message("fileComplete")
                response.id = message.id
                receivedOriginal = true
                server.send(response, to: peer)
                finished.fulfill()
            default: break
            }
        }

        let payload = try JSONEncoder().encode(qr).base64EncodedString()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adb)
        process.arguments = ["-s", serial, "shell", "am", "instrument", "-w", "-e", "class", "com.nexus.mastersync.ConnectionSmokeTest",
                             "-e", "nexusInvitation", payload,
                             "com.nexus.mastersync.test/androidx.test.runner.AndroidJUnitRunner"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.terminationHandler = { _ in android.fulfill() }
        try process.run()
        wait(for: [clipboard, finished, scanSaved, android], timeout: 75)
        if process.isRunning {
            process.terminate()
            XCTFail("A instrumentação Android excedeu o prazo.")
        } else {
            let result = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTAssertTrue(result.contains("OK (1 test)") && process.terminationStatus == 0,
                          result.replacingOccurrences(of: payload, with: "[invitation]"))
        }
    }

    private func run(_ executable: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
