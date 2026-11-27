import AppKit
import NexusCore
@testable import NexusMasterSync
import SwiftUI
import XCTest

/// Renders the new screens in both appearances, so a broken layout or a crash shows up here, and saves PNGs for a look.
@MainActor
final class ShellRenderTests: XCTestCase {
    static let outputDirectory = "/private/tmp/claude-501/redesign"

    /// Counts distinct colors on a coarse grid: a blank render has two or three.
    static func distinctColors(in image: NSImage) -> Int {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return 0 }
        var seen = Set<UInt32>()
        for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 3) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                seen.insert(UInt32(c.redComponent * 255) << 16 | UInt32(c.greenComponent * 255) << 8 | UInt32(c.blueComponent * 255))
            }
        }
        return seen.count
    }

    func render<V: View>(_ view: V, name: String, scheme: ColorScheme, width: CGFloat, height: CGFloat) throws -> NSImage {
        let palette = NexusPalette(scheme: scheme)
        let framed = view.frame(width: width, height: height).background(palette.canvas)
            .environment(\.colorScheme, scheme).environment(\.nexusFlatBackdrop, true).foregroundStyle(palette.ink)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.nsImage, "\(name) não renderizou")
        XCTAssertGreaterThan(Self.distinctColors(in: image), 20, "\(name) saiu em branco (ScrollView não aparece no ImageRenderer)")
        try? FileManager.default.createDirectory(atPath: Self.outputDirectory, withIntermediateDirectories: true)
        if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: "\(Self.outputDirectory)/\(name)-\(scheme == .dark ? "escuro" : "claro").png"))
        }
        return image
    }

    func testSidebarRendersInBothSchemes() throws {
        let model = NexusModel()
        for scheme in [ColorScheme.dark, .light] {
            let image = try render(Sidebar(model: model, pinnedApps: [], openApp: { _ in }, manageApps: {}),
                                   name: "barra-lateral", scheme: scheme, width: 244, height: 790)
            XCTAssertEqual(image.size.width, 244, accuracy: 1)
            XCTAssertEqual(image.size.height, 790, accuracy: 1)
        }
    }

    func testSidebarWithPinnedAppsRenders() throws {
        let model = NexusModel()
        let apps = (1...6).map { AndroidApp(component: "com.example.app\($0)/.Main", label: "App \($0)") }
        let image = try render(Sidebar(model: model, pinnedApps: apps, openApp: { _ in }, manageApps: {}),
                               name: "barra-lateral-apps", scheme: .dark, width: 244, height: 790)
        XCTAssertEqual(image.size.height, 790, accuracy: 1)
    }

    // MARK: Overview

    func overviewData(connected: Bool) -> OverviewData {
        OverviewData(
            name: "Pixel 9 Pro", active: connected, battery: connected ? 82 : nil, charging: connected,
            controls: QuickControls.items(QuickControls.Inputs(phoneName: "Pixel 9 Pro", online: connected, dndAllowed: true, dndEnabled: false,
                canFind: true, controlsAvailable: true, torch: false, torchAvailable: true, ringer: "normal", hasADB: connected)),
            notices: [], conversation: connected ? [
                OverviewConversationRow(id: "1", title: "Você", preview: "Manda aquela foto do quadro?", date: .now, outgoing: true),
                OverviewConversationRow(id: "2", title: "Pixel 9 Pro", preview: "Proposta_final.pdf", date: .now, outgoing: false)] : [],
            photos: [], clipboardText: connected ? "Reunião remarcada para 16h — sala 3B, link no convite." : nil, clipboardDate: .now)
    }

    func testOverviewRendersConnectedAndDisconnected() throws {
        for scheme in [ColorScheme.dark, .light] {
            for connected in [true, false] {
                let view = OverviewScreen(data: overviewData(connected: connected), actions: OverviewActions(), extras: AnyView(EmptyView()))
                let image = try render(view, name: "visao-geral-\(connected ? "conectado" : "desconectado")", scheme: scheme, width: 944, height: 700)
                XCTAssertEqual(image.size.width, 944, accuracy: 1)
            }
        }
    }

    func testOverviewRendersInANarrowWindow() throws {
        _ = try render(OverviewScreen(data: overviewData(connected: true), actions: OverviewActions(), extras: AnyView(EmptyView())),
                       name: "visao-geral-estreita", scheme: .dark, width: 484, height: 900)
    }

    // MARK: Whole window

    /// Smoke test: the whole window builds and draws for every section without a connected phone. (Scrolling content does not
    /// show in ImageRenderer, so the sidebar is what makes the image non-blank; the per-screen checks cover their own views.)
    func testEverySectionRendersInTheWindow() throws {
        let model = NexusModel()
        for section in Section.allCases {
            model.section = section
            for scheme in [ColorScheme.dark, .light] {
                let image = try render(Dashboard(model: model), name: "janela-\(section.id.lowercased().replacingOccurrences(of: " ", with: "-"))",
                                       scheme: scheme, width: 1240, height: 790)
                XCTAssertEqual(image.size.width, 1240, accuracy: 1, "\(section)")
            }
        }
    }

    // MARK: Apps

    func appsData(loaded: Bool, session: Bool = false) -> AppsScreenData {
        let apps = loaded ? ["Câmera", "WhatsApp", "Spotify", "Nubank", "Maps", "iFood", "Gmail", "Fotos"].enumerated().map {
            AndroidApp(component: "com.example.app\($0.offset)/.Main", label: $0.element) } : []
        return AppsScreenData(phoneName: "Pixel 9 Pro", apps: apps, listLoaded: loaded,
                              pins: loaded ? [apps[1].id, apps[2].id, apps[4].id] : [], icons: [:], active: true,
                              launcherAvailable: true, canLaunch: true, needsWirelessSetup: false,
                              session: session ? AppsSession(title: "Controle do celular", state: "Em andamento") : nil)
    }

    func testAppsScreenRendersEmptyAndWithApps() throws {
        for scheme in [ColorScheme.dark, .light] {
            for (name, data) in [("vazio", appsData(loaded: false)), ("com-apps", appsData(loaded: true, session: true))] {
                let image = try render(AppsScreen(data: data, actions: AppsScreenActions()), name: "apps-\(name)", scheme: scheme,
                                       width: 944, height: 720)
                XCTAssertEqual(image.size.width, 944, accuracy: 1)
            }
        }
    }

    func testAppsScreenRendersInANarrowWindow() throws {
        _ = try render(AppsScreen(data: appsData(loaded: true), actions: AppsScreenActions()), name: "apps-estreita", scheme: .dark,
                       width: 484, height: 1000)
    }

    // MARK: Coming soon and menu bar

    func testComingSoonRendersForEverySoonSection() throws {
        for section in Section.allCases where section.isComingSoon {
            for scheme in [ColorScheme.dark, .light] {
                let image = try render(ComingSoonView(section: section), name: "em-breve-\(section.id.lowercased().replacingOccurrences(of: " ", with: "-"))",
                                       scheme: scheme, width: 700, height: 420)
                XCTAssertEqual(image.size.width, 700, accuracy: 1)
            }
        }
    }

    func testMenuBarContentRendersWithoutPhone() throws {
        let model = NexusModel()
        for scheme in [ColorScheme.dark, .light] {
            let image = try render(MenuBarPanel(model: model, open: { _ in }, quit: {}), name: "menu-da-barra", scheme: scheme,
                                   width: 340, height: 460)
            XCTAssertEqual(image.size.width, 340, accuracy: 1)
        }
    }

    // MARK: Review fixes

    /// Sidebar at the smallest window height: the footer (Dispositivos, Configurações) must stay visible, outside the scroll.
    func testSidebarKeepsTheFooterVisibleInASmallWindow() throws {
        let model = NexusModel()
        let image = try render(Sidebar(model: model, pinnedApps: [], openApp: { _ in }, manageApps: {}),
                               name: "barra-lateral-pequena", scheme: .dark, width: 244, height: 570)
        // The footer sits in the bottom 60 points; it must have drawn something other than the flat background there.
        let bottom = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            .cropping(to: CGRect(x: 0, y: bottom(of: image) - 60, width: 244, height: 60))
        XCTAssertGreaterThan(Self.distinctColors(in: NSImage(cgImage: try XCTUnwrap(bottom), size: NSSize(width: 244, height: 60))), 12)
    }

    private func bottom(of image: NSImage) -> Int { Int(image.size.height) }

    func testWindowRendersAtTheMinimumSize() throws {
        let model = NexusModel()
        for section in [Section.overview, .notifications, .remote, .apps, .settings, .conversation] {
            model.section = section
            let image = try render(Dashboard(model: model), name: "janela-minima-\(section.id.lowercased())", scheme: .dark, width: 780, height: 570)
            XCTAssertEqual(image.size.height, 570, accuracy: 1)
        }
    }

    func testMiniPlayerExpandedFitsALowWindow() throws {
        let view = MiniPlayerFitProbe()
        let image = try render(view, name: "mini-player-janela-baixa", scheme: .dark, width: 420, height: 520)
        XCTAssertEqual(image.size.height, 520, accuracy: 1)
    }
}

/// The expanded player with a long queue, in a 520-point-high frame: Fechar must stay on screen.
private struct MiniPlayerFitProbe: View {
    var body: some View {
        var message = Message("mediaStatus")
        message.name = "Abracadabra"; message.artist = "Lady Gaga"; message.albumName = "Mayhem"
        message.durationMs = 223_000; message.positionMs = 56_000; message.playing = true; message.canSeek = true
        message.canLike = true; message.hasQueue = true
        let queue = (1...10).map { MediaQueueItem(id: Int64($0), title: "Faixa \($0)") }
        return MiniPlayer(state: MediaPlayerState(message: message, receivedAt: .now), art: nil, phoneName: "Pixel", queue: queue,
                          queueActive: 1, output: .mac, connecting: false, canControl: true, canChooseOutput: true, expanded: true,
                          volume: 40, onVolume: { _ in }, onCommand: { _ in }, onSeek: { _ in }, onLike: { _ in }, onOpenQueue: {},
                          onPick: { _ in }, onOutput: { _ in }, onToggleExpanded: {}, onClose: {}, maxHeight: 500)
    }
}

// MARK: Mini player height

/// Records the size a view takes when offered a large area, to prove the player hugs its content.
private final class SizeBox { var size: CGSize = .zero }

private struct MeasuringLayout: Layout {
    let box: SizeBox
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(proposal) ?? .zero
        box.size = size
        return size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: proposal)
    }
}

@MainActor
extension ShellRenderTests {
    private func playerHeight(expanded: Bool, queue: Int, offered: CGFloat, maxHeight: CGFloat) -> CGFloat {
        var message = Message("mediaStatus")
        message.name = "Abracadabra"; message.artist = "Lady Gaga"; message.albumName = "Mayhem"
        message.durationMs = 223_000; message.positionMs = 56_000; message.playing = true; message.canSeek = true
        message.hasQueue = queue > 0
        let items = (0..<queue).map { MediaQueueItem(id: Int64($0), title: "Faixa \($0)") }
        let box = SizeBox()
        let player = MiniPlayer(state: MediaPlayerState(message: message, receivedAt: .now), art: nil, phoneName: "Pixel", queue: items,
                                queueActive: 0, output: .mac, connecting: false, canControl: true, canChooseOutput: true, expanded: expanded,
                                volume: 40, onVolume: { _ in }, onCommand: { _ in }, onSeek: { _ in }, onLike: { _ in }, onOpenQueue: {},
                                onPick: { _ in }, onOutput: { _ in }, onToggleExpanded: {}, onClose: {}, maxHeight: maxHeight)
        let renderer = ImageRenderer(content: MeasuringLayout(box: box) { player }.frame(width: 420, height: offered, alignment: .bottomTrailing))
        _ = renderer.nsImage
        return box.size.height
    }

    func testCollapsedPlayerHugsItsContentInATallWindow() {
        let height = playerHeight(expanded: false, queue: 0, offered: 900, maxHeight: 860)
        XCTAssertLessThan(height, 110, "o player recolhido não pode esticar até a altura da janela")
        XCTAssertGreaterThan(height, 40)
    }

    func testExpandedPlayerNeverExceedsTheAvailableHeight() {
        for available: CGFloat in [530, 700, 860] {
            let height = playerHeight(expanded: true, queue: 6, offered: available + 40, maxHeight: available)
            XCTAssertLessThanOrEqual(height, available + 0.5, "available \(available)")
        }
        // With room to spare it takes only what it needs, not the whole window.
        XCTAssertLessThan(playerHeight(expanded: true, queue: 0, offered: 900, maxHeight: 860), 560)
    }
}



// MARK: Gallery

@MainActor
extension ShellRenderTests {
    private func makeTransfers() -> FileTransfers {
        FileTransfers(storage: FileManager.default.temporaryDirectory.appendingPathComponent("gallery-render-\(UUID().uuidString)"), send: { _, _ in })
    }

    private func sampleMedia(count: Int) throws -> (GalleryModel, [MediaEntry]) {
        let day: Int64 = 86_400
        let base: Int64 = 1_764_000_000
        let items: [MediaEntry] = try (0..<count).map { index in
            let mime = index % 5 == 4 ? "video/mp4" : "image/jpeg"
            let json = #"{"id":"\#(100 + index)","name":"PXL_\#(index).jpg","mime":"\#(mime)","album":"Câmera","at":\#(base - Int64(index / 6) * day),"size":2400000}"#
            return try JSONDecoder().decode(MediaEntry.self, from: Data(json.utf8))
        }
        let albums = try ["Câmera", "Screenshots", "WhatsApp", "Downloads"].enumerated().map {
            try JSONDecoder().decode(MediaAlbum.self, from: Data(#"{"id":"\#($0.offset + 1)","name":"\#($0.element)"}"#.utf8))
        }
        var thumbnails: [String: NSImage] = [:]
        for (index, item) in items.enumerated() {
            let image = NSImage(size: NSSize(width: 160, height: 160))
            image.lockFocus()
            NSGradient(colors: [NSColor(hue: CGFloat(index % 9) / 9, saturation: 0.5, brightness: 0.8, alpha: 1), .black])?
                .draw(in: NSRect(x: 0, y: 0, width: 160, height: 160), angle: 90)
            image.unlockFocus()
            thumbnails[item.id] = image
        }
        let gallery = GalleryModel()
        gallery.loadForSnapshot(items: items, albums: albums, thumbnails: thumbnails, more: true)
        return (gallery, items)
    }

    func testGalleryRendersWithPhotos() throws {
        let (gallery, _) = try sampleMedia(count: 18)
        for scheme in [ColorScheme.dark, .light] {
            let browser = GalleryBrowser(gallery: gallery, files: makeTransfers(), canTransfer: true, grouping: .constant(.day), deviceID: "phone")
            let image = try render(browser, name: "fotos", scheme: scheme, width: 944, height: 1000)
            XCTAssertEqual(image.size.width, 944, accuracy: 1)
        }
    }

    func testGalleryRendersWhenNarrowAndEmpty() throws {
        let gallery = GalleryModel()
        _ = try render(GalleryBrowser(gallery: gallery, files: makeTransfers(), canTransfer: false, grouping: .constant(.day), deviceID: "phone"),
                       name: "fotos-vazia", scheme: .dark, width: 484, height: 500)
        let (full, _) = try sampleMedia(count: 12)
        _ = try render(GalleryBrowser(gallery: full, files: makeTransfers(), canTransfer: true, grouping: .constant(.month), deviceID: "phone"),
                       name: "fotos-estreita", scheme: .dark, width: 484, height: 900)
    }

    func testViewerRendersEveryState() throws {
        let (gallery, items) = try sampleMedia(count: 6)
        let photo = NSImage(size: NSSize(width: 400, height: 300))
        photo.lockFocus(); NSColor.systemPink.setFill(); NSRect(x: 0, y: 0, width: 400, height: 300).fill(); photo.unlockFocus()
        let states: [(String, GalleryModel.Preview.Content)] = [("imagem", .image(photo)), ("carregando", .loading), ("falhou", .failed("A prévia não chegou."))]
        for (name, content) in states {
            gallery.preview = GalleryModel.Preview(id: "p", item: items[1], fromTransfer: false, content: content)
            let viewer = GalleryViewer(gallery: gallery, files: makeTransfers(), canTransfer: true, items: items, isFavorite: { _ in true }, toggleFavorite: { _ in })
            let image = try render(viewer, name: "visualizador-\(name)", scheme: .dark, width: 980, height: 640)
            XCTAssertEqual(image.size.height, 640, accuracy: 1)
        }
    }
}


// MARK: Content never overflows its container

@MainActor
extension ShellRenderTests {
    /// The width a view asks for when offered `offered` points: more than that means it would be cut off in a smaller window.
    private func requestedWidth<V: View>(_ view: V, offered: CGFloat) -> CGFloat {
        let box = SizeBox()
        let renderer = ImageRenderer(content: MeasuringLayout(box: box) { view }.frame(width: offered, height: 900, alignment: .topLeading))
        _ = renderer.nsImage
        return box.size.width
    }

    func testOverviewNeverAsksForMoreWidthThanItIsOffered() {
        for offered: CGFloat in [484, 560, 700, 850] {
            let view = OverviewScreen(data: overviewData(connected: true), actions: OverviewActions(), extras: AnyView(EmptyView()))
            XCTAssertLessThanOrEqual(requestedWidth(view, offered: offered), offered + 0.5, "offered \(offered)")
        }
    }

    func testAppsScreenNeverAsksForMoreWidthThanItIsOffered() {
        for offered: CGFloat in [484, 640] {
            XCTAssertLessThanOrEqual(requestedWidth(AppsScreen(data: appsData(loaded: true), actions: AppsScreenActions()), offered: offered),
                                     offered + 0.5, "offered \(offered)")
        }
    }

    func testWidthProbeMapsWidthToLayoutChoice() {
        XCTAssertFalse(OverviewScreen.isWide(width: 0))
        XCTAssertFalse(OverviewScreen.isWide(width: 859))
        XCTAssertTrue(OverviewScreen.isWide(width: 860))
    }
}


// MARK: Files screen

@MainActor
extension ShellRenderTests {
    private func filesFixture() throws -> (FileTransfers, PixelFilesModel) {
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent("files-render-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        let offer = #"{"id":"6f9619ff-8b86-d011-b42d-00c04fc964ff","name":"Roteiro_viagem.docx","mime":"application/msword","size":312000,"hash":"x"}"#
        let sent = #"[{"peerID":"6f9619ff-8b86-d011-b42d-00c04fc964ff","offer":\#(offer),"url":"file:///tmp/Roteiro_viagem.docx","date":780000000}]"#
        try Data(sent.utf8).write(to: storage.appendingPathComponent("sent-history.json"))
        let files = FileTransfers(storage: storage, send: { _, _ in })
        let pixel = PixelFilesModel(downloads: storage)
        pixel.shell = { command in
            if command.hasPrefix("ls -la") {
                return "drwxrws--- 2 u0 media_rw 4096 2025-11-26 10:15 Download\ndrwxrws--- 2 u0 media_rw 4096 2025-11-26 10:15 DCIM\ndrwxrws--- 2 u0 media_rw 4096 2025-11-26 10:15 Documents\ndrwxrws--- 2 u0 media_rw 4096 2025-11-26 10:15 Music\ndrwxrws--- 2 u0 media_rw 4096 2025-11-26 10:15 Recordings"
            }
            if command.hasPrefix("df") { return "Filesystem 1K-blocks Used Available Use% Mounted on\n/dev/fuse 250000000 176000000 74000000 70% /storage" }
            if command.hasPrefix("du") { return "74000000\t/sdcard/DCIM\n52000000\t/sdcard/Music\n21000000\t/sdcard/Android/media/com.whatsapp" }
            return "Download 38\nDCIM 1204\nDocuments 12\nMusic 86\nRecordings 9"
        }
        await_ { await pixel.open(PixelPath.root) }
        await_ { await pixel.loadOverview() }
        return (files, pixel)
    }

    /// Runs async work to completion from a synchronous test body.
    private func await_(_ work: @escaping () async -> Void) {
        let done = expectation(description: "async")
        Task { await work(); done.fulfill() }
        wait(for: [done], timeout: 5)
    }

    func testFilesScreenRendersBothTabs() throws {
        let (files, pixel) = try filesFixture()
        let model = NexusModel()
        for scheme in [ColorScheme.dark, .light] {
            _ = try render(FilesScreen(model: model, files: files, pixel: pixel, chooseFiles: {}), name: "arquivos-transferencias",
                           scheme: scheme, width: 944, height: 640)
            _ = try render(FilesScreen(model: model, files: files, pixel: pixel, chooseFiles: {}, initialTab: .pixel, pixelAvailable: true),
                           name: "arquivos-pixel", scheme: scheme, width: 944, height: 640)
        }
        _ = try render(FilesScreen(model: model, files: files, pixel: pixel, chooseFiles: {}, initialTab: .pixel, pixelAvailable: false),
                       name: "arquivos-sem-adb", scheme: .dark, width: 944, height: 520)
        _ = try render(FilesScreen(model: model, files: files, pixel: pixel, chooseFiles: {}), name: "arquivos-estreita",
                       scheme: .dark, width: 484, height: 900)
    }
}
