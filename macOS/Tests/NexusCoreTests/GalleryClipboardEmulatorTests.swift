import CryptoKit
import Foundation
import XCTest
@testable import NexusCore

final class GalleryClipboardEmulatorTests: XCTestCase {
    func testClipboardImagesAndGalleryOnLockedAndroid() throws {
        let env = ProcessInfo.processInfo.environment
        guard let adb = env["NEXUS_TEST_ANDROID_ADB"],
              let serial = env["NEXUS_TEST_ANDROID_SERIAL"], serial.hasPrefix("emulator-"),
              env["NEXUS_TEST_GALLERY"] == "1" else {
            throw XCTSkip("Defina NEXUS_TEST_GALLERY=1 e selecione o teclado correspondente no emulador.")
        }
        let standardKeyboard = env["NEXUS_TEST_STANDARD_KEYBOARD"] == "1"
        let server = LocalServer(identity: try TLSIdentity.ephemeral(), id: Wire.id(),
                                 name: "Galeria de teste", peers: []) { _ in }
        let started = expectation(description: "servidor local")
        server.onUpdate = { if server.port != nil { started.fulfill(); server.onUpdate = nil } }
        server.start(port: 0, advertise: false)
        defer { server.stop() }
        wait(for: [started], timeout: 10)
        let qr = try server.invite(host: "127.0.0.1")
        let port = "tcp:\(qr.port)"
        XCTAssertEqual(try run(adb, ["-s", serial, "reverse", port, port]), 0)
        defer { _ = try? run(adb, ["-s", serial, "reverse", "--remove", port]) }

        let clipboard = expectation(description: "imagem copiada no Android fora do Nexus")
        let textClipboard = standardKeyboard ? expectation(description: "texto enviado ao ativar sincronização com o Nexus em foco") : nil
        let lockedGallery = standardKeyboard ? nil : expectation(description: "galeria consultada com Android bloqueado")
        let preview = standardKeyboard ? nil : expectation(description: "prévia da foto")
        let original = standardKeyboard ? nil : expectation(description: "original associado à abertura")
        let instrumented = expectation(description: "instrumentação concluída")
        let searchID = Wire.id()
        let previewID = Wire.id()
        let downloadID = Wire.id()
        var startedBackground = false
        var copied: Data?
        var offer: FileOffer?
        var bytes = Data()
        var approved = false
        var selected: String?
        var clipboardReady = !standardKeyboard
        var canReturnImage = !standardKeyboard
        let images = ClipboardImages()

        server.onUpdate = {
            if !approved, let pending = server.pending {
                approved = true
                server.confirm(pending.id, allow: true)
            }
        }
        func sendCapabilities(to peer: String) {
            var flags = Message("capabilities")
            flags.clipboard = clipboardReady
            flags.clipboardImages = clipboardReady
            flags.files = true
            flags.gallery = true
            server.send(flags, to: peer)
        }
        server.onSession = { peer in
            selected = peer
            sendCapabilities(to: peer)
        }
        images.send = { [weak server] frame in if let selected { server?.send(frame, to: selected) } }
        images.received = { [weak images] data, mime in
            guard copied == nil else { return XCTFail("A escrita recebida voltou ao Mac como cópia nova.") }
            XCTAssertEqual(mime, "image/png")
            copied = data
            clipboard.fulfill()
            if canReturnImage { images?.offer(data, mime: mime) }
        }
        server.onMessage = { peer, message in
            switch message.type {
            case "capabilities":
                if message.backgroundConnection == true { startedBackground = true }
            case "qaClipboardFocused":
                XCTAssertTrue(standardKeyboard && !clipboardReady)
                clipboardReady = true
                sendCapabilities(to: peer)
            case "clipboard" where standardKeyboard:
                XCTAssertEqual(message.text, "Cópia com teclado padrão")
                textClipboard?.fulfill()
                var reply = Message("clipboard")
                reply.text = "Texto do Mac de teste"
                server.send(reply, to: peer)
            case "qaClipboardBackground":
                XCTAssertTrue(standardKeyboard && !canReturnImage)
                canReturnImage = true
                if let copied { images.offer(copied, mime: "image/png") }
            case let type where type.hasPrefix("clipboardImage"):
                images.receive(message)
            case "qaGalleryReady":
                XCTAssertTrue(startedBackground)
                var query = Message("galleryList")
                query.id = searchID
                query.query = "_100%_conexao"
                query.mime = "image"
                query.order = "name"
                query.addedFrom = Int64(Date.now.addingTimeInterval(-600).timeIntervalSince1970)
                query.addedBefore = Int64(Date.now.addingTimeInterval(600).timeIntervalSince1970)
                server.send(query, to: peer)
            case "galleryPage":
                guard message.id == searchID, let page = message.media, let photo = page.first else {
                    return XCTFail("Consulta da galeria sem mídia.")
                }
                XCTAssertEqual(page.count, 1)
                XCTAssertEqual(photo.name, "Nexus_100%_conexao.png")
                lockedGallery?.fulfill()
                var view = Message("galleryPreview")
                view.id = previewID
                view.mediaId = photo.id
                server.send(view, to: peer)
                var fetch = Message("galleryFetch")
                fetch.id = photo.id
                fetch.transferId = downloadID
                server.send(fetch, to: peer)
            case "galleryPreviewImage":
                XCTAssertEqual(message.id, previewID)
                XCTAssertNotNil(message.data.flatMap { Data(base64Encoded: $0) })
                preview?.fulfill()
            case "galleryStatus":
                XCTFail(message.message ?? "Falha na galeria.")
            case "fileOffer":
                guard message.id == downloadID else { return }
                offer = FileOffer(message)
                var offset = Message("fileOffset")
                offset.id = downloadID
                offset.offset = 0
                server.send(offset, to: peer)
            case "fileData":
                guard message.id == downloadID, let chunk = message.data.flatMap({ Data(base64Encoded: $0) }) else { return }
                XCTAssertEqual(Int64(bytes.count), message.offset)
                bytes.append(chunk)
                var ack = Message("fileAck")
                ack.id = downloadID
                ack.offset = Int64(bytes.count)
                server.send(ack, to: peer)
            case "fileDone":
                guard message.id == downloadID else { return }
                XCTAssertEqual(bytes, copied)
                XCTAssertEqual(offer?.hash, Data(SHA256.hash(data: bytes)).base64EncodedString())
                var ack = Message("fileComplete")
                ack.id = downloadID
                server.send(ack, to: peer)
                original?.fulfill()
            default: break
            }
        }

        let invite = try JSONEncoder().encode(qr).base64EncodedString()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adb)
        process.arguments = ["-s", serial, "shell", "am", "instrument", "-w", "-e", "class",
                             "com.nexus.mastersync.GalleryClipboardSmokeTest", "-e", "nexusInvitation", invite,
                             "-e", "nexusStandardKeyboard", standardKeyboard ? "1" : "0",
                             "com.nexus.mastersync.test/androidx.test.runner.AndroidJUnitRunner"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.terminationHandler = { _ in instrumented.fulfill() }
        try process.run()
        let expected = [clipboard, instrumented] + [textClipboard, lockedGallery, preview, original].compactMap { $0 }
        wait(for: expected, timeout: 80)
        if process.isRunning {
            process.terminate()
            XCTFail("A instrumentação da galeria excedeu o prazo.")
        } else {
            let result = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTAssertTrue(result.contains("OK (1 test)") && process.terminationStatus == 0,
                          result.replacingOccurrences(of: invite, with: "[invitation]"))
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
