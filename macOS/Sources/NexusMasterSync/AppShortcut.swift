import AppKit
import CryptoKit
import Foundation
import ImageIO
import NexusCore
import UniformTypeIdentifiers

/// A pinned Android app as a Mac app of its own: a small bundle with the app's icon and name that, when opened,
/// asks MasterSync (by a `mastersync://app` link) to show that app in a scrcpy window.
enum AppShortcut {
    static let scheme = "mastersync"
    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/MasterSync Apps", isDirectory: true)
    }

    // MARK: Names and links

    static func bundleName(label: String) -> String {
        var name = label.map { "/:\\".contains($0) || $0.isNewline ? " " : String($0) }.joined()
        name = name.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        while name.hasPrefix(".") { name.removeFirst() }
        name = String(name.prefix(60)).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "App do Android" : name
    }

    static func identifier(peer: String, component: String) -> String {
        let digest = SHA256.hash(data: Data((peer + "|" + component).utf8))
        return "com.nexus.mastersync.shortcut." + digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    private static let queryAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func encode(_ text: String) -> String { text.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? "" }

    static func launchURL(peer: String, app: AndroidApp) -> URL {
        URL(string: "\(scheme)://app?peer=\(encode(peer))&component=\(encode(app.component))&label=\(encode(app.label))")!
    }

    /// The phone and app a link points to, or nil when the link is not ours or carries anything that is not a valid app.
    static func parse(_ url: URL) -> (peer: String, app: AndroidApp)? {
        guard url.scheme == scheme, url.host == "app",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard let peer = value("peer"), Wire.validID(peer), let component = value("component") else { return nil }
        let app = AndroidApp(component: component, label: String((value("label") ?? component).prefix(70)))
        guard app.validComponent else { return nil }
        return (peer, app)
    }

    // MARK: Bundles

    private struct Marker { let peer: String; let component: String }

    private static func marker(of bundle: URL) -> Marker? {
        guard let plist = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
              let peer = plist["MasterSyncPeer"] as? String, let component = plist["MasterSyncComponent"] as? String else { return nil }
        return Marker(peer: peer, component: component)
    }

    private static func ownBundles(in directory: URL) -> [(url: URL, marker: Marker)] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".app") }.compactMap { name in
            let url = directory.appendingPathComponent(name)
            return marker(of: url).map { (url, $0) }
        }
    }

    @discardableResult
    static func install(app: AndroidApp, peer: String, icon: NSImage?, in directory: URL) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        var name = bundleName(label: app.label)
        let identifier = identifier(peer: peer, component: app.component)
        var bundle = directory.appendingPathComponent(name + ".app")
        if manager.fileExists(atPath: bundle.path), let existing = marker(of: bundle),
           existing.peer != peer || existing.component != app.component {
            name += " (\(identifier.suffix(4)))"
            bundle = directory.appendingPathComponent(name + ".app")
        }
        try? manager.removeItem(at: bundle)

        let contents = bundle.appendingPathComponent("Contents")
        try manager.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try manager.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "CFBundleName": name, "CFBundleDisplayName": name, "CFBundleIdentifier": identifier,
            "CFBundleExecutable": "launch", "CFBundleIconFile": "AppIcon", "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1", "LSMinimumSystemVersion": "14.0",
            // The launcher only hands over to MasterSync, so it needs no Dock icon of its own.
            "LSUIElement": true, "MasterSyncPeer": peer, "MasterSyncComponent": app.component,
        ]
        try (plist as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"))

        let script = contents.appendingPathComponent("MacOS/launch")
        let link = launchURL(peer: peer, app: app).absoluteString
        try "#!/bin/sh\nexec /usr/bin/open \"\(link)\"\n".write(to: script, atomically: true, encoding: .utf8)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        try writeIcon(icon ?? placeholder(for: app), to: contents.appendingPathComponent("Resources/AppIcon.icns"))
        sign(bundle)
        return bundle
    }

    static func remove(app: AndroidApp, peer: String, in directory: URL) throws {
        for (url, marker) in ownBundles(in: directory) where marker.peer == peer && marker.component == app.component {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Makes the shortcuts for [peer] match the pinned apps: new ones appear, unpinned ones go. Anything else in the
    /// folder, including shortcuts of other phones, is left alone.
    static func sync(pinned: [(AndroidApp, NSImage?)], peer: String, in directory: URL) throws {
        let keep = Set(pinned.map(\.0.component))
        for (url, marker) in ownBundles(in: directory) where marker.peer == peer && !keep.contains(marker.component) {
            try FileManager.default.removeItem(at: url)
        }
        for (app, icon) in pinned { try install(app: app, peer: peer, icon: icon, in: directory) }
    }

    // MARK: Icons

    private static func placeholder(for app: AndroidApp) -> NSImage {
        let size = NSSize(width: 512, height: 512)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(NexusPalette.hueColor(NexusPalette.stableHue(app.component))).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 112, yRadius: 112).fill()
        let letter = String(app.label.prefix(1)).uppercased() as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 260, weight: .bold), .foregroundColor: NSColor.white]
        let box = letter.size(withAttributes: attributes)
        letter.draw(at: NSPoint(x: (size.width - box.width) / 2, y: (size.height - box.height) / 2), withAttributes: attributes)
        image.unlockFocus()
        return image
    }

    private static func writeIcon(_ image: NSImage, to url: URL) throws {
        let side = 512
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { throw NexusError.invalidFrame }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        // Keep the app's own shape: the icon is drawn on a transparent square, inset like macOS icons.
        image.draw(in: NSRect(x: 40, y: 40, width: side - 80, height: side - 80), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let cgImage = rep.cgImage,
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.icns.identifier as CFString, 1, nil) else {
            throw NexusError.invalidFrame
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { throw NexusError.invalidFrame }
    }

    /// An ad-hoc signature so macOS runs the script bundle without complaint; failing to sign is not an error.
    private static func sign(_ bundle: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--sign", "-", bundle.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
