import AppKit
import NexusCore
@testable import NexusMasterSync
import XCTest

final class AppShortcutTests: XCTestCase {
    private let peer = "6f9619ff-8b86-d011-b42d-00c04fc964ff"
    private let whatsapp = AndroidApp(component: "com.whatsapp/.Main", label: "WhatsApp")

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shortcuts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func icon() -> NSImage {
        let image = NSImage(size: NSSize(width: 96, height: 96))
        image.lockFocus(); NSColor.systemGreen.setFill(); NSRect(x: 0, y: 0, width: 96, height: 96).fill(); image.unlockFocus()
        return image
    }

    // MARK: Names and links

    func testBundleNameIsSafeForTheFileSystem() {
        XCTAssertEqual(AppShortcut.bundleName(label: "WhatsApp"), "WhatsApp")
        XCTAssertEqual(AppShortcut.bundleName(label: "  A/B:C\\D  "), "A B C D")
        XCTAssertEqual(AppShortcut.bundleName(label: ""), "App do Android")
        XCTAssertEqual(AppShortcut.bundleName(label: "///"), "App do Android")
        XCTAssertLessThanOrEqual(AppShortcut.bundleName(label: String(repeating: "x", count: 200)).count, 60)
        XCTAssertFalse(AppShortcut.bundleName(label: ".hidden").hasPrefix("."))
    }

    func testIdentifierDependsOnPhoneAndApp() {
        let a = AppShortcut.identifier(peer: peer, component: "com.a/.M")
        XCTAssertEqual(a, AppShortcut.identifier(peer: peer, component: "com.a/.M"))
        XCTAssertNotEqual(a, AppShortcut.identifier(peer: peer, component: "com.b/.M"))
        XCTAssertNotEqual(a, AppShortcut.identifier(peer: "11111111-1111-1111-1111-111111111111", component: "com.a/.M"))
        XCTAssertTrue(a.hasPrefix("com.nexus.mastersync.shortcut."))
    }

    func testLinkRoundTrips() throws {
        let url = AppShortcut.launchURL(peer: peer, app: whatsapp)
        XCTAssertEqual(url.scheme, "mastersync")
        let parsed = try XCTUnwrap(AppShortcut.parse(url))
        XCTAssertEqual(parsed.peer, peer)
        XCTAssertEqual(parsed.app.component, "com.whatsapp/.Main")
        XCTAssertEqual(parsed.app.label, "WhatsApp")
    }

    func testLinkWithAccentsAndSpacesRoundTrips() throws {
        let app = AndroidApp(component: "com.x/.Main", label: "Câmera & Fotos")
        XCTAssertEqual(AppShortcut.parse(AppShortcut.launchURL(peer: peer, app: app))?.app.label, "Câmera & Fotos")
    }

    func testBadLinksAreRefused() {
        XCTAssertNil(AppShortcut.parse(URL(string: "https://example.com/app?peer=\(peer)&component=a.b/.C")!))
        XCTAssertNil(AppShortcut.parse(URL(string: "mastersync://app?peer=nope&component=a.b/.C")!))
        XCTAssertNil(AppShortcut.parse(URL(string: "mastersync://app?peer=\(peer)&component=a%3Bb")!))
        XCTAssertNil(AppShortcut.parse(URL(string: "mastersync://app?peer=\(peer)&component=a.b/.C%3B%20rm%20-rf")!))
        XCTAssertNil(AppShortcut.parse(URL(string: "mastersync://other?peer=\(peer)&component=a.b/.C")!))
        XCTAssertNil(AppShortcut.parse(URL(string: "mastersync://app?peer=\(peer)")!))
    }

    // MARK: Bundles

    func testInstallBuildsARunnableMacApp() throws {
        let directory = try temporaryDirectory()
        let bundle = try AppShortcut.install(app: whatsapp, peer: peer, icon: icon(), in: directory)
        XCTAssertEqual(bundle.lastPathComponent, "WhatsApp.app")
        let plist = try XCTUnwrap(NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")) as? [String: Any])
        XCTAssertEqual(plist["CFBundleName"] as? String, "WhatsApp")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "launch")
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, AppShortcut.identifier(peer: peer, component: whatsapp.component))
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
        XCTAssertEqual(plist["MasterSyncPeer"] as? String, peer)
        XCTAssertEqual(plist["MasterSyncComponent"] as? String, whatsapp.component)
        let script = bundle.appendingPathComponent("Contents/MacOS/launch")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: script.path))
        let body = try String(contentsOf: script, encoding: .utf8)
        XCTAssertTrue(body.contains("mastersync://app?"))
        XCTAssertTrue(body.hasPrefix("#!/bin/sh"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("Contents/Resources/AppIcon.icns").path))
    }

    func testInstallWithoutAnIconStillWorks() throws {
        let bundle = try AppShortcut.install(app: whatsapp, peer: peer, icon: nil, in: try temporaryDirectory())
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("Contents/Resources/AppIcon.icns").path))
    }

    func testInstallingAgainReplacesTheBundle() throws {
        let directory = try temporaryDirectory()
        _ = try AppShortcut.install(app: whatsapp, peer: peer, icon: icon(), in: directory)
        _ = try AppShortcut.install(app: whatsapp, peer: peer, icon: icon(), in: directory)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".app") }.count, 1)
    }

    func testTwoAppsWithTheSameNameDoNotCollide() throws {
        let directory = try temporaryDirectory()
        let other = AndroidApp(component: "com.business.whatsapp/.Main", label: "WhatsApp")
        let a = try AppShortcut.install(app: whatsapp, peer: peer, icon: nil, in: directory)
        let b = try AppShortcut.install(app: other, peer: peer, icon: nil, in: directory)
        XCTAssertNotEqual(a.lastPathComponent, b.lastPathComponent)
    }

    func testSyncKeepsPinnedAndRemovesTheRest() throws {
        let directory = try temporaryDirectory()
        let maps = AndroidApp(component: "com.maps/.Main", label: "Maps")
        let stale = AndroidApp(component: "com.old/.Main", label: "Antigo")
        _ = try AppShortcut.install(app: stale, peer: peer, icon: nil, in: directory)
        let otherPhone = "11111111-1111-1111-1111-111111111111"
        _ = try AppShortcut.install(app: AndroidApp(component: "com.keep/.Main", label: "Outro celular"), peer: otherPhone, icon: nil, in: directory)
        try AppShortcut.sync(pinned: [(whatsapp, icon()), (maps, nil)], peer: peer, in: directory)
        let names = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
        XCTAssertEqual(names, ["WhatsApp.app", "Maps.app", "Outro celular.app"])
    }

    func testSyncIgnoresFilesThatAreNotOurs() throws {
        let directory = try temporaryDirectory()
        try Data("x".utf8).write(to: directory.appendingPathComponent("notas.txt"))
        let foreign = directory.appendingPathComponent("Outro.app/Contents")
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: true)
        try ([:] as NSDictionary).write(to: foreign.appendingPathComponent("Info.plist"))
        try AppShortcut.sync(pinned: [], peer: peer, in: directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("notas.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Outro.app").path))
    }

    func testRemoveDeletesOnlyThatShortcut() throws {
        let directory = try temporaryDirectory()
        _ = try AppShortcut.install(app: whatsapp, peer: peer, icon: nil, in: directory)
        try AppShortcut.remove(app: whatsapp, peer: peer, in: directory)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}
