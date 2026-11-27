import AppKit
import NexusCore
@testable import NexusMasterSync
import SwiftUI
import XCTest

@MainActor
final class MiniPlayerRenderTests: XCTestCase {
    private func sampleState(playing: Bool = true) -> MediaPlayerState {
        var message = Message("mediaStatus")
        message.name = "Abracadabra"
        message.artist = "Lady Gaga"
        message.albumName = "Mayhem"
        message.year = 2025
        message.trackNumber = 2
        message.trackCount = 14
        message.durationMs = 223_000
        message.positionMs = 56_000
        message.speed = 1
        message.playing = playing
        message.artKey = "k"
        message.canSeek = true
        message.canLike = true
        message.liked = false
        message.hasQueue = true
        return MediaPlayerState(message: message, receivedAt: .now)
    }

    private func sampleArt() -> NSImage {
        let image = NSImage(size: NSSize(width: 160, height: 160))
        image.lockFocus()
        NSGradient(colors: [.darkGray, .lightGray])?.draw(in: NSRect(x: 0, y: 0, width: 160, height: 160), angle: 45)
        image.unlockFocus()
        return image
    }

    private func renderMini(expanded: Bool, scheme: ColorScheme, output: MediaOutput) throws -> NSImage {
        let palette = NexusPalette(scheme: scheme)
        let player = MiniPlayer(
            state: sampleState(), art: sampleArt(), phoneName: "Pixel 9 Pro", queue: [MediaQueueItem(id: 1, title: "Faixa um"), MediaQueueItem(id: 2, title: "Faixa dois")],
            queueActive: 1, output: output, connecting: false, canControl: true, canChooseOutput: true, expanded: expanded,
            volume: output == .mac ? 40 : nil, onVolume: { _ in }, onCommand: { _ in }, onSeek: { _ in }, onLike: { _ in },
            onOpenQueue: {}, onPick: { _ in }, onOutput: { _ in }, onToggleExpanded: {}, onClose: {})
        let view = player.padding(28).background(palette.canvas).environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return try XCTUnwrap(renderer.nsImage)
    }

    func testMiniPlayerRendersCollapsedAndExpanded() throws {
        for (name, scheme) in [("claro", ColorScheme.light), ("escuro", ColorScheme.dark)] {
            let mini = try renderMini(expanded: false, scheme: scheme, output: .mac)
            XCTAssertEqual(mini.size.width, 416, accuracy: 1)
            XCTAssertGreaterThan(mini.size.height, 90)
            let full = try renderMini(expanded: true, scheme: scheme, output: .mac)
            XCTAssertGreaterThan(full.size.height, 380)
            let phone = try renderMini(expanded: true, scheme: scheme, output: .phone)
            XCTAssertGreaterThan(phone.size.height, 380)
            for (suffix, image) in [("mini", mini), ("completo", full)] {
                if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: "/private/tmp/claude-501/redesign/mini-player-\(name)-\(suffix).png"))
                }
            }
        }
    }
}
