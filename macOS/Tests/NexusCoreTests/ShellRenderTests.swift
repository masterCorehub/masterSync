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

    private func overviewData(connected: Bool) -> OverviewData {
        OverviewData(
            name: "Pixel 9 Pro", active: connected, battery: connected ? 82 : nil, charging: connected,
            status: [("Conexão", connected ? "Rede local" : "Desconectado"), ("Notificações", "Espelhando"),
                     ("Área de transferência", "Sincronizando"), ("Arquivos", "Aceitando")],
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

    private func appsData(loaded: Bool, session: Bool = false) -> AppsScreenData {
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
}
